#---------------------------------------------------------------
# EKS Cluster
#---------------------------------------------------------------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.33"

  cluster_name                   = local.name
  cluster_version                = var.eks_cluster_version
  cluster_endpoint_public_access = true

  # Combine all subnets for EKS cluster
  subnet_ids = concat(module.vpc.private_subnets, module.vpc.intra_subnets)

  # EKS Addons
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent              = true
      before_compute           = true
      service_account_role_arn = module.vpc_cni_irsa.iam_role_arn
      configuration_values = jsonencode({
        env = {
          # Reference docs https://docs.aws.amazon.com/eks/latest/userguide/cni-increase-ip-addresses.html
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }
    eks-pod-identity-agent = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_driver_irsa.iam_role_arn
    }
  }

  # EKS Managed Node Groups - Only for system components
  eks_managed_node_groups = {
    system = {
      instance_types = ["m5.large"]

      min_size     = 1
      max_size     = 3
      desired_size = 2

      # Use secondary CIDR subnets for better IP management
      subnet_ids = module.vpc.intra_subnets

      labels = {
        WorkerType    = "ON_DEMAND"
        NodeGroupType = "system"
      }

      taints = [
        {
          key    = "system"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      ]

      tags = {
        Name = "${local.name}-system-node"
      }
    }
  }

  # aws-auth configmap
  manage_aws_auth_configmap = true
  aws_auth_roles = [
    # We need to add in the Karpenter node IAM role for nodes launched by Karpenter
    {
      rolearn  = module.eks_blueprints_addons.karpenter.node_iam_role_arn
      username = "system:node:{{EC2PrivateDNSName}}"
      groups = [
        "system:bootstrappers",
        "system:nodes",
      ]
    }
  ]

  tags = local.tags
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
  # Metrics Server
  #---------------------------------------
  enable_metrics_server = true
  metrics_server = {
    chart_version = "3.12.2"
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

  #---------------------------------------
  # NVIDIA GPU Operator (Essential for RAPIDS)
  #---------------------------------------
  enable_nvidia_gpu_operator = var.enable_nvidia_gpu_operator
  nvidia_gpu_operator = {
    chart_version = "v24.9.0"
    values = [
      <<-EOT
        operator:
          defaultRuntime: containerd
        driver:
          enabled: true
          version: "550.90.07"
        toolkit:
          enabled: true
        devicePlugin:
          enabled: true
        dcgmExporter:
          enabled: true
        gfd:
          enabled: true
        migManager:
          enabled: false
        nodeStatusExporter:
          enabled: true
        gds:
          enabled: false
        vgpuManager:
          enabled: false
        vgpuDeviceManager:
          enabled: false
        sandboxWorkloads:
          enabled: false
        vfioManager:
          enabled: false
        tolerations:
          - key: nvidia.com/gpu
            operator: Exists
            effect: NoSchedule
      EOT
    ]
  }



  tags = local.tags
}

#---------------------------------------------------------------
# IRSA for VPC CNI
#---------------------------------------------------------------
module "vpc_cni_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.55"

  role_name_prefix      = "VPC-CNI-IRSA"
  attach_vpc_cni_policy = true
  vpc_cni_enable_ipv4   = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-node"]
    }
  }

  tags = local.tags
}

#---------------------------------------------------------------
# IRSA for EBS CSI Driver
#---------------------------------------------------------------
module "ebs_csi_driver_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.55"

  role_name_prefix      = "EBS-CSI-Driver-IRSA"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = local.tags
}


