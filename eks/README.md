# EKS Fraud Detection with JARK Stack

This directory contains the complete implementation of a fraud detection platform using the JARK stack (JupyterHub, Argo Workflows, Ray, Karpenter) on Amazon EKS.

## 🏗️ Architecture

The implementation combines:
- **Data-on-EKS Foundation**: Proven EMR on EKS infrastructure
- **JARK Stack**: Modern ML platform capabilities
- **GPU Acceleration**: NVIDIA RAPIDS for high-performance computing

## 📁 Directory Structure

```
eks/
├── terraform/              # Infrastructure as Code
│   ├── main.tf             # Core Terraform configuration
│   ├── eks.tf              # EKS cluster with JARK stack
│   ├── ray.tf              # Ray cluster configuration
│   ├── argo.tf             # Argo Workflows setup
│   ├── emr.tf              # EMR on EKS virtual cluster
│   ├── karpenter.tf        # Auto-scaling node pools
│   ├── vpc.tf              # VPC and networking
│   ├── deploy.sh           # Deployment script
│   ├── cleanup.sh          # Cleanup script
│   └── README.md           # Detailed infrastructure docs
├── docker/                 # Container images
│   ├── emr-spark-rapids/   # EMR + RAPIDS notebook
│   ├── ray-ml/             # Ray ML training notebook
│   ├── unified-dev/        # Combined environment
│   ├── notebooks/          # Sample fraud detection notebooks
│   └── build-images.sh     # Docker build script
├── blueprint-analysis.md   # Data-on-EKS blueprint analysis
└── JARK_STACK_IMPLEMENTATION.md  # Complete implementation guide
```

## 🚀 Quick Start

### 1. Deploy Infrastructure
```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your AWS configuration
./deploy.sh
```

### 2. Build Notebook Images
```bash
cd ../docker
./build-images.sh
```

### 3. Access Services
After deployment, you'll have access to:

- **JupyterHub**: Multi-user notebook environment
  - Username: `any`
  - Password: `fraud-detection-demo`
- **Ray Dashboard**: Monitor distributed computing
- **Argo Workflows**: ML pipeline orchestration
- **Grafana**: Monitoring and observability
  - Username: `admin`
  - Password: `fraud-detection-grafana`

## 🎯 Key Features

### JupyterHub Profiles
- **EMR Spark + RAPIDS**: GPU-accelerated feature engineering
- **Ray ML Training**: Distributed model training
- **Unified Development**: Both EMR and Ray capabilities

### Auto-scaling Infrastructure
- **CPU NodePool**: C5/R5 instances for general workloads
- **GPU NodePool**: G5/G6 instances for RAPIDS acceleration
- **Memory NodePool**: R5/R6i instances for large datasets

### ML Pipeline Orchestration
- **Argo Workflows**: Kubernetes-native pipeline execution
- **Pre-built Templates**: Fraud detection pipeline workflows
- **EMR Integration**: Submit Spark jobs from workflows

### Monitoring & Observability
- **Prometheus**: Metrics collection
- **Grafana**: Visualization dashboards
- **FluentBit**: Centralized logging

## 📊 Fraud Detection Workflow

1. **Feature Engineering**: Use EMR Spark + RAPIDS in JupyterHub
2. **Model Training**: Distributed training with Ray
3. **Pipeline Orchestration**: Automate with Argo Workflows
4. **Model Serving**: Deploy with Ray Serve
5. **Monitoring**: Track performance with Grafana

## 🔧 Configuration

Key configuration options in `terraform.tfvars`:

```hcl
# JARK Stack Components
enable_jupyterhub              = true
enable_kuberay_operator        = true
enable_argo_workflows          = true
enable_kube_prometheus_stack   = true

# GPU Support
enable_nvidia_gpu_operator     = true
```

## 🔍 Monitoring

Access monitoring dashboards:
```bash
# Get service URLs
kubectl get svc --all-namespaces -o wide | grep LoadBalancer

# Check cluster status
kubectl get nodes
kubectl get pods --all-namespaces
```

## 🧹 Cleanup

To destroy all resources:
```bash
cd terraform
./cleanup.sh
```

## 📚 Documentation

- **[Terraform README](terraform/README.md)**: Detailed infrastructure documentation
- **[JARK Implementation Guide](JARK_STACK_IMPLEMENTATION.md)**: Complete implementation details
- **[Blueprint Analysis](blueprint-analysis.md)**: Data-on-EKS blueprint analysis

## 🎯 Benefits

- **🚀 Unified Development**: Single interface for all ML workflows
- **📈 Auto-scaling**: Intelligent resource provisioning with Karpenter
- **🔧 Production Ready**: Kubernetes-native ML platform
- **💰 Cost Optimized**: Spot instances and dynamic scaling
- **🔒 Secure**: IRSA-based authentication throughout

This implementation provides a complete, production-ready fraud detection platform that combines the stability of EMR on EKS with the modern capabilities of the JARK stack.