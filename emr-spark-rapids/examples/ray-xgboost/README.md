# Ray XGBoost Distributed Training on EKS

This directory contains the configuration and examples for running distributed XGBoost training using Ray on the EKS cluster with GPU acceleration.

## Overview

The Ray cluster setup provides:
- **KubeRay Operator**: Manages Ray clusters on Kubernetes
- **GPU-enabled Ray Workers**: Utilize G5 instances for GPU-accelerated training
- **CPU Ray Workers**: Handle data preprocessing and coordination tasks
- **Distributed XGBoost Training**: Scale training across multiple GPU nodes
- **S3 Integration**: Load data and save models to S3

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Ray Head      │    │  GPU Workers    │    │  CPU Workers    │
│   (Scheduler)   │◄──►│  (Training)     │◄──►│  (Preprocessing)│
│   Core Nodes    │    │  G5.2xlarge     │    │  M5.xlarge      │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
                    ┌─────────────────┐
                    │   S3 Storage    │
                    │ Data & Models   │
                    └─────────────────┘
```

## Components

### 1. KubeRay Operator
- Manages Ray cluster lifecycle
- Handles autoscaling of worker nodes
- Provides Ray dashboard for monitoring

### 2. Ray Cluster Configuration
- **Head Node**: Runs on core nodes for scheduling and coordination
- **GPU Workers**: Run on G5 instances with NVIDIA GPU support
- **CPU Workers**: Run on M5 instances for data processing tasks

### 3. Karpenter Node Pools
- **ray-gpu-nodepool**: Provisions G5 instances for GPU workloads
- **ray-cpu-nodepool**: Provisions M5/C5 instances for CPU workloads

## Deployment

### Prerequisites
1. EKS cluster with EMR Spark RAPIDS blueprint deployed
2. Karpenter configured and running
3. NVIDIA device plugin or GPU operator enabled
4. S3 bucket for data and model storage

### Deploy Ray Infrastructure

1. **Deploy KubeRay Operator and Ray Cluster**:
   ```bash
   # Apply the Terraform configuration
   terraform apply -target=helm_release.kuberay_operator
   terraform apply -target=kubectl_manifest.ray_cluster
   ```

2. **Deploy Karpenter Node Pools** (Optional - for dedicated Ray nodes):
   ```bash
   kubectl apply -f ray-karpenter-nodepool.yaml
   ```

3. **Verify Ray Cluster**:
   ```bash
   # Check Ray cluster status
   kubectl get raycluster -n ray-ml
   
   # Check Ray pods
   kubectl get pods -n ray-ml
   
   # Access Ray dashboard
   kubectl port-forward svc/ray-dashboard -n ray-ml 8265:8265
   # Open http://localhost:8265 in browser
   ```

## Usage

### 1. Prepare Training Data

Ensure your fraud detection data is available in S3 in parquet format:
```
s3://your-bucket/processed-data/features/
├── part-00000.parquet
├── part-00001.parquet
└── ...
```

### 2. Configure Training Job

Update the environment variables in `ray-training-job.yaml`:
```yaml
env:
- name: S3_BUCKET
  value: "your-fraud-detection-bucket"  # Your S3 bucket name
- name: DATA_PREFIX
  value: "processed-data/features"      # Path to training data
- name: MODEL_OUTPUT_PREFIX
  value: "models/xgboost"               # Path for model output
- name: AWS_DEFAULT_REGION
  value: "us-west-2"                    # Your AWS region
```

### 3. Submit Training Job

```bash
# Create the training job
kubectl apply -f ray-training-job.yaml

# Monitor job progress
kubectl logs -f job/ray-xgboost-training -n ray-ml

# Check job status
kubectl get jobs -n ray-ml
```

### 4. Monitor Training

```bash
# Access Ray dashboard for detailed monitoring
kubectl port-forward svc/ray-dashboard -n ray-ml 8265:8265

