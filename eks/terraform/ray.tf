#---------------------------------------------------------------
# Ray Cluster for ML Training and Serving
#---------------------------------------------------------------
resource "kubernetes_namespace" "ray_system" {
  count = var.enable_kuberay_operator ? 1 : 0
  
  metadata {
    name = "ray-system"
    labels = {
      name = "ray-system"
    }
  }

  depends_on = [module.eks]
}

resource "kubernetes_namespace" "ray_clusters" {
  count = var.enable_kuberay_operator ? 1 : 0
  
  metadata {
    name = "ray-clusters"
    labels = {
      name = "ray-clusters"
    }
  }

  depends_on = [module.eks]
}

#---------------------------------------------------------------
# Ray Cluster for Fraud Detection
#---------------------------------------------------------------
resource "kubectl_manifest" "ray_cluster" {
  count = var.enable_kuberay_operator ? 1 : 0
  
  yaml_body = <<-YAML
    apiVersion: ray.io/v1
    kind: RayCluster
    metadata:
      name: fraud-detection-ray-cluster
      namespace: ray-clusters
    spec:
      rayVersion: '2.8.0'
      enableInTreeAutoscaling: true
      autoscalerOptions:
        upscalingMode: Default
        idleTimeoutSeconds: 60
        resources:
          limits:
            cpu: "500m"
            memory: "512Mi"
          requests:
            cpu: "500m"
            memory: "512Mi"
      headGroupSpec:
        rayStartParams:
          dashboard-host: '0.0.0.0'
          num-cpus: '0'
        template:
          metadata:
            labels:
              ray-cluster: fraud-detection
              ray-node-type: head
          spec:
            containers:
            - name: ray-head
              image: rayproject/ray:2.8.0-py310
              resources:
                limits:
                  cpu: 2
                  memory: 8Gi
                requests:
                  cpu: 1
                  memory: 4Gi
              ports:
              - containerPort: 6379
                name: gcs-server
              - containerPort: 8265
                name: dashboard
              - containerPort: 10001
                name: client
              env:
              - name: RAY_DISABLE_IMPORT_WARNING
                value: "1"
              - name: S3_BUCKET
                value: "${module.s3_bucket.s3_bucket_id}"
              - name: AWS_DEFAULT_REGION
                value: "${local.region}"
              volumeMounts:
              - mountPath: /tmp/ray
                name: ray-logs
            volumes:
            - name: ray-logs
              emptyDir: {}
            serviceAccountName: ray-service-account
            nodeSelector:
              provisioner: spark-cpu-optimized
      workerGroupSpecs:
      - replicas: 2
        minReplicas: 1
        maxReplicas: 5
        groupName: cpu-workers
        rayStartParams:
          num-cpus: '4'
        template:
          metadata:
            labels:
              ray-cluster: fraud-detection
              ray-node-type: worker
              worker-type: cpu
          spec:
            containers:
            - name: ray-worker
              image: rayproject/ray:2.8.0-py310
              lifecycle:
                preStop:
                  exec:
                    command: ["/bin/sh","-c","ray stop"]
              resources:
                limits:
                  cpu: 4
                  memory: 16Gi
                requests:
                  cpu: 2
                  memory: 8Gi
              env:
              - name: RAY_DISABLE_IMPORT_WARNING
                value: "1"
              - name: S3_BUCKET
                value: "${module.s3_bucket.s3_bucket_id}"
              - name: AWS_DEFAULT_REGION
                value: "${local.region}"
              volumeMounts:
              - mountPath: /tmp/ray
                name: ray-logs
            volumes:
            - name: ray-logs
              emptyDir: {}
            serviceAccountName: ray-service-account
            nodeSelector:
              provisioner: spark-cpu-optimized
      - replicas: 1
        minReplicas: 0
        maxReplicas: 3
        groupName: gpu-workers
        rayStartParams:
          num-cpus: '8'
          num-gpus: '1'
        template:
          metadata:
            labels:
              ray-cluster: fraud-detection
              ray-node-type: worker
              worker-type: gpu
          spec:
            containers:
            - name: ray-worker
              image: rayproject/ray:2.8.0-py310-gpu
              lifecycle:
                preStop:
                  exec:
                    command: ["/bin/sh","-c","ray stop"]
              resources:
                limits:
                  cpu: 8
                  memory: 32Gi
                  nvidia.com/gpu: 1
                requests:
                  cpu: 4
                  memory: 16Gi
                  nvidia.com/gpu: 1
              env:
              - name: RAY_DISABLE_IMPORT_WARNING
                value: "1"
              - name: S3_BUCKET
                value: "${module.s3_bucket.s3_bucket_id}"
              - name: AWS_DEFAULT_REGION
                value: "${local.region}"
              volumeMounts:
              - mountPath: /tmp/ray
                name: ray-logs
            volumes:
            - name: ray-logs
              emptyDir: {}
            serviceAccountName: ray-service-account
            nodeSelector:
              provisioner: spark-gpu-rapids
            tolerations:
            - key: nvidia.com/gpu
              operator: Exists
              effect: NoSchedule
  YAML

  depends_on = [
    module.eks_blueprints_addons,
    kubernetes_namespace.ray_clusters,
    kubernetes_service_account.ray_service_account
  ]
}

#---------------------------------------------------------------
# Ray Service Account with IRSA
#---------------------------------------------------------------
resource "kubernetes_service_account" "ray_service_account" {
  count = var.enable_kuberay_operator ? 1 : 0
  
  metadata {
    name      = "ray-service-account"
    namespace = kubernetes_namespace.ray_clusters[0].metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = module.ray_irsa[0].iam_role_arn
    }
  }

  depends_on = [kubernetes_namespace.ray_clusters]
}

#---------------------------------------------------------------
# IRSA for Ray Cluster
#---------------------------------------------------------------
module "ray_irsa" {
  count = var.enable_kuberay_operator ? 1 : 0
  
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.55"

  role_name_prefix = "Ray-Cluster-IRSA"

  role_policy_arns = {
    s3_access = aws_iam_policy.ray_s3_policy[0].arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["ray-clusters:ray-service-account"]
    }
  }

  tags = local.tags
}

resource "aws_iam_policy" "ray_s3_policy" {
  count = var.enable_kuberay_operator ? 1 : 0
  
  name_prefix = "${local.name}-ray-s3-"
  description = "IAM policy for Ray cluster S3 access"

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
# Ray Dashboard Service (LoadBalancer)
#---------------------------------------------------------------
resource "kubernetes_service" "ray_dashboard" {
  count = var.enable_kuberay_operator ? 1 : 0
  
  metadata {
    name      = "ray-dashboard-service"
    namespace = kubernetes_namespace.ray_clusters[0].metadata[0].name
    annotations = {
      "service.beta.kubernetes.io/aws-load-balancer-type" = "nlb"
      "service.beta.kubernetes.io/aws-load-balancer-scheme" = "internet-facing"
    }
  }

  spec {
    selector = {
      "ray-cluster" = "fraud-detection"
      "ray-node-type" = "head"
    }

    port {
      name        = "dashboard"
      port        = 8265
      target_port = 8265
      protocol    = "TCP"
    }

    type = "LoadBalancer"
  }

  depends_on = [kubectl_manifest.ray_cluster]
}