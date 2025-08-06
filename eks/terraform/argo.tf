#---------------------------------------------------------------
# Argo Workflows Namespace and RBAC
#---------------------------------------------------------------
resource "kubernetes_namespace" "argo_workflows" {
  count = var.enable_argo_workflows ? 1 : 0
  
  metadata {
    name = "argo-workflows"
    labels = {
      name = "argo-workflows"
    }
  }

  depends_on = [module.eks]
}

#---------------------------------------------------------------
# Argo Workflows Service Account with IRSA
#---------------------------------------------------------------
resource "kubernetes_service_account" "argo_workflows_sa" {
  count = var.enable_argo_workflows ? 1 : 0
  
  metadata {
    name      = "argo-workflows-sa"
    namespace = kubernetes_namespace.argo_workflows[0].metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = module.argo_workflows_irsa[0].iam_role_arn
    }
  }

  depends_on = [kubernetes_namespace.argo_workflows]
}

#---------------------------------------------------------------
# IRSA for Argo Workflows
#---------------------------------------------------------------
module "argo_workflows_irsa" {
  count = var.enable_argo_workflows ? 1 : 0
  
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.55"

  role_name_prefix = "Argo-Workflows-IRSA"

  role_policy_arns = {
    s3_access = aws_iam_policy.argo_workflows_s3_policy[0].arn
    emr_access = aws_iam_policy.argo_workflows_emr_policy[0].arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["argo-workflows:argo-workflows-sa", "argo-workflows:argo-server"]
    }
  }

  tags = local.tags
}

resource "aws_iam_policy" "argo_workflows_s3_policy" {
  count = var.enable_argo_workflows ? 1 : 0
  
  name_prefix = "${local.name}-argo-s3-"
  description = "IAM policy for Argo Workflows S3 access"

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

resource "aws_iam_policy" "argo_workflows_emr_policy" {
  count = var.enable_argo_workflows ? 1 : 0
  
  name_prefix = "${local.name}-argo-emr-"
  description = "IAM policy for Argo Workflows EMR access"

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

#---------------------------------------------------------------
# Fraud Detection Pipeline Workflow Template
#---------------------------------------------------------------
resource "kubectl_manifest" "fraud_detection_workflow_template" {
  count = var.enable_argo_workflows ? 1 : 0
  
  yaml_body = <<-YAML
    apiVersion: argoproj.io/v1alpha1
    kind: WorkflowTemplate
    metadata:
      name: fraud-detection-pipeline
      namespace: argo-workflows
    spec:
      entrypoint: fraud-detection-dag
      serviceAccountName: argo-workflows-sa
      
      arguments:
        parameters:
        - name: virtual-cluster-id
          value: "${module.emr_containers.virtual_cluster_id}"
        - name: execution-role-arn
          value: "${module.emr_containers.iam_role_arn}"
        - name: s3-bucket
          value: "${module.s3_bucket.s3_bucket_id}"
        - name: region
          value: "${local.region}"
      
      templates:
      - name: fraud-detection-dag
        dag:
          tasks:
          - name: feature-engineering
            template: emr-spark-job
            arguments:
              parameters:
              - name: job-name
                value: "fraud-feature-engineering"
              - name: entry-point
                value: "s3://{{workflow.parameters.s3-bucket}}/fraud-data/feature_engineering.py"
              - name: spark-config
                value: "--conf spark.rapids.sql.enabled=true --conf spark.plugins=com.nvidia.spark.SQLPlugin"
          
          - name: model-training
            template: ray-training-job
            dependencies: [feature-engineering]
            arguments:
              parameters:
              - name: training-script
                value: "s3://{{workflow.parameters.s3-bucket}}/fraud-data/xgboost_training.py"
          
          - name: model-deployment
            template: ray-serve-deployment
            dependencies: [model-training]
            arguments:
              parameters:
              - name: model-path
                value: "s3://{{workflow.parameters.s3-bucket}}/fraud-models/latest/"
      
      - name: emr-spark-job
        inputs:
          parameters:
          - name: job-name
          - name: entry-point
          - name: spark-config
        container:
          image: amazon/aws-cli:latest
          command: [sh, -c]
          args: |
            aws emr-containers start-job-run \
              --virtual-cluster-id {{workflow.parameters.virtual-cluster-id}} \
              --name {{inputs.parameters.job-name}} \
              --execution-role-arn {{workflow.parameters.execution-role-arn}} \
              --release-label emr-7.9.0-latest \
              --job-driver '{
                "sparkSubmitJobDriver": {
                  "entryPoint": "{{inputs.parameters.entry-point}}",
                  "sparkSubmitParameters": "{{inputs.parameters.spark-config}}"
                }
              }' \
              --configuration-overrides '{
                "applicationConfiguration": [
                  {
                    "classification": "spark-defaults",
                    "properties": {
                      "spark.executor.instances": "4",
                      "spark.executor.memory": "30G",
                      "spark.executor.resource.gpu.amount": "1",
                      "spark.rapids.sql.enabled": "true"
                    }
                  }
                ]
              }' \
              --region {{workflow.parameters.region}}
          env:
          - name: AWS_DEFAULT_REGION
            value: "{{workflow.parameters.region}}"
      
      - name: ray-training-job
        inputs:
          parameters:
          - name: training-script
        script:
          image: rayproject/ray:2.8.0-py310
          command: [python]
          source: |
            import ray
            import boto3
            import os
            
            # Connect to Ray cluster
            ray.init(address="ray://ray-cluster-head.ray-clusters.svc.cluster.local:10001")
            
            # Download and execute training script
            s3 = boto3.client('s3')
            bucket = "{{workflow.parameters.s3-bucket}}"
            key = "{{inputs.parameters.training-script}}".replace(f"s3://{bucket}/", "")
            
            s3.download_file(bucket, key, '/tmp/training_script.py')
            exec(open('/tmp/training_script.py').read())
          env:
          - name: AWS_DEFAULT_REGION
            value: "{{workflow.parameters.region}}"
          - name: S3_BUCKET
            value: "{{workflow.parameters.s3-bucket}}"
      
      - name: ray-serve-deployment
        inputs:
          parameters:
          - name: model-path
        script:
          image: rayproject/ray:2.8.0-py310
          command: [python]
          source: |
            import ray
            from ray import serve
            import boto3
            
            # Connect to Ray cluster
            ray.init(address="ray://ray-cluster-head.ray-clusters.svc.cluster.local:10001")
            
            # Deploy fraud detection model
            @serve.deployment(num_replicas=2)
            class FraudDetectionModel:
                def __init__(self):
                    # Load model from S3
                    self.model_path = "{{inputs.parameters.model-path}}"
                    # Model loading logic here
                
                async def __call__(self, request):
                    # Inference logic here
                    return {"fraud_probability": 0.1}
            
            serve.start()
            FraudDetectionModel.deploy()
          env:
          - name: AWS_DEFAULT_REGION
            value: "{{workflow.parameters.region}}"
          - name: S3_BUCKET
            value: "{{workflow.parameters.s3-bucket}}"
  YAML

  depends_on = [
    module.eks_blueprints_addons,
    kubernetes_namespace.argo_workflows,
    kubernetes_service_account.argo_workflows_sa
  ]
}