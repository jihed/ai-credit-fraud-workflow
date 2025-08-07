# Fraud Detection ML Stack on EKS

This Terraform configuration deploys a complete ML Stack (JupyterHub, Argo Workflows, Ray, Karpenter) on Amazon EKS, optimized for fraud detection workloads with EMR on EKS and NVIDIA RAPIDS acceleration.

## Architecture Overview

The infrastructure combines the proven data-on-eks blueprint with modern ML platform capabilities:

### Core Infrastructure
- **EKS Cluster**: Kubernetes 1.33 with EMR on EKS support
- **Karpenter**: Dynamic node provisioning with GPU support (G5/G6 instances)
- **EMR on EKS**: Virtual cluster for running Spark RAPIDS jobs
- **NVIDIA GPU Operator**: GPU support for RAPIDS acceleration

### ML Stack Components
- **JupyterHub**: Multi-user notebook environment with custom fraud detection profiles
- **Argo Workflows**: Kubernetes-native ML pipeline orchestration
- **Ray**: Distributed ML training and high-performance model serving
- **Karpenter**: Intelligent autoscaling for all workloads

### Monitoring & Observability
- **Prometheus**: Metrics collection and alerting
- **Grafana**: Visualization dashboards with fraud detection metrics
- **FluentBit**: Centralized logging for all components

## Prerequisites

Before deploying, ensure you have:

1. **AWS CLI** configured with appropriate permissions
2. **Terraform** >= 1.3.2 installed
3. **kubectl** installed for cluster management
4. **IAM Permissions** for EKS, EMR, EC2, VPC, and S3 operations

## Quick Start

1. **Clone and Configure**:
   ```bash
   # Copy the example variables file
   cp terraform.tfvars.example terraform.tfvars
   
   # Edit terraform.tfvars with your specific configuration
   vim terraform.tfvars
   ```

2. **Deploy Infrastructure**:
   ```bash
   # Run the deployment script
   ./deploy.sh
   ```

3. **Verify Deployment**:
   ```bash
   # Check cluster status
   kubectl get nodes
   
   # Check Karpenter
   kubectl get pods -n karpenter
   
   # Check EMR namespace
   kubectl get all -n emr-fraud-detection
   ```

## Configuration Options

### Key Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `name` | Cluster name prefix | `fraud-detection-emr-eks` |
| `region` | AWS region | `us-west-2` |
| `eks_cluster_version` | EKS version | `1.33` |
| `enable_nvidia_gpu_operator` | Enable GPU support | `true` |
| `vpc_cidr` | VPC CIDR block | `10.1.0.0/16` |

### ML Stack Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `enable_jupyterhub` | Enable JupyterHub notebooks | `true` |
| `enable_kuberay_operator` | Enable Ray for distributed ML | `true` |
| `enable_argo_workflows` | Enable workflow orchestration | `true` |
| `enable_kube_prometheus_stack` | Enable monitoring stack | `true` |

### Karpenter NodePools

The configuration includes three pre-configured NodePools:

1. **spark-cpu-optimized**: C5/R5 instances for Spark drivers
2. **spark-gpu-rapids**: G5/G6 GPU instances for RAPIDS workloads
3. **spark-memory-optimized**: R5/R6i instances for large datasets

## ML Stack Usage

### JupyterHub Notebooks

Access JupyterHub for interactive development:

```bash
# Get JupyterHub URL
kubectl get svc -n jupyterhub proxy-public -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Login credentials
# Username: any
# Password: fraud-detection-demo
```

**Available Notebook Profiles:**
- **EMR Spark + RAPIDS**: Feature engineering with GPU acceleration
- **Ray ML Training**: Distributed ML training and serving
- **Unified Development**: Both EMR Spark and Ray capabilities

### Ray Distributed Computing

Monitor Ray cluster and submit distributed jobs:

```bash
# Check Ray cluster status
kubectl get rayclusters -n ray-clusters

# Get Ray Dashboard URL
kubectl get svc -n ray-clusters ray-dashboard-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Connect to Ray from notebook
import ray
ray.init(address="ray://ray-cluster-head:10001")
```

### Argo Workflows

Orchestrate ML pipelines with Argo Workflows:

```bash
# Get Argo UI URL
kubectl get svc -n argo-workflows argo-server -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Submit fraud detection pipeline
argo submit -n argo-workflows --from workflowtemplate/fraud-detection-pipeline
```

### Monitoring with Grafana

Access monitoring dashboards:

```bash
# Get Grafana URL
kubectl get svc -n kube-prometheus-stack kube-prometheus-stack-grafana -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Login credentials
# Username: admin
# Password: fraud-detection-grafana
```

## EMR Job Submission

Submit EMR jobs using the virtual cluster:

```bash
# Get cluster information
VIRTUAL_CLUSTER_ID=$(terraform output -raw emr_virtual_cluster_id)
EXECUTION_ROLE_ARN=$(terraform output -raw emr_execution_role_arn)
S3_BUCKET=$(terraform output -raw s3_bucket_name)

# Submit a RAPIDS-enabled Spark job
aws emr-containers start-job-run \
  --virtual-cluster-id $VIRTUAL_CLUSTER_ID \
  --name "fraud-detection-feature-engineering" \
  --execution-role-arn $EXECUTION_ROLE_ARN \
  --release-label emr-7.9.0-latest \
  --job-driver '{
    "sparkSubmitJobDriver": {
      "entryPoint": "s3://'$S3_BUCKET'/fraud-data/feature_engineering.py",
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
          "spark.rapids.sql.enabled": "true"
        }
      }
    ]
  }'
```

