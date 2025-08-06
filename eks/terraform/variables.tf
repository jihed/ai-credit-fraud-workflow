variable "name" {
  description = "Name of the VPC and EKS Cluster"
  type        = string
  default     = "emr-spark-rapids"
}

variable "region" {
  description = "Region"
  default     = "us-west-2"
  type        = string
}

variable "eks_cluster_version" {
  description = "EKS Cluster version"
  type        = string
  default     = "1.31"
}

variable "tags" {
  description = "Default tags"
  type        = map(string)
  default     = {}
}

# VPC with 2046 IPs (10.1.0.0/21) and 2 AZs
variable "vpc_cidr" {
  description = "VPC CIDR. This should be a valid private (RFC 1918) CIDR range"
  type        = string
  default     = "10.1.0.0/21"
}

# RFC6598 range 100.64.0.0/10
# Note you can only /16 range to VPC. You can add multiples of /16 if required
variable "secondary_cidr_blocks" {
  description = "Secondary CIDR blocks to be attached to VPC"
  type        = list(string)
  default     = ["100.64.0.0/16"]
}

variable "enable_amazon_prometheus" {
  description = "Enable AWS Managed Prometheus service"
  default     = true
  type        = bool
}

variable "enable_nvidia_gpu_operator" {
  description = "Enable NVIDIA GPU Operator"
  default     = false
  type        = bool
}

variable "kms_key_admin_roles" {
  description = "list of role ARNs to add to the KMS policy"
  type        = list(string)
  default     = []
}

#---------------------------------------------------------------
# Platform Components Configuration
#---------------------------------------------------------------
variable "enable_jupyterhub" {
  description = "Enable JupyterHub for notebook development"
  type        = bool
  default     = true
}

variable "enable_ray_cluster" {
  description = "Enable Ray cluster for distributed ML training"
  type        = bool
  default     = true
}

variable "enable_inference_service" {
  description = "Enable fraud detection inference service"
  type        = bool
  default     = true
}

variable "enable_sample_data" {
  description = "Enable sample fraud detection data upload via bash script"
  type        = bool
  default     = true
}

variable "enable_monitoring_dashboards" {
  description = "Enable Grafana dashboards for fraud detection"
  type        = bool
  default     = true
}

#---------------------------------------------------------------
# Application Configuration
#---------------------------------------------------------------
variable "jupyterhub_admin_password" {
  description = "Admin password for JupyterHub (leave empty for auto-generated)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "fraud_detection_model_version" {
  description = "Version of the fraud detection model to deploy"
  type        = string
  default     = "v1.0.0"
}

variable "inference_service_replicas" {
  description = "Number of replicas for the inference service"
  type        = number
  default     = 3
}

variable "ray_cluster_workers" {
  description = "Number of Ray worker nodes"
  type        = number
  default     = 2
}

#---------------------------------------------------------------
# Enhanced Monitoring Configuration
#---------------------------------------------------------------
variable "enable_nvidia_gpu_monitoring" {
  description = "Enable NVIDIA GPU monitoring with DCGM exporter"
  type        = bool
  default     = true
}

variable "enable_cost_monitoring" {
  description = "Enable Kubecost for cost monitoring and optimization"
  type        = bool
  default     = true
}

variable "enable_enhanced_logging" {
  description = "Enable enhanced logging with AWS for Fluent Bit"
  type        = bool
  default     = true
}

#---------------------------------------------------------------
# Advanced EKS Configuration
#---------------------------------------------------------------
variable "enable_karpenter_gpu_nodes" {
  description = "Enable Karpenter GPU node pools for ML workloads"
  type        = bool
  default     = true
}

variable "enable_karpenter_cpu_nodes" {
  description = "Enable Karpenter CPU node pools for general workloads"
  type        = bool
  default     = true
}

variable "gpu_instance_types" {
  description = "List of GPU instance types for Karpenter"
  type        = list(string)
  default     = ["g5.2xlarge", "g5.4xlarge"]
}

variable "cpu_instance_types" {
  description = "List of CPU instance types for Karpenter"
  type        = list(string)
  default     = ["m5.xlarge", "m5.2xlarge", "m5.4xlarge", "m5.8xlarge"]
}
