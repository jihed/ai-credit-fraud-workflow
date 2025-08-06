#---------------------------------------------------------------
# JupyterHub for notebook integration
#---------------------------------------------------------------

# Random secret token for JupyterHub
resource "random_password" "jupyterhub_secret_token" {
  length  = 64
  special = false
}

# Secret for JupyterHub configuration
resource "aws_secretsmanager_secret" "jupyterhub" {
  name                    = "${local.name}-jupyterhub"
  recovery_window_in_days = 0 # Set to zero for this example to force delete during Terraform destroy
}

resource "aws_secretsmanager_secret_version" "jupyterhub" {
  secret_id     = aws_secretsmanager_secret.jupyterhub.id
  secret_string = random_password.jupyterhub_secret_token.result
}

# Data source for JupyterHub secret
data "aws_secretsmanager_secret_version" "jupyterhub_secret_version" {
  secret_id  = aws_secretsmanager_secret.jupyterhub.id
  depends_on = [aws_secretsmanager_secret_version.jupyterhub]
}

# ECR repository for custom JupyterHub image
resource "aws_ecr_repository" "jupyterhub_rapids" {
  name                 = "jupyterhub-rapids"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.tags
}

# ECR lifecycle policy
resource "aws_ecr_lifecycle_policy" "jupyterhub_rapids" {
  repository = aws_ecr_repository.jupyterhub_rapids.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Delete untagged images older than 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

#---------------------------------------------------------------
# EKS Pod Identity for JupyterHub
#---------------------------------------------------------------
resource "aws_iam_role" "jupyterhub_role" {
  name = format("%s-%s", local.name, "jupyterhub-role")

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

resource "aws_iam_role_policy_attachment" "jupyterhub_policy" {
  policy_arn = aws_iam_policy.jupyterhub_policy.arn
  role       = aws_iam_role.jupyterhub_role.name
}

resource "aws_eks_pod_identity_association" "jupyterhub_hub" {
  cluster_name    = module.eks.cluster_name
  namespace       = "jupyterhub"
  service_account = "jupyterhub-hub"
  role_arn        = aws_iam_role.jupyterhub_role.arn
}

resource "aws_eks_pod_identity_association" "jupyterhub_notebook" {
  cluster_name    = module.eks.cluster_name
  namespace       = "jupyterhub"
  service_account = "jupyterhub-notebook-sa"
  role_arn        = aws_iam_role.jupyterhub_role.arn
}

# IAM policy for JupyterHub
resource "aws_iam_policy" "jupyterhub_policy" {
  name_prefix = "${local.name}-jupyterhub-"
  description = "IAM policy for JupyterHub notebooks"

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
      },
      {
        Effect = "Allow"
        Action = [
          "emr-containers:StartJobRun",
          "emr-containers:DescribeJobRun",
          "emr-containers:CancelJobRun",
          "emr-containers:ListJobRuns"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.tags
}

# Kubernetes namespace for JupyterHub
resource "kubernetes_namespace" "jupyterhub" {
  metadata {
    name = "jupyterhub"
    labels = {
      name = "jupyterhub"
    }
  }

  depends_on = [module.eks]
}

# Service account for JupyterHub notebooks
resource "kubernetes_service_account" "jupyterhub_notebook" {
  metadata {
    name      = "jupyterhub-notebook-sa"
    namespace = kubernetes_namespace.jupyterhub.metadata[0].name
    # EKS Pod Identity will handle IAM permissions automatically
  }

  depends_on = [module.eks]
}

# Persistent Volume Claim for shared data (temporarily disabled)
# resource "kubernetes_persistent_volume_claim" "jupyterhub_shared_data" {
#   metadata {
#     name      = "jupyterhub-shared-data"
#     namespace = kubernetes_namespace.jupyterhub.metadata[0].name
#   }

#   spec {
#     access_modes = ["ReadWriteOnce"]
#     resources {
#       requests = {
#         storage = "100Gi"
#       }
#     }
#     storage_class_name = "gp2"
#   }

#   depends_on = [module.eks]
# }

# EFS file system for shared storage
resource "aws_efs_file_system" "jupyterhub_shared" {
  creation_token = "${local.name}-jupyterhub-shared"
  
  performance_mode = "generalPurpose"
  throughput_mode  = "provisioned"
  provisioned_throughput_in_mibps = 100

  encrypted = true

  tags = merge(local.tags, {
    Name = "${local.name}-jupyterhub-shared"
  })
}

# EFS mount targets
resource "aws_efs_mount_target" "jupyterhub_shared" {
  count = length(module.vpc.private_subnets)

  file_system_id  = aws_efs_file_system.jupyterhub_shared.id
  subnet_id       = module.vpc.private_subnets[count.index]
  security_groups = [aws_security_group.efs.id]
}

# Security group for EFS
resource "aws_security_group" "efs" {
  name_prefix = "${local.name}-efs-"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "NFS"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [module.vpc.vpc_cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags
}

# EFS storage class for shared storage
resource "kubernetes_storage_class" "efs" {
  metadata {
    name = "efs-sc"
  }

  storage_provisioner    = "efs.csi.aws.com"
  reclaim_policy         = "Retain"
  allow_volume_expansion = true
  
  parameters = {
    provisioningMode = "efs-ap"
    fileSystemId     = aws_efs_file_system.jupyterhub_shared.id
    directoryPerms   = "0755"
  }

  depends_on = [module.eks, aws_efs_file_system.jupyterhub_shared]
}

# JupyterHub deployment is now handled by EKS Blueprint addons in addons.tf
# This file maintains the supporting resources for JupyterHub

# ConfigMap for notebook templates
resource "kubernetes_config_map" "notebook_templates" {
  metadata {
    name      = "notebook-templates"
    namespace = kubernetes_namespace.jupyterhub.metadata[0].name
  }

  data = {
    "emr-spark-rapids-example.ipynb" = file("${path.module}/../notebook-templates/emr-spark-rapids-example.ipynb")
    "ray-xgboost-training.ipynb"     = file("${path.module}/../notebook-templates/ray-xgboost-training.ipynb")
    "fraud-detection-pipeline.ipynb" = file("${path.module}/../notebook-templates/fraud-detection-pipeline.ipynb")
  }

  depends_on = [kubernetes_namespace.jupyterhub]
}