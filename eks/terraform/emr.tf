#---------------------------------------------------------------
# EMR on EKS Virtual Cluster
#---------------------------------------------------------------
resource "aws_emrcontainers_virtual_cluster" "fraud_detection" {
  name = "${local.name}-emr-virtual-cluster"

  container_provider {
    id   = module.eks.cluster_name
    type = "EKS"

    info {
      eks_info {
        namespace = kubernetes_namespace.emr_fraud_detection.metadata[0].name
      }
    }
  }

  tags = local.tags

  depends_on = [
    kubernetes_namespace.emr_fraud_detection,
    kubernetes_service_account.emr_containers_sa_spark,
    kubernetes_role.emr_containers,
    kubernetes_role_binding.emr_containers
  ]
}

#---------------------------------------------------------------
# EMR on EKS Job Execution Role
#---------------------------------------------------------------
resource "aws_iam_role" "emr_execution_role" {
  name_prefix = "${local.name}-emr-execution-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "emr-containers.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonEMRContainersServiceRolePolicy",
    aws_iam_policy.emr_s3_policy.arn
  ]

  tags = local.tags
}

resource "aws_iam_policy" "emr_s3_policy" {
  name_prefix = "${local.name}-emr-s3-"
  description = "IAM policy for EMR S3 access"

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

#---------------------------------------------------------------
# EMR on EKS Namespace and RBAC
#---------------------------------------------------------------
resource "kubernetes_namespace" "emr_fraud_detection" {
  metadata {
    name = "emr-fraud-detection"
    labels = {
      name = "emr-fraud-detection"
    }
  }

  depends_on = [module.eks]
}

resource "kubernetes_service_account" "emr_containers_sa_spark" {
  metadata {
    name      = "emr-containers-sa-spark"
    namespace = kubernetes_namespace.emr_fraud_detection.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.emr_execution_role.arn
    }
  }

  depends_on = [kubernetes_namespace.emr_fraud_detection]
}

resource "kubernetes_role" "emr_containers" {
  metadata {
    namespace = kubernetes_namespace.emr_fraud_detection.metadata[0].name
    name      = "emr-containers"
  }

  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["get", "list", "watch", "describe", "create", "edit", "delete", "deletecollection"]
  }

  rule {
    api_groups = [""]
    resources  = ["configmaps"]
    verbs      = ["get", "list", "watch", "describe", "create", "edit", "delete", "deletecollection"]
  }

  rule {
    api_groups = [""]
    resources  = ["persistentvolumeclaims"]
    verbs      = ["get", "list", "watch", "describe", "create", "edit", "delete", "deletecollection"]
  }

  depends_on = [kubernetes_namespace.emr_fraud_detection]
}

resource "kubernetes_role_binding" "emr_containers" {
  metadata {
    name      = "emr-containers"
    namespace = kubernetes_namespace.emr_fraud_detection.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.emr_containers_sa_spark.metadata[0].name
    namespace = kubernetes_namespace.emr_fraud_detection.metadata[0].name
  }

  role_ref {
    kind      = "Role"
    name      = kubernetes_role.emr_containers.metadata[0].name
    api_group = "rbac.authorization.k8s.io"
  }

  depends_on = [
    kubernetes_service_account.emr_containers_sa_spark,
    kubernetes_role.emr_containers
  ]
}

#---------------------------------------------------------------
# S3 Bucket for EMR Spark Event Logs and Data
#---------------------------------------------------------------
module "s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 4.6"

  bucket_prefix = "${local.name}-emr-"

  # For demo only - please evaluate for your environment
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

# Create S3 bucket prefixes for organization
resource "aws_s3_object" "spark_event_logs" {
  bucket       = module.s3_bucket.s3_bucket_id
  key          = "spark-event-logs/"
  content_type = "application/x-directory"
}

resource "aws_s3_object" "fraud_data" {
  bucket       = module.s3_bucket.s3_bucket_id
  key          = "fraud-data/"
  content_type = "application/x-directory"
}

resource "aws_s3_object" "fraud_models" {
  bucket       = module.s3_bucket.s3_bucket_id
  key          = "fraud-models/"
  content_type = "application/x-directory"
}

resource "aws_s3_object" "fraud_predictions" {
  bucket       = module.s3_bucket.s3_bucket_id
  key          = "fraud-predictions/"
  content_type = "application/x-directory"
}