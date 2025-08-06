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
  value       = module.emr_containers.virtual_cluster_id
}

output "emr_virtual_cluster_arn" {
  description = "EMR on EKS Virtual Cluster ARN"
  value       = module.emr_containers.virtual_cluster_arn
}

output "emr_execution_role_arn" {
  description = "EMR on EKS Job Execution Role ARN"
  value       = module.emr_containers.iam_role_arn
}

# Pod Identity outputs
output "jupyterhub_pod_identity_role_arn" {
  description = "JupyterHub Pod Identity Role ARN"
  value       = aws_iam_role.jupyterhub_pod_identity_role.arn
}

output "ray_pod_identity_role_arn" {
  description = "Ray Cluster Pod Identity Role ARN"
  value       = var.enable_kuberay_operator ? aws_iam_role.ray_pod_identity_role[0].arn : "Ray not enabled"
}

output "argo_pod_identity_role_arn" {
  description = "Argo Workflows Pod Identity Role ARN"
  value       = var.enable_argo_workflows ? aws_iam_role.argo_workflows_pod_identity_role[0].arn : "Argo Workflows not enabled"
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

# JARK Stack outputs
output "jupyterhub_url" {
  description = "JupyterHub URL (available after LoadBalancer provisioning)"
  value       = var.enable_jupyterhub ? "http://<jupyterhub-loadbalancer-url>" : "JupyterHub not enabled"
}

output "ray_dashboard_url" {
  description = "Ray Dashboard URL (available after LoadBalancer provisioning)"
  value       = var.enable_kuberay_operator ? "http://<ray-dashboard-loadbalancer-url>:8265" : "Ray not enabled"
}

output "argo_workflows_url" {
  description = "Argo Workflows UI URL (available after LoadBalancer provisioning)"
  value       = var.enable_argo_workflows ? "http://<argo-workflows-loadbalancer-url>:2746" : "Argo Workflows not enabled"
}

output "grafana_url" {
  description = "Grafana Dashboard URL (available after LoadBalancer provisioning)"
  value       = var.enable_kube_prometheus_stack ? "http://<grafana-loadbalancer-url>" : "Grafana not enabled"
}

# Access commands
output "get_jupyterhub_url" {
  description = "Command to get JupyterHub URL"
  value       = var.enable_jupyterhub ? "kubectl get svc -n jupyterhub proxy-public -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'" : "JupyterHub not enabled"
}

output "get_ray_dashboard_url" {
  description = "Command to get Ray Dashboard URL"
  value       = var.enable_kuberay_operator ? "kubectl get svc -n ray-clusters ray-dashboard-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'" : "Ray not enabled"
}

output "get_argo_workflows_url" {
  description = "Command to get Argo Workflows URL"
  value       = var.enable_argo_workflows ? "kubectl get svc -n argo-workflows argo-server -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'" : "Argo Workflows not enabled"
}

output "get_grafana_url" {
  description = "Command to get Grafana URL"
  value       = var.enable_kube_prometheus_stack ? "kubectl get svc -n kube-prometheus-stack kube-prometheus-stack-grafana -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'" : "Grafana not enabled"
}

# Credentials
output "jupyterhub_credentials" {
  description = "JupyterHub login credentials"
  value       = var.enable_jupyterhub ? "Username: any, Password: fraud-detection-demo" : "JupyterHub not enabled"
}

output "grafana_credentials" {
  description = "Grafana login credentials"
  value       = var.enable_kube_prometheus_stack ? "Username: admin, Password: fraud-detection-grafana" : "Grafana not enabled"
}

output "emr_job_submission_example" {
  description = "Example EMR job submission command"
  value = <<-EOT
    aws emr-containers start-job-run \
      --virtual-cluster-id ${module.emr_containers.virtual_cluster_id} \
      --name "fraud-detection-feature-engineering" \
      --execution-role-arn ${module.emr_containers.iam_role_arn} \
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
              "spark.kubernetes.executor.podNamePrefix": "fraud-detection"
            }
          }
        ]
      }'
  EOT
}

output "argo_workflow_submission_example" {
  description = "Example Argo Workflow submission command"
  value = var.enable_argo_workflows ? <<-EOT
    # Submit fraud detection pipeline workflow
    argo submit -n argo-workflows --from workflowtemplate/fraud-detection-pipeline \
      --parameter virtual-cluster-id=${module.emr_containers.virtual_cluster_id} \
      --parameter execution-role-arn=${module.emr_containers.iam_role_arn} \
      --parameter s3-bucket=${module.s3_bucket.s3_bucket_id} \
      --parameter region=${local.region}
  EOT : "Argo Workflows not enabled"
}