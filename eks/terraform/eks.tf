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

  #---------------------------------------
  # Prometheus Stack for Monitoring
  #---------------------------------------
  enable_kube_prometheus_stack = var.enable_kube_prometheus_stack
  kube_prometheus_stack = {
    chart_version = "65.7.0"
    values = [
      <<-EOT
        prometheus:
          prometheusSpec:
            resources:
              limits:
                cpu: 1000m
                memory: 2Gi
              requests:
                cpu: 500m
                memory: 1Gi
            retention: 7d
            storageSpec:
              volumeClaimTemplate:
                spec:
                  storageClassName: gp3
                  accessModes: ["ReadWriteOnce"]
                  resources:
                    requests:
                      storage: 50Gi
        grafana:
          enabled: true
          adminPassword: "fraud-detection-grafana"
          resources:
            limits:
              cpu: 200m
              memory: 256Mi
            requests:
              cpu: 100m
              memory: 128Mi
          persistence:
            enabled: true
            storageClassName: gp3
            size: 10Gi
        alertmanager:
          enabled: false
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

#---------------------------------------------------------------
# EKS Pod Identity for JupyterHub
#---------------------------------------------------------------
resource "aws_iam_role" "jupyterhub_pod_identity_role" {
  name_prefix = "${local.name}-jupyterhub-pod-identity-"

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

  managed_policy_arns = [
    aws_iam_policy.jupyterhub_s3_policy.arn,
    aws_iam_policy.jupyterhub_emr_policy.arn
  ]

  tags = local.tags
}

resource "aws_eks_pod_identity_association" "jupyterhub" {
  cluster_name    = module.eks.cluster_name
  namespace       = "jupyterhub"
  service_account = "jupyterhub"
  role_arn        = aws_iam_role.jupyterhub_pod_identity_role.arn

  depends_on = [module.eks]
}

resource "aws_eks_pod_identity_association" "jupyterhub_user" {
  cluster_name    = module.eks.cluster_name
  namespace       = "jupyterhub"
  service_account = "jupyterhub-user-sa"
  role_arn        = aws_iam_role.jupyterhub_pod_identity_role.arn

  depends_on = [module.eks]
}

#---------------------------------------------------------------
# IAM Policies for JupyterHub
#---------------------------------------------------------------
resource "aws_iam_policy" "jupyterhub_s3_policy" {
  name_prefix = "${local.name}-jupyterhub-s3-"
  description = "IAM policy for JupyterHub S3 access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          module.s3_bucket.s3_bucket_arn,
          "${module.s3_bucket.s3_bucket_arn}/*"
        ]
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_policy" "jupyterhub_emr_policy" {
  name_prefix = "${local.name}-jupyterhub-emr-"
  description = "IAM policy for JupyterHub EMR access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "emr-containers:StartJobRun",
          "emr-containers:ListJobRuns",
          "emr-containers:DescribeJobRun",
          "emr-containers:CancelJobRun"
        ]
        Resource = [
          module.emr_containers.virtual_cluster_arn,
          "${module.emr_containers.virtual_cluster_arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = module.emr_containers.iam_role_arn
      }
    ]
  })

  tags = local.tags
}
