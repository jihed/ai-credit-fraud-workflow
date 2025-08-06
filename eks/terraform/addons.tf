#---------------------------------------------------------------
# EKS Pod Identity for EBS CSI Driver
#---------------------------------------------------------------
resource "aws_iam_role" "ebs_csi_driver_role" {
  name = format("%s-%s", local.name, "ebs-csi-driver-role")

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

resource "aws_iam_role_policy_attachment" "ebs_csi_driver_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.ebs_csi_driver_role.name
}

resource "aws_eks_pod_identity_association" "ebs_csi_driver" {
  cluster_name    = module.eks.cluster_name
  namespace       = "kube-system"
  service_account = "ebs-csi-controller-sa"
  role_arn        = aws_iam_role.ebs_csi_driver_role.arn
}

#---------------------------------------------------------------
# EKS Pod Identity for EFS CSI Driver
#---------------------------------------------------------------
resource "aws_iam_role" "efs_csi_driver_role" {
  name = format("%s-%s", local.name, "efs-csi-driver-role")

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

resource "aws_iam_role_policy_attachment" "efs_csi_driver_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
  role       = aws_iam_role.efs_csi_driver_role.name
}

resource "aws_eks_pod_identity_association" "efs_csi_driver" {
  cluster_name    = module.eks.cluster_name
  namespace       = "kube-system"
  service_account = "efs-csi-controller-sa"
  role_arn        = aws_iam_role.efs_csi_driver_role.arn
}

#---------------------------------------------------------------
# EKS Blueprints Addons
#---------------------------------------------------------------
module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.2"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  #---------------------------------------
  # Amazon EKS Managed Add-ons
  #---------------------------------------
  eks_addons = {
    aws-ebs-csi-driver = {
      # EKS Pod Identity will handle IAM permissions
    }
    aws-efs-csi-driver = {
      # EKS Pod Identity will handle IAM permissions
    }
    coredns = {
      preserve = true
    }
    vpc-cni = {
      preserve = true
    }
    kube-proxy = {
      preserve = true
    }
  }

  #---------------------------------------
  # Kubernetes Add-ons
  #---------------------------------------

  #---------------------------------------
  # Metrics Server
  #---------------------------------------
  enable_metrics_server = true
  metrics_server = {
    values = [templatefile("${path.module}/helm-values/metrics-server-values.yaml", {})]
  }

  #---------------------------------------
  # AWS Load Balancer Controller
  #---------------------------------------
  enable_aws_load_balancer_controller = true
  aws_load_balancer_controller = {
    chart_version = "1.8.1"
  }

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
  # CloudWatch metrics for EKS
  #---------------------------------------
  enable_aws_cloudwatch_metrics = true
  aws_cloudwatch_metrics = {
    chart_version = "0.0.11"
    values        = [templatefile("${path.module}/helm-values/aws-cloudwatch-metrics-values.yaml", {})]
  }

  #---------------------------------------
  # AWS for Fluent Bit - Enhanced Log Aggregation
  #---------------------------------------
  enable_aws_for_fluentbit = true
  aws_for_fluentbit = {
    chart_version = "0.1.32"
    values = [templatefile("${path.module}/helm-values/aws-for-fluentbit-values.yaml", {
      cluster_name = module.eks.cluster_name
      region       = local.region
      account_id   = data.aws_caller_identity.current.account_id
    })]
  }

  #---------------------------------------
  # Prometheus and Grafana Stack
  #---------------------------------------
  enable_kube_prometheus_stack = true
  kube_prometheus_stack = {
    values = [
      var.enable_amazon_prometheus ? templatefile("${path.module}/helm-values/kube-prometheus-amp-enable.yaml", {
        region              = local.region
        amp_sa              = local.amp_ingest_service_account
        amp_irsa            = aws_iam_role.amp_ingest_role[0].arn
        amp_remotewrite_url = "https://aps-workspaces.${local.region}.amazonaws.com/workspaces/${aws_prometheus_workspace.amp[0].id}/api/v1/remote_write"
        amp_url             = "https://aps-workspaces.${local.region}.amazonaws.com/workspaces/${aws_prometheus_workspace.amp[0].id}"
        }) : templatefile("${path.module}/helm-values/kube-prometheus.yaml", {
        grafana_admin_password = data.aws_secretsmanager_secret_version.admin_password_version.secret_string
      })
    ]
    chart_version = "65.5.1"
    set_sensitive = [
      {
        name  = "grafana.adminPassword"
        value = data.aws_secretsmanager_secret_version.admin_password_version.secret_string
      }
    ]
  }



  tags = local.tags
}

#---------------------------------------------------------------
# NVIDIA DCGM Exporter for GPU Metrics
#---------------------------------------------------------------
resource "kubernetes_namespace" "nvidia_monitoring" {
  count = var.enable_nvidia_gpu_monitoring ? 1 : 0

  metadata {
    name = "nvidia-monitoring"
    labels = {
      name = "nvidia-monitoring"
    }
  }

  depends_on = [module.eks]
}

