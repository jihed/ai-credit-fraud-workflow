# Fraud Detection EMR on EKS - Deployment Guide

This guide explains the complete deployment process for the fraud detection demo using EMR on EKS with a clear separation between infrastructure and applications.

## Architecture Overview

The deployment follows infrastructure-as-code best practices with clear separation of concerns:

```
┌─────────────────────────────────────────────────────────────┐
│                    Infrastructure Layer                     │
│                      (Terraform)                           │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  • EKS Cluster                                      │   │
│  │  • VPC, Subnets, Security Groups                   │   │
│  │  • IAM Roles and Policies                          │   │
│  │  • Karpenter (Node Provisioning)                   │   │
│  │  • NVIDIA GPU Operator                             │   │
│  │  • Core EKS Add-ons (ALB, EBS CSI, etc.)          │   │
│  │  • EMR on EKS Virtual Cluster                      │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────┐
│                   Application Layer                         │
│                  (Helm Charts / GitOps)                    │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  • JupyterHub (Data Science Environment)           │   │
│  │  • Ray Cluster (Distributed ML)                    │   │
│  │  • Airflow (Workflow Orchestration) [Optional]     │   │
│  │  • Kafka (Streaming) [Optional]                    │   │
│  │  • Application-specific Configurations             │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Why This Separation?

### Infrastructure (Terraform)
- **Lifecycle**: Long-lived, changes infrequently
- **Scope**: Cluster-wide resources, security, networking
- **Ownership**: Platform/DevOps teams
- **State Management**: Terraform state for infrastructure resources

### Applications (Helm/GitOps)
- **Lifecycle**: Frequently updated, version-controlled
- **Scope**: Application-specific configurations
- **Ownership**: Development/Data Science teams
- **State Management**: Kubernetes native, Git-driven

## Deployment Options

You have three deployment approaches for applications:

### Option 1: Direct Helm Deployment (Simplest)
Best for: Development, testing, quick demos

### Option 2: GitOps with ArgoCD (Recommended)
Best for: Production, team collaboration, audit trails

### Option 3: Hybrid Approach
Infrastructure via Terraform, critical apps via GitOps, dev apps via Helm

## Step-by-Step Deployment

### Phase 1: Infrastructure Deployment

1. **Prerequisites**:
   ```bash
   # Install required tools
   brew install terraform awscli kubectl helm
   
   # Configure AWS credentials
   aws configure
   ```

2. **Deploy Infrastructure**:
   ```bash
   cd terraform
   
   # Copy and customize configuration
   cp terraform.tfvars.example terraform.tfvars
   vim terraform.tfvars
   
   # Deploy infrastructure
   ./deploy.sh
   ```

3. **Verify Infrastructure**:
   ```bash
   # Check cluster access
   kubectl get nodes
   
   # Verify Karpenter
   kubectl get pods -n karpenter
   
   # Check GPU operator (if enabled)
   kubectl get pods -n gpu-operator
   ```

### Phase 2A: Application Deployment (Helm)

1. **Deploy ML Stack Applications**:
   ```bash
   cd eks/helm
   
   # Add Helm repositories
   ./scripts/add-helm-repos.sh
   
   # Deploy all ML Stack applications
   ./scripts/deploy-applications.sh
   ```

2. **Access Applications**:
   ```bash
   # Get JupyterHub URL
   kubectl get svc -n jupyterhub proxy-public
   
   # Access Ray Dashboard
   kubectl port-forward -n ray-system svc/ray-cluster-head-svc 8265:8265
   ```

### Phase 2B: Application Deployment (GitOps)

1. **Install ArgoCD**:
   ```bash
   cd ../../gitops
   
   # Install ArgoCD
   ./scripts/install-argocd.sh
   ```

2. **Deploy Applications**:
   ```bash
   # Deploy ArgoCD applications
   kubectl apply -f applications/
   
   # Check application status
   argocd app list
   ```

3. **Access ArgoCD UI**:
   ```bash
   # Get admin password
   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
   
   # Port forward to access UI
   kubectl port-forward svc/argocd-server -n argocd 8080:443
   
   # Access at https://localhost:8080
   ```

## Configuration Management

### Infrastructure Configuration

Edit `terraform/terraform.tfvars`:
```hcl
# Basic Configuration
name   = "fraud-detection-emr-eks"
region = "us-west-2"

# EKS Configuration
eks_cluster_version = "1.33"

# Add-on Configuration
enable_nvidia_gpu_operator = true
enable_amazon_prometheus   = false