# Check Ray cluster resources
kubectl exec -it deployment/fraud-training-cluster-head -n ray-ml -- python -c "import ray; ray.init(); print(ray.cluster_resources())"
```

## Training Script Features

The `train_xgboost_ray.py` script provides:

- **Data Loading**: Efficient loading from S3 parquet files
- **Feature Engineering**: Automated feature preparation
- **Distributed Training**: Ray-based XGBoost training with GPU acceleration
- **Model Evaluation**: Comprehensive evaluation metrics
- **Model Persistence**: Save models and metadata to S3
- **Error Handling**: Robust error handling and logging

### Key Parameters

```python
xgb_params = {
    'objective': 'binary:logistic',
    'eval_metric': 'auc',
    'tree_method': 'gpu_hist',      # GPU acceleration
    'gpu_id': 0,
    'max_depth': 6,
    'learning_rate': 0.1,
    'scale_pos_weight': 10,         # Handle class imbalance
    # ... other parameters
}
```

### Scaling Configuration

```python
scaling_config = ScalingConfig(
    num_workers=4,                      # Number of Ray workers
    use_gpu=True,                       # Enable GPU usage
    resources_per_worker={"CPU": 4, "GPU": 1}
)
```

## Performance Optimization

### GPU Utilization
- Uses `tree_method='gpu_hist'` for GPU-accelerated training
- Configures appropriate GPU memory allocation
- Handles GPU device selection automatically

### Data Loading
- Parallel data loading from S3
- Efficient parquet format processing
- Memory-optimized data structures

### Scaling
- Automatic worker scaling based on workload
- Spot instance support for cost optimization
- Resource-aware scheduling

## Monitoring and Troubleshooting

### Ray Dashboard
Access the Ray dashboard for real-time monitoring:
```bash
kubectl port-forward svc/ray-dashboard -n ray-ml 8265:8265
```

### Common Issues

1. **GPU Not Available**:
   ```bash
   # Check GPU nodes
   kubectl get nodes -l nvidia.com/gpu.present=true
   
   # Check GPU device plugin
   kubectl get pods -n kube-system | grep nvidia
   ```

2. **Ray Cluster Not Starting**:
   ```bash
   # Check Ray operator logs
   kubectl logs -n ray-system deployment/kuberay-operator
   
   # Check Ray head pod logs
   kubectl logs -n ray-ml deployment/fraud-training-cluster-head
   ```

3. **Training Job Failures**:
   ```bash
   # Check job logs
   kubectl logs -f job/ray-xgboost-training -n ray-ml
   
   # Check Ray worker logs
   kubectl logs -n ray-ml -l app=ray-worker
   ```

### Resource Monitoring

```bash
# Check cluster resources
kubectl top nodes

# Check Ray cluster resources
kubectl exec -it deployment/fraud-training-cluster-head -n ray-ml -- \
  python -c "import ray; ray.init(); print(ray.cluster_resources())"

# Monitor GPU utilization
kubectl exec -it <gpu-worker-pod> -n ray-ml -- nvidia-smi
```

## Cost Optimization

- **Spot Instances**: Use spot instances for Ray workers to reduce costs
- **Auto-scaling**: Automatic scaling down when not in use
- **Resource Limits**: Set appropriate resource limits to prevent over-provisioning
- **Job Cleanup**: Automatic cleanup of completed jobs

## Next Steps

1. **Model Serving**: Deploy trained models using the inference service (Task 7)
2. **Pipeline Integration**: Integrate with EMR on EKS data processing (Task 5)
3. **Monitoring**: Set up comprehensive monitoring (Task 10)
4. **CI/CD**: Implement GitOps deployment (Task 11)

## References

- [Ray Documentation](https://docs.ray.io/)
- [KubeRay Documentation](https://ray-project.github.io/kuberay/)
- [XGBoost Ray Integration](https://docs.ray.io/en/latest/train/examples/xgboost/xgboost_example.html)
- [AWS Data on EKS](https://github.com/awslabs/data-on-eks)