resource "kubernetes_daemonset" "nvidia_dcgm_exporter" {
  count = var.enable_nvidia_gpu_monitoring ? 1 : 0
  metadata {
    name      = "nvidia-dcgm-exporter"
    namespace = "kube-system"
    labels = {
      app = "nvidia-dcgm-exporter"
    }
  }

  spec {
    selector {
      match_labels = {
        app = "nvidia-dcgm-exporter"
      }
    }

    template {
      metadata {
        labels = {
          app = "nvidia-dcgm-exporter"
        }
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "9400"
        }
      }

      spec {
        toleration {
          key      = "nvidia.com/gpu"
          operator = "Exists"
          effect   = "NoSchedule"
        }

        node_selector = {
          "accelerator" = "nvidia"
        }

        container {
          name  = "nvidia-dcgm-exporter"
          image = "nvcr.io/nvidia/k8s/dcgm-exporter:3.3.5-3.4.0-ubuntu22.04"

          port {
            name           = "metrics"
            container_port = 9400
          }

          security_context {
            run_as_non_root = false
            run_as_user     = 0
          }

          volume_mount {
            name       = "proc"
            mount_path = "/host/proc"
            read_only  = true
          }

          volume_mount {
            name       = "sys"
            mount_path = "/host/sys"
            read_only  = true
          }

          env {
            name  = "DCGM_EXPORTER_LISTEN"
            value = ":9400"
          }

          env {
            name  = "DCGM_EXPORTER_KUBERNETES"
            value = "true"
          }

          resources {
            requests = {
              memory = "128Mi"
              cpu    = "50m"
            }
            limits = {
              memory = "256Mi"
              cpu    = "100m"
            }
          }
        }

        volume {
          name = "proc"
          host_path {
            path = "/proc"
          }
        }

        volume {
          name = "sys"
          host_path {
            path = "/sys"
          }
        }

        host_network = true
        host_pid     = true
      }
    }
  }

  depends_on = [module.eks_blueprints_addons]
}

# Service for NVIDIA DCGM Exporter
resource "kubernetes_service" "nvidia_dcgm_exporter" {
  count = var.enable_nvidia_gpu_monitoring ? 1 : 0
  metadata {
    name      = "nvidia-dcgm-exporter"
    namespace = "kube-system"
    labels = {
      app = "nvidia-dcgm-exporter"
    }
  }

  spec {
    port {
      name        = "metrics"
      port        = 9400
      target_port = 9400
    }

    selector = {
      app = "nvidia-dcgm-exporter"
    }
  }

  depends_on = [kubernetes_daemonset.nvidia_dcgm_exporter[0]]
}

# ServiceMonitor for NVIDIA DCGM Exporter
resource "kubernetes_manifest" "nvidia_dcgm_service_monitor" {
  count = var.enable_nvidia_gpu_monitoring ? 1 : 0
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "nvidia-dcgm-exporter"
      namespace = "kube-seystem"
      labels = {
        app = "nvidia-dcgm-exporter"
      }
    }
    spec = {
      selector = {
        matchLabels = {
          app = "nvidia-dcgm-exporter"
        }
      }
      endpoints = [
        {
          port     = "metrics"
          interval = "30s"
          path     = "/metrics"
        }
      ]
    }
  }

  depends_on = [
    kubernetes_service.nvidia_dcgm_exporter[0],
    module.eks_blueprints_addons
  ]
}

#---------------------------------------------------------------
# Kubecost for Cost Monitoring
#---------------------------------------------------------------
resource "kubernetes_namespace" "kubecost" {
  count = var.enable_cost_monitoring ? 1 : 0
  metadata {
    name = "kubecost"
    labels = {
      name = "kubecost"
    }
  }

  depends_on = [module.eks]
}

resource "helm_release" "kubecost" {
  count      = var.enable_cost_monitoring ? 1 : 0
  name       = "kubecost"
  repository = "https://kubecost.github.io/cost-analyzer/"
  chart      = "cost-analyzer"
  version    = "2.3.4"
  namespace  = kubernetes_namespace.kubecost[0].metadata[0].name

  values = [templatefile("${path.module}/helm-values/kubecost-values.yaml", {
    cluster_name = module.eks.cluster_name
    region       = local.region
  })]

  depends_on = [
    module.eks_blueprints_addons,
    kubernetes_namespace.kubecost[0]
  ]
}

# ServiceMonitor for Kubecost
resource "kubernetes_manifest" "kubecost_service_monitor" {
  count = var.enable_cost_monitoring ? 1 : 0
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "kubecost"
      namespace = kubernetes_namespace.kubecost[0].metadata[0].name
      labels = {
        app = "kubecost"
      }
    }
    spec = {
      selector = {
        matchLabels = {
          app = "cost-analyzer"
        }
      }
      endpoints = [
        {
          port     = "http"
          interval = "60s"
          path     = "/metrics"
        }
      ]
    }
  }

  depends_on = [
    helm_release.kubecost[0],
    module.eks_blueprints_addons
  ]
}

