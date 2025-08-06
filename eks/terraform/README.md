# Terraform Infrastructure

This directory contains all Terraform configuration files and related infrastructure code for the EMR to EKS migration platform.

## Directory Structure

```
terraform/
├── .terraform/                 # Terraform state and provider cache
├── helm-values/               # Helm chart values files
├── k8s/                       # Kubernetes manifests and templates
├── *.tf                       # Terraform configuration files
├── terraform.tfvars           # Variable values
├── terraform.tfstate*         # Terraform state files
├── terraform-*.sh             # Terraform management scripts
└── README.md                  # This file
```

## Core Terraform Files

### Main Configuration
- `main.tf` - Main Terraform configuration and locals
- `providers.tf` - Provider configurations (AWS, Kubernetes, Helm)
- `variables.tf` - Variable definitions
- `terraform.tfvars` - Variable values
- `outputs.tf` - Output definitions
- `versions.tf` - Provider version constraints

### Infrastructure Components
- `vpc.tf` - VPC and networking configuration
- `eks.tf` - EKS cluster configuration
- `addons.tf` - EKS Blueprint addons (Karpenter, monitoring, etc.)
- `emr-eks.tf` - EMR on EKS configuration
- `amp.tf` - Amazon Managed Prometheus configuration

### Application Components
- `jupyterhub.tf` - JupyterHub configuration
- `ray-cluster.tf` - Ray cluster configuration (disabled by default)
- `inference-service.tf` - Fraud detection inference service (disabled by default)
- `monitoring-dashboards.tf` - Custom monitoring dashboards

## Management Scripts

### Deployment
```bash
# Deploy complete infrastructure
./terraform-deploy.sh

# Import existing resources
./terraform-import.sh

# Validate deployment
./terraform-validate.sh

# Clean up resources
./terraform-cleanup.sh
```

### Configuration
Edit `terraform.tfvars` to customize the deployment:

```hcl
# Basic configuration
name = "emr-spark-rapids"
region = "us-west-2"

# Component toggles
enable_jupyterhub = true
enable_ray_cluster = false
enable_inference_service = false
enable_monitoring_dashboards = true

# Enhanced features
enable_nvidia_gpu_monitoring = true
enable_cost_monitoring = true
enable_karpenter_gpu_nodes = true
```

## Quick Start

1. **Configure variables**:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your settings
   ```

2. **Deploy infrastructure**:
   ```bash
   ./terraform-deploy.sh
   ```

3. **Validate deployment**:
   ```bash
   ./terraform-validate.sh
   ```

4. **Access services**:
   ```bash
   terraform output quick_start_commands
   ```

## State Management

- **State files**: `terraform.tfstate` and `terraform.tfstate.backup`
- **Remote state**: Configure in `main.tf` for production use
- **State locking**: Recommended for team environments

## Dependencies

### Required Tools
- Terraform >= 1.0
- AWS CLI configured
- kubectl configured
- Helm 3.x

### AWS Permissions
The deployment requires extensive AWS permissions including:
- EKS cluster management
- VPC and networking
- IAM roles and policies
- S3 bucket management
- EMR containers
- CloudWatch and monitoring

## Troubleshooting

### Common Issues

1. **State conflicts**: Use `terraform refresh` to sync state
2. **Resource timeouts**: Increase timeouts in provider configuration
3. **Permission errors**: Verify AWS credentials and permissions
4. **Helm conflicts**: Check for existing releases with `helm list -A`

### Validation
```bash
# Check Terraform configuration
terraform validate

# Plan changes
terraform plan

# Check cluster connectivity
kubectl get nodes

# Verify addons
kubectl get pods -A
```

## Architecture

The Terraform configuration deploys:

### Core Infrastructure
- **VPC**: Multi-AZ setup with public/private subnets
- **EKS Cluster**: Managed Kubernetes with multiple node groups
- **Karpenter**: Auto-scaling with spot instance support
- **Load Balancers**: ALB for ingress, NLB for services

### Monitoring Stack
- **Prometheus**: Metrics collection and storage
- **Grafana**: Visualization and dashboards
- **Amazon Managed Prometheus**: Long-term metrics storage
- **CloudWatch**: AWS native monitoring
- **Kubecost**: Cost monitoring and optimization

### ML Platform
- **JupyterHub**: Interactive development environment
- **Ray**: Distributed computing framework (optional)
- **EMR on EKS**: Spark job execution
- **Inference Service**: Model serving API (optional)

### Security
- **Pod Identity**: Secure AWS service access
- **Network Policies**: Pod-to-pod communication control
- **Encryption**: EBS and EFS encryption
- **RBAC**: Kubernetes role-based access control

## Cost Optimization

The platform includes several cost optimization features:
- **Spot Instances**: 60-70% cost savings
- **Auto-scaling**: Scale to zero when not needed
- **Resource Quotas**: Prevent resource waste
- **Cost Monitoring**: Real-time cost visibility

Expected monthly costs:
- **Traditional EMR**: ~$2,900/month
- **EKS Optimized**: ~$345/month
- **Total Savings**: ~$2,555/month (88% reduction)

## Support

For issues and questions:
1. Check the troubleshooting section above
2. Review Terraform and kubectl logs
3. Validate configuration with provided scripts
4. Consult AWS EKS and Terraform documentation