## Monitoring and Logging

- **CloudWatch Logs**: EMR job logs are automatically sent to CloudWatch
- **Spark History Server**: Access via EMR console
- **Kubernetes Logs**: FluentBit forwards pod logs to CloudWatch

## Cost Optimization

The configuration includes several cost optimization features:

- **Spot Instances**: Karpenter uses spot instances by default
- **Dynamic Scaling**: Nodes are provisioned only when needed
- **Automatic Cleanup**: Unused nodes are terminated after 30 seconds
- **Resource Limits**: CPU limits prevent runaway scaling

## Security Features

- **IRSA**: IAM Roles for Service Accounts for secure AWS API access
- **Network Policies**: Isolated networking for EMR workloads
- **Encrypted Storage**: EBS volumes and S3 buckets use encryption
- **RBAC**: Kubernetes role-based access control for EMR namespace

## Troubleshooting

### Common Issues

1. **GPU Nodes Not Starting**:
   ```bash
   # Check Karpenter logs
   kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter
   
   # Check NodePool status
   kubectl get nodepools
   ```

2. **EMR Jobs Failing**:
   ```bash
   # Check EMR job logs
   aws emr-containers describe-job-run --virtual-cluster-id $VIRTUAL_CLUSTER_ID --id $JOB_ID
   
   # Check pod events
   kubectl get events -n emr-fraud-detection
   ```

3. **NVIDIA GPU Operator Issues**:
   ```bash
   # Check GPU operator status
   kubectl get pods -n gpu-operator
   
   # Check GPU availability
   kubectl get nodes -o json | jq '.items[].status.allocatable."nvidia.com/gpu"'
   ```

### Resource Limits

If you encounter resource limits, adjust the Karpenter NodePool limits:

```bash
# Edit the NodePool
kubectl edit nodepool spark-gpu-rapids

# Increase CPU limits
spec:
  limits:
    cpu: 2000  # Increase from 1000
```

## Cleanup

To destroy all resources:

```bash
./cleanup.sh
```

This will:
1. Cancel any running EMR jobs
2. Clean up Kubernetes resources
3. Empty S3 buckets
4. Destroy all Terraform resources

## Support

For issues related to:
- **EKS/Kubernetes**: Check AWS EKS documentation
- **EMR on EKS**: Check AWS EMR on EKS documentation
- **Karpenter**: Check Karpenter documentation
- **NVIDIA GPU Operator**: Check NVIDIA GPU Operator documentation

## Next Steps

After successful deployment:

1. Deploy ML Stack applications: `cd ../helm && ./scripts/deploy-applications.sh`
2. Upload your fraud detection notebooks to the S3 bucket
3. Adapt the existing EMR notebooks for EMR on EKS
4. Submit test jobs to validate GPU acceleration
5. Set up monitoring and alerting for production use

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                        AWS Account                          │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                    VPC                              │   │
│  │                                                     │   │
│  │  ┌─────────────────────────────────────────────┐   │   │
│  │  │              EKS Cluster                    │   │   │
│  │  │                                             │   │   │
│  │  │  ┌─────────────┐  ┌─────────────────────┐  │   │   │
│  │  │  │   System    │  │     Karpenter       │  │   │   │
│  │  │  │   Nodes     │  │   (Dynamic Nodes)   │  │   │   │
│  │  │  │             │  │                     │  │   │   │
│  │  │  │ ┌─────────┐ │  │ ┌─────────────────┐ │  │   │   │
│  │  │  │ │Karpenter│ │  │ │  GPU Nodes      │ │  │   │   │
│  │  │  │ │   Pod   │ │  │ │  (G5/G6)        │ │  │   │   │
│  │  │  │ └─────────┘ │  │ │                 │ │  │   │   │
│  │  │  │             │  │ │ ┌─────────────┐ │ │  │   │   │
│  │  │  │ ┌─────────┐ │  │ │ │EMR Spark    │ │ │  │   │   │
│  │  │  │ │GPU Oper.│ │  │ │ │Pods         │ │ │  │   │   │
│  │  │  │ └─────────┘ │  │ │ └─────────────┘ │ │  │   │   │
│  │  │  └─────────────┘  │ └─────────────────┘ │  │   │   │
│  │  │                   │                     │  │   │   │
│  │  │  ┌─────────────────────────────────────┐  │   │   │
│  │  │  │        EMR on EKS Namespace         │  │   │   │
│  │  │  │                                     │  │   │   │
│  │  │  │  ┌─────────────────────────────┐   │  │   │   │
│  │  │  │  │     EMR Virtual Cluster     │   │  │   │   │
│  │  │  │  └─────────────────────────────┘   │  │   │   │
│  │  │  └─────────────────────────────────────┘  │   │   │
│  │  └─────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                    S3 Bucket                        │   │
│  │                                                     │   │
│  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐   │   │
│  │  │ Fraud Data  │ │   Models    │ │Event Logs   │   │   │
│  │  └─────────────┘ └─────────────┘ └─────────────┘   │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```