# Tags
tags = {
  Environment = "demo"
  Team        = "data-science"
  Project     = "fraud-detection"
}
```

### Application Configuration

#### Helm Values
Edit files in `eks/helm/values/`:
- `jupyterhub-values.yaml`: JupyterHub configuration
- `ray-values.yaml`: Ray cluster configuration
- `argo-values.yaml`: Argo Workflows configuration
- `grafana-values.yaml`: Grafana monitoring configuration

#### GitOps Configuration
Edit ArgoCD applications in `gitops/applications/`:
- `jupyterhub-app.yaml`: JupyterHub application definition
- `ray-cluster-app.yaml`: Ray cluster application definition

## Environment-Specific Deployments

### Development Environment
```bash
# Use smaller instance types and fewer replicas
# terraform/terraform.tfvars
tags = {
  Environment = "dev"
}

# eks/helm/values/ray-values.yaml
worker:
  replicas: 1
  minReplicas: 0
  maxReplicas: 3
```

### Production Environment
```bash
# Use production-grade configurations
# terraform/terraform.tfvars
enable_amazon_prometheus = true
enable_vpc_endpoints     = true

# eks/helm/values/jupyterhub-values.yaml
hub:
  config:
    JupyterHub:
      authenticator_class: 'oauthenticator.generic.GenericOAuthenticator'
```

## Monitoring and Observability

### Infrastructure Monitoring
- **CloudWatch**: EKS cluster metrics and logs
- **Karpenter Metrics**: Node provisioning and scaling
- **EMR Console**: EMR job monitoring

### Application Monitoring
- **JupyterHub**: User activity and resource usage
- **Ray Dashboard**: Distributed computing metrics
- **ArgoCD UI**: Application deployment status

## Security Best Practices

### Infrastructure Security
- **IRSA**: IAM Roles for Service Accounts
- **Network Policies**: Pod-to-pod communication control
- **Encryption**: EBS volumes and S3 buckets encrypted
- **VPC Endpoints**: Private API access (optional)

### Application Security
- **Authentication**: Proper authentication for JupyterHub
- **RBAC**: Kubernetes role-based access control
- **Secrets Management**: Kubernetes secrets for sensitive data
- **Image Security**: Use trusted container images

## Troubleshooting

### Infrastructure Issues
```bash
# Check Terraform state
terraform show

# Verify EKS cluster
aws eks describe-cluster --name <cluster-name>

# Check Karpenter logs
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter
```

### Application Issues
```bash
# Check Helm releases
helm list --all-namespaces

# Check pod status
kubectl get pods --all-namespaces

# Check ArgoCD application status
argocd app get <app-name>
```

### Common Issues

1. **GPU Nodes Not Starting**:
   - Check Karpenter NodePool configuration
   - Verify GPU instance availability in region
   - Check NVIDIA GPU Operator status

2. **EMR Jobs Failing**:
   - Verify EMR execution role permissions
   - Check S3 bucket access
   - Review EMR job logs in CloudWatch

3. **Application Sync Issues** (GitOps):
   - Check Git repository access
   - Verify Helm chart versions
   - Review ArgoCD application logs

## Cleanup

### Application Cleanup
```bash
# Helm cleanup
helm uninstall jupyterhub -n jupyterhub
helm uninstall ray-cluster -n ray-system

# GitOps cleanup
kubectl delete -f gitops/applications/
kubectl delete namespace argocd
```

### Infrastructure Cleanup
```bash
cd terraform
./cleanup.sh
```

## Next Steps

After successful deployment:

1. **Upload Notebooks**: Copy fraud detection notebooks to JupyterHub
2. **Test EMR Jobs**: Submit sample EMR on EKS jobs
3. **Configure Monitoring**: Set up alerts and dashboards
4. **Security Hardening**: Implement production security measures
5. **CI/CD Integration**: Integrate with your CI/CD pipeline

## Best Practices Summary

### Infrastructure
- ✅ Use Terraform for infrastructure
- ✅ Separate environments with different tfvars
- ✅ Use remote state storage
- ✅ Implement proper IAM policies
- ✅ Enable logging and monitoring

### Applications
- ✅ Use Helm for application packaging
- ✅ Use GitOps for production deployments
- ✅ Version control all configurations
- ✅ Implement proper secret management
- ✅ Use namespace isolation

### Operations
- ✅ Implement monitoring and alerting
- ✅ Regular backup and disaster recovery testing
- ✅ Security scanning and updates
- ✅ Cost optimization and resource management
- ✅ Documentation and runbooks

This approach provides a robust, scalable, and maintainable foundation for running fraud detection workloads on EMR on EKS while following cloud-native best practices.