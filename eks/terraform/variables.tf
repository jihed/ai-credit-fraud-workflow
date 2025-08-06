variable "name" {
  description = "Name of the VPC and EKS Cluster"
  type        = string
  default     = "fraud-detection-emr-eks"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "eks_cluster_version" {
  description = "EKS Cluster version"
  type        = string
  default     = "1.33"
}

variable "tags" {
  description = "Default tags"
  type        = map(string)
  default = {
    Environment = "demo"
    Team        = "data-science"
    Project     = "fraud-detection"
  }
}

# VPC Configuration
variable "vpc_cidr" {
  description = "VPC CIDR. This should be a valid private (RFC 1918) CIDR range"
  type        = string
  default     = "10.1.0.0/16"
}

variable "public_subnets" {
  description = "Public Subnets CIDRs. 62 IPs per Subnet/AZ"
  type        = list(string)
  default     = ["10.1.0.0/26", "10.1.0.64/26"]
}

variable "private_subnets" {
  description = "Private Subnets CIDRs. 254 IPs per Subnet/AZ for Private NAT + NLB + Airflow + EC2 Jumphost etc."
  type        = list(string)
  default     = ["10.1.1.0/24", "10.1.2.0/24"]
}

variable "secondary_cidr_blocks" {
  description = "Secondary CIDR blocks to be attached to VPC"
  type        = list(string)
  default     = ["100.64.0.0/16"]
}

variable "eks_data_plane_subnet_secondary_cidr" {
  description = "Secondary CIDR blocks. 32766 IPs per Subnet per Subnet/AZ for EKS Node and Pods"
  type        = list(string)
  default     = ["100.64.0.0/17", "100.64.128.0/17"]
}

# Add-on Configuration
variable "enable_nvidia_gpu_operator" {
  description = "Enable NVIDIA GPU Operator for GPU support"
  type        = bool
  default     = true
}

variable "enable_amazon_prometheus" {
  description = "Enable AWS Managed Prometheus service"
  type        = bool
  default     = false
}

variable "enable_vpc_endpoints" {
  description = "Enable VPC Endpoints"
  type        = bool
  default     = false
}

# JARK Stack Components
variable "enable_jupyterhub" {
  description = "Enable JupyterHub for unified notebook experience"
  type        = bool
  default     = true
}

variable "enable_kuberay_operator" {
  description = "Enable Ray Operator for distributed ML"
  type        = bool
  default     = true
}

variable "enable_argo_workflows" {
  description = "Enable Argo Workflows for ML pipeline orchestration"
  type        = bool
  default     = true
}

variable "enable_kube_prometheus_stack" {
  description = "Enable Prometheus and Grafana monitoring stack"
  type        = bool
  default     = true
}

variable "kms_key_admin_roles" {
  description = "List of role ARNs to add to the KMS policy"
  type        = list(string)
  default     = []
}