#---------------------------------------------------------------
# Karpenter Node instance role Access Entry
#---------------------------------------------------------------
resource "aws_eks_access_entry" "karpenter_nodes" {
  cluster_name  = module.eks.cluster_name
  principal_arn = module.eks_blueprints_addons.karpenter.node_iam_role_arn
  type          = "EC2_LINUX"
}

#---------------------------------------------------------------
# Enhanced Karpenter NodePools for ML Workloads
#---------------------------------------------------------------
resource "kubectl_manifest" "gpu_nodepool" {
  count = var.enable_karpenter_gpu_nodes ? 1 : 0
  yaml_body = templatefile("${path.module}/k8s/karpenter-gpu-nodepool.yaml", {
    cluster_name = module.eks.cluster_name
    node_role    = split("/", module.eks_blueprints_addons.karpenter.node_iam_role_arn)[1]
    subnet_id    = module.vpc.private_subnets[2]
  })

  depends_on = [module.eks_blueprints_addons]
}

resource "kubectl_manifest" "cpu_nodepool" {
  count = var.enable_karpenter_cpu_nodes ? 1 : 0
  yaml_body = templatefile("${path.module}/k8s/karpenter-cpu-nodepool.yaml", {
    cluster_name = module.eks.cluster_name
    node_role    = split("/", module.eks_blueprints_addons.karpenter.node_iam_role_arn)[1]
    subnet_id    = module.vpc.private_subnets[3]
  })

  depends_on = [module.eks_blueprints_addons]
}

#---------------------------------------------------------------
# NVIDIA GPU Support
#---------------------------------------------------------------
# NVIDIA GPU Operator (if enabled)
resource "helm_release" "nvidia_gpu_operator" {
  count = var.enable_nvidia_gpu_operator ? 1 : 0

  name             = "nvidia-gpu-operator"
  repository       = "https://helm.ngc.nvidia.com/nvidia"
  chart            = "gpu-operator"
  version          = "v23.9.1"
  namespace        = "nvidia-gpu-operator"
  create_namespace = true

  values = [templatefile("${path.module}/helm-values/nvidia-operator-values.yaml", {
    cluster_name = module.eks.cluster_name
  })]

  depends_on = [module.eks_blueprints_addons]
}

# NVIDIA Device Plugin (if GPU Operator is disabled)
resource "helm_release" "nvidia_device_plugin" {
  count = var.enable_nvidia_gpu_operator ? 0 : 1

  name             = "nvidia-device-plugin"
  repository       = "https://nvidia.github.io/k8s-device-plugin"
  chart            = "nvidia-device-plugin"
  version          = "0.15.0"
  namespace        = "nvidia-device-plugin"
  create_namespace = true

  values = [templatefile("${path.module}/helm-values/nvidia-device-plugin-values.yaml", {
    cluster_name = module.eks.cluster_name
  })]

  depends_on = [module.eks_blueprints_addons]
}

#---------------------------------------------------------------
# KubeRay Operator for Distributed ML Training
#---------------------------------------------------------------
resource "helm_release" "kuberay_operator" {
  name             = "kuberay-operator"
  repository       = "https://ray-project.github.io/kuberay-helm/"
  chart            = "kuberay-operator"
  version          = "1.1.0"
  namespace        = "ray-system"
  create_namespace = true

  values = [templatefile("${path.module}/helm-values/kuberay-operator-values.yaml", {
    cluster_name = module.eks.cluster_name
  })]

  depends_on = [module.eks_blueprints_addons]
}

#---------------------------------------------------------------
# Grafana Admin credentials resources
#---------------------------------------------------------------
data "aws_secretsmanager_secret_version" "admin_password_version" {
  secret_id  = aws_secretsmanager_secret.grafana.id
  depends_on = [aws_secretsmanager_secret_version.grafana]
}

resource "random_password" "grafana" {
  length           = 16
  special          = true
  override_special = "@_"
}

#tfsec:ignore:aws-ssm-secret-use-customer-key
resource "aws_secretsmanager_secret" "grafana" {
  name                    = "${local.name}-grafana"
  recovery_window_in_days = 0 # Set to zero for this example to force delete during Terraform destroy
}

resource "aws_secretsmanager_secret_version" "grafana" {
  secret_id     = aws_secretsmanager_secret.grafana.id
  secret_string = random_password.grafana.result
}

#---------------------------------------------------------------
# S3 bucket for Spark jobs
#---------------------------------------------------------------
module "s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 3.0"

  bucket_prefix = "${local.name}-spark-"

  # For example only - please evaluate for your environment
  force_destroy = true

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = local.tags
}
