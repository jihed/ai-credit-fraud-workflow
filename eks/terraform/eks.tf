#---------------------------------------------------------------
# EKS Cluster
#---------------------------------------------------------------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.33"

  cluster_name    = local.name
  cluster_version = var.eks_cluster_version

  # WARNING: Avoid using this option in production accounts
  cluster_endpoint_public_access = true

  # Modern authentication mode with Pod Identity
  authentication_mode                      = "API_AND_CONFIG_MAP"
  enable_cluster_creator_admin_permissions = true

  vpc_id = module.vpc.vpc_id
  # Use secondary CIDR subnets for EKS control plane
  subnet_ids = module.vpc.intra_subnets

  # Combine root account, current user/role and additional roles for KMS key access
  kms_key_administrators = distinct(concat([
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"],
    var.kms_key_admin_roles,
    [data.aws_iam_session_context.current.issuer_arn]
  ))

  #---------------------------------------
  # EKS Managed Add-ons
  #---------------------------------------
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent    = true
      before_compute = true
      preserve       = true
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }
    eks-pod-identity-agent = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent = true
    }
  }

  #---------------------------------------
  # Security Group Rules
  #---------------------------------------
  cluster_security_group_additional_rules = {
    ingress_nodes_ephemeral_ports_tcp = {
      description                = "Nodes on ephemeral ports"
      protocol                   = "tcp"
      from_port                  = 1025
      to_port                    = 65535
      type                       = "ingress"
      source_node_security_group = true
    }
  }

  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
    ingress_cluster_to_node_all_traffic = {
      description                   = "Cluster API to Nodegroup all traffic"
      protocol                      = "-1"
      from_port                     = 0
      to_port                       = 0
      type                          = "ingress"
      source_cluster_security_group = true
    }
  }

  #---------------------------------------
  # EKS Managed Node Groups
  #---------------------------------------
  eks_managed_node_group_defaults = {
    iam_role_additional_policies = {
      AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    }
    ebs_optimized = true
    block_device_mappings = {
      xvda = {
        device_name = "/dev/xvda"
        ebs = {
          volume_size = 100
          volume_type = "gp3"
          encrypted   = true
        }
      }
    }
  }

  eks_managed_node_groups = {
    # Core node group for system components and add-ons
    core_node_group = {
      name        = "core-node-group"
      description = "Core managed node group for system components"

      # Use secondary CIDR subnets for nodes
      subnet_ids = module.vpc.intra_subnets

      min_size     = 2
      max_size     = 6
      desired_size = 3

      instance_types = ["m5.xlarge"]

      labels = {
        WorkerType               = "ON_DEMAND"
        NodeGroupType            = "core"
        "karpenter.sh/discovery" = local.name
      }

      taints = [
        {
          key    = "system"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      ]

      tags = {
        Name = "${local.name}-core-node-group"
      }
    }
  }

  tags = local.tags
}

#---------------------------------------------------------------
# Pod Identity Association for VPC CNI
#---------------------------------------------------------------
resource "aws_iam_role" "vpc_cni_pod_identity_role" {
  name_prefix = "${local.name}-vpc-cni-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      }
    ]
  })



  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "vpc_cni_pod_identity_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.vpc_cni_pod_identity_role.name
}

resource "aws_eks_pod_identity_association" "vpc_cni" {
  cluster_name    = module.eks.cluster_name
  namespace       = "kube-system"
  service_account = "aws-node"
  role_arn        = aws_iam_role.vpc_cni_pod_identity_role.arn

  depends_on = [module.eks]
}

#---------------------------------------------------------------
# Pod Identity Association for EBS CSI Driver
#---------------------------------------------------------------
resource "aws_iam_role" "ebs_csi_pod_identity_role" {
  name_prefix = "${local.name}-ebs-csi-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi_pod_identity_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.ebs_csi_pod_identity_role.name
}

resource "aws_eks_pod_identity_association" "ebs_csi" {
  cluster_name    = module.eks.cluster_name
  namespace       = "kube-system"
  service_account = "ebs-csi-controller-sa"
  role_arn        = aws_iam_role.ebs_csi_pod_identity_role.arn

  depends_on = [module.eks]
}


#---------------------------------------------------------------
# EKS Blueprints Addons
#---------------------------------------------------------------
module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.20"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  #---------------------------------------
  # Karpenter Autoscaler for EKS Cluster
  #---------------------------------------
  enable_karpenter                  = true
  karpenter_enable_spot_termination = true
  karpenter_node = {
    iam_role_additional_policies = {
      AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    }
  }
  karpenter = {
    chart_version       = "1.6.0"
    repository_username = data.aws_ecrpublic_authorization_token.token.user_name
    repository_password = data.aws_ecrpublic_authorization_token.token.password
  }

  #---------------------------------------
  # AWS Load Balancer Controller
  #---------------------------------------
  enable_aws_load_balancer_controller = true
  aws_load_balancer_controller = {
    chart_version = "2.13.4"
  }

  #---------------------------------------
  # AWS for FluentBit - DaemonSet
  #---------------------------------------
  enable_aws_for_fluentbit = true
  aws_for_fluentbit_cw_log_group = {
    use_name_prefix   = false
    name              = "/${local.name}/aws-fluentbit-logs"
    retention_in_days = 30
  }
  aws_for_fluentbit = {
    chart_version = "0.1.34"
    values = [
      <<-EOT
        cloudWatchLogs:
          enabled: true
          logGroupName: /${local.name}/aws-fluentbit-logs
          logStreamName: fluentbit-log-stream
          region: ${local.region}
          autoCreateGroup: false
        firehose:
          enabled: false
        kinesis:
          enabled: false
        elasticsearch:
          enabled: false
      EOT
    ]
  }

  tags = local.tags
}
