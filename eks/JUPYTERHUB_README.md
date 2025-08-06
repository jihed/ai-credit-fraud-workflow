# JupyterHub on EKS for Fraud Detection

This implementation provides a GPU-enabled JupyterHub environment on Amazon EKS with integrated access to EMR on EKS and Ray clusters for fraud detection workloads.

## Features

- **GPU-Enabled Notebooks**: NVIDIA GPU support for RAPIDS acceleration
- **EMR on EKS Integration**: Submit Spark jobs with RAPIDS directly from notebooks
- **Ray Cluster Access**: Distributed ML training with XGBoost
- **Shared Storage**: EFS-based shared storage for collaboration
- **Pre-built Templates**: Ready-to-use notebooks for common workflows
- **Auto-scaling**: Kubernetes-native scaling for notebook instances

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    JupyterHub on EKS                        │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │   Hub Pod   │  │ Proxy Pod   │  │ User Pods   │         │
│  │             │  │             │  │ (GPU-enabled)│         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
├─────────────────────────────────────────────────────────────┤
│                    Shared Storage (EFS)                     │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │ EMR on EKS  │  │ Ray Cluster │  │   S3 Data   │         │
│  │   (RAPIDS)  │  │  (XGBoost)  │  │   Storage   │         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
└─────────────────────────────────────────────────────────────┘
```

## Components

### 1. Custom Docker Image
- **Base**: `jupyter/datascience-notebook:latest`
- **RAPIDS**: cuDF, cuML, cuGraph for GPU acceleration
- **Ray**: Distributed computing framework
- **AWS SDK**: EMR and S3 integration
- **ML Libraries**: XGBoost, scikit-learn, pandas

### 2. Kubernetes Resources
- **Namespace**: `jupyterhub`
- **Service Account**: IRSA-enabled for AWS access
- **Storage**: EFS for shared data, EBS for user home directories
- **RBAC**: Appropriate permissions for notebook operations

### 3. Notebook Templates
- **EMR Spark RAPIDS**: Submit GPU-accelerated Spark jobs
- **Ray XGBoost Training**: Distributed ML training
- **End-to-End Pipeline**: Complete fraud detection workflow

## Deployment

### Prerequisites
1. EKS cluster with GPU nodes (g5.2xlarge)
2. EMR on EKS virtual clusters configured
3. Ray operator deployed
4. AWS CLI and kubectl configured

### Quick Start
```bash
# Deploy JupyterHub
./deploy-jupyterhub.sh

# Validate deployment
./validate-jupyterhub.sh

# Build custom image (if needed)
./build-jupyterhub-image.sh
```

### Manual Deployment
```bash
# 1. Apply Terraform configuration
terraform apply -target=helm_release.jupyterhub

# 2. Build and push custom image
./build-jupyterhub-image.sh

# 3. Wait for deployment
kubectl wait --for=condition=ready pod -l app=jupyterhub,component=hub -n jupyterhub --timeout=300s

# 4. Get access URL
kubectl get svc proxy-public -n jupyterhub
```

## Configuration

### Environment Variables
The notebooks have access to these environment variables:
- `EMR_VIRTUAL_CLUSTER_ID`: EMR virtual cluster ID
- `EMR_EXECUTION_ROLE_ARN`: EMR execution role ARN
- `RAY_ADDRESS`: Ray cluster address
- `S3_BUCKET`: S3 bucket for data storage
- `AWS_DEFAULT_REGION`: AWS region

### Authentication
- **Type**: Dummy authenticator (for demo)
- **Users**: admin, data-scientist, ml-engineer
- **Password**: fraud-detection-demo

### Resource Allocation
- **CPU**: 2-4 cores per notebook
- **Memory**: 8-16 GB per notebook
- **GPU**: 1 NVIDIA GPU per notebook
- **Storage**: 20 GB per user + shared EFS

## Usage

### Accessing JupyterHub
1. Get the load balancer URL:
   ```bash
   kubectl get svc proxy-public -n jupyterhub
   ```
2. Open the URL in your browser
3. Login with credentials: `admin` / `fraud-detection-demo`
4. Start a new server (GPU-enabled)

### Available Templates

#### 1. EMR Spark RAPIDS Example
**File**: `templates/emr-spark-rapids-example.ipynb`

Submit GPU-accelerated Spark jobs to EMR on EKS:
```python
# Submit RAPIDS-enabled Spark job
job_config = {
    "name": "rapids-fraud-detection",
    "virtualClusterId": VIRTUAL_CLUSTER_ID,
    "executionRoleArn": EXECUTION_ROLE_ARN,
    # ... GPU configuration
}
response = emr_client.start_job_run(**job_config)
```

#### 2. Ray XGBoost Training
**File**: `templates/ray-xgboost-training.ipynb`

Distributed XGBoost training with GPU acceleration:
```python
# Connect to Ray cluster
ray.init(address=RAY_ADDRESS)

