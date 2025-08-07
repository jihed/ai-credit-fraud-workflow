#---------------------------------------------------------------
# Outputs
#---------------------------------------------------------------
output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "EKS cluster version"
  value       = module.eks.cluster_version
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.eks.cluster_security_group_id
}

output "region" {
  description = "AWS region"
  value       = local.region
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "private_subnets" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnets
}



output "emr_virtual_cluster_id" {
  description = "EMR on EKS Virtual Cluster ID"
  value       = aws_emrcontainers_virtual_cluster.fraud_detection.id
}

output "emr_virtual_cluster_arn" {
  description = "EMR on EKS Virtual Cluster ARN"
  value       = aws_emrcontainers_virtual_cluster.fraud_detection.arn
}

output "emr_execution_role_arn" {
  description = "EMR on EKS Job Execution Role ARN"
  value       = aws_iam_role.emr_execution_role.arn
}

output "s3_bucket_name" {
  description = "S3 bucket name for EMR data and logs"
  value       = module.s3_bucket.s3_bucket_id
}

output "s3_bucket_arn" {
  description = "S3 bucket ARN for EMR data and logs"
  value       = module.s3_bucket.s3_bucket_arn
}

# Karpenter outputs
output "karpenter_node_iam_role_arn" {
  description = "Karpenter Node IAM Role ARN"
  value       = module.eks_blueprints_addons.karpenter.node_iam_role_arn
}

output "karpenter_node_iam_role_name" {
  description = "Karpenter Node IAM Role Name"
  value       = module.eks_blueprints_addons.karpenter.node_iam_role_name
}

# Configuration commands
output "configure_kubectl" {
  description = "Configure kubectl command"
  value       = "aws eks --region ${local.region} update-kubeconfig --name ${module.eks.cluster_name}"
}

output "emr_job_submission_example" {
  description = "Example EMR on EKS job submission command for ML workloads"
  value = <<-EOT
    aws emr-containers start-job-run \
      --virtual-cluster-id ${aws_emrcontainers_virtual_cluster.fraud_detection.id} \
      --name "fraud-detection-ml-feature-engineering" \
      --execution-role-arn ${aws_iam_role.emr_execution_role.arn} \
      --release-label emr-7.9.0-latest \
      --job-driver '{
        "sparkSubmitJobDriver": {
          "entryPoint": "s3://${module.s3_bucket.s3_bucket_id}/fraud-data/feature_engineering.py",
          "sparkSubmitParameters": "--conf spark.rapids.sql.enabled=true --conf spark.plugins=com.nvidia.spark.SQLPlugin"
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
              "spark.rapids.sql.enabled": "true",
              "spark.kubernetes.executor.podNamePrefix": "fraud-detection-ml"
            }
          }
        ]
      }'
  EOT
}

# Service URL outputs (placeholders for future ML Stack services)
output "get_jupyterhub_url" {
  description = "Command to get JupyterHub URL"
  value       = "kubectl get svc -n jupyterhub proxy-public -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo 'Service not deployed yet'"
}

output "get_ray_dashboard_url" {
  description = "Command to get Ray Dashboard URL"
  value       = "kubectl get svc -n ray-clusters ray-dashboard-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo 'Service not deployed yet'"
}

output "get_argo_workflows_url" {
  description = "Command to get Argo Workflows URL"
  value       = "kubectl get svc -n argo-workflows argo-server -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo 'Service not deployed yet'"
}

output "get_grafana_url" {
  description = "Command to get Grafana URL"
  value       = "kubectl get svc -n kube-prometheus-stack kube-prometheus-stack-grafana -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo 'Service not deployed yet'"
}

output "argo_workflow_submission_example" {
  description = "Example Argo workflow submission command"
  value = <<-EOT
    # Example Argo workflow for fraud detection ML pipeline
    kubectl apply -f - <<EOF
    apiVersion: argoproj.io/v1alpha1
    kind: Workflow
    metadata:
      generateName: fraud-detection-ml-pipeline-
      namespace: argo-workflows
    spec:
      entrypoint: ml-pipeline
      templates:
      - name: ml-pipeline
        steps:
        - - name: data-preprocessing
            template: spark-job
            arguments:
              parameters:
              - name: job-name
                value: "fraud-data-preprocessing"
        - - name: model-training
            template: spark-job
            arguments:
              parameters:
              - name: job-name
                value: "fraud-model-training"
      - name: spark-job
        inputs:
          parameters:
          - name: job-name
        container:
          image: public.ecr.aws/emr-on-eks/spark/emr-7.9.0:latest
          command: ["/bin/bash"]
          args: ["-c", "echo 'Running {{inputs.parameters.job-name}}'"]
    EOF
  EOT
}

# Next steps information
output "next_steps" {
  description = "Next steps for ML Stack deployment"
  value = <<-EOT
    Infrastructure deployment complete! Next steps:
    
    1. Deploy ML Stack applications using Helm:
       cd ../helm && ./scripts/deploy-applications.sh
    
    2. Or deploy using GitOps:
       cd ../gitops && ./scripts/install-argocd.sh
       kubectl apply -f applications/
    
    3. Configure kubectl:
       ${module.eks.cluster_name != "" ? "aws eks --region ${local.region} update-kubeconfig --name ${module.eks.cluster_name}" : ""}
    
    4. Check cluster status:
       kubectl get nodes
       kubectl get pods -n karpenter
  EOT
}