# Train distributed XGBoost model
trainer = ray_xgboost.XGBoostTrainer(
    scaling_config=ScalingConfig(num_workers=2, use_gpu=True),
    params={'tree_method': 'gpu_hist'},
    datasets={"train": train_dataset}
)
result = trainer.fit()
```

#### 3. End-to-End Pipeline
**File**: `templates/fraud-detection-pipeline.ipynb`

Complete fraud detection workflow:
1. Data processing with EMR on EKS + RAPIDS
2. Model training with Ray + XGBoost
3. Model deployment and inference testing

### Development Workflow

1. **Data Exploration**: Use RAPIDS for GPU-accelerated data analysis
2. **Feature Engineering**: Submit Spark jobs to EMR on EKS
3. **Model Training**: Use Ray for distributed training
4. **Model Evaluation**: Test models in the notebook environment
5. **Deployment**: Save models to S3 for inference service

## Monitoring

### JupyterHub Metrics
```bash
# Check pod status
kubectl get pods -n jupyterhub

# View logs
kubectl logs -n jupyterhub -l app=jupyterhub,component=hub

# Monitor resource usage
kubectl top pods -n jupyterhub
```

### GPU Utilization
```bash
# Check GPU nodes
kubectl get nodes -l nvidia.com/gpu=true

# Monitor GPU usage in notebooks
nvidia-smi
```

## Troubleshooting

### Common Issues

#### 1. Notebook Server Won't Start
```bash
# Check events
kubectl get events -n jupyterhub --sort-by='.lastTimestamp'

# Check node resources
kubectl describe nodes -l nvidia.com/gpu=true
```

#### 2. GPU Not Available
```bash
# Verify GPU nodes
kubectl get nodes -l nvidia.com/gpu=true

# Check NVIDIA device plugin
kubectl get pods -n kube-system -l name=nvidia-device-plugin-daemonset
```

#### 3. EMR Jobs Fail
```bash
# Check EMR virtual cluster
aws emr-containers list-virtual-clusters

# Verify execution role
aws iam get-role --role-name <execution-role-name>
```

#### 4. Ray Connection Issues
```bash
# Check Ray cluster
kubectl get raycluster -n ray-system

# Verify Ray head service
kubectl get svc -n ray-system -l ray.io/node-type=head
```

### Logs and Debugging
```bash
# JupyterHub hub logs
kubectl logs -n jupyterhub -l app=jupyterhub,component=hub

# User notebook logs
kubectl logs -n jupyterhub <user-pod-name>

# EMR job logs
aws logs describe-log-streams --log-group-name /aws/emr-containers/<cluster-id>
```

## Security

### RBAC Configuration
- Service accounts with minimal required permissions
- Namespace isolation for JupyterHub components
- IRSA for secure AWS API access

### Network Security
- Internal load balancer for JupyterHub access
- Security groups restricting EFS access
- Encrypted storage (EFS and EBS)

### Data Protection
- Encryption in transit and at rest
- Secure S3 bucket access via IAM roles
- Audit logging for all operations

## Cost Optimization

### Resource Management
- Auto-scaling for notebook instances
- Spot instances for GPU nodes (where appropriate)
- Automatic cleanup of idle notebooks

### Monitoring Costs
```bash
# Check resource usage
kubectl top nodes
kubectl top pods -n jupyterhub

# Monitor S3 costs
aws s3api get-bucket-metrics-configuration --bucket <bucket-name>
```

## Scaling

### Horizontal Scaling
- Multiple notebook instances per user
- Ray cluster auto-scaling
- EMR on EKS job parallelization

### Vertical Scaling
- Configurable resource limits per notebook
- GPU memory optimization
- Storage capacity planning

## Integration

### CI/CD Pipeline
- Automated image builds
- Terraform-based infrastructure updates
- GitOps deployment with FluxCD

### External Services
- S3 for data storage and model artifacts
- CloudWatch for logging and monitoring
- Prometheus/Grafana for metrics

## Support

### Documentation
- [JupyterHub Documentation](https://jupyterhub.readthedocs.io/)
- [EMR on EKS Guide](https://docs.aws.amazon.com/emr/latest/EMR-on-EKS-DevelopmentGuide/)
- [Ray Documentation](https://docs.ray.io/)
- [RAPIDS Documentation](https://rapids.ai/)

### Community
- [JupyterHub Discourse](https://discourse.jupyter.org/c/jupyterhub)
- [Ray Community](https://discuss.ray.io/)
- [RAPIDS Community](https://rapids.ai/community.html)