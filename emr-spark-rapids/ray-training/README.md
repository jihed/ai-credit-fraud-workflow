# Ray XGBoost Distributed Training for Fraud Detection

This directory contains the implementation for migrating XGBoost training from SageMaker to Ray-based distributed training on EKS, as part of the EMR to EKS migration project.

## Overview

The Ray XGBoost training system provides:

- **Distributed GPU-accelerated training** using Ray and XGBoost with `tree_method="gpu_hist"`
- **SageMaker-compatible model artifacts** saved to S3 for seamless integration
- **Comprehensive monitoring and logging** with CloudWatch integration
- **Kubernetes-native deployment** with auto-scaling and resource management
- **Production-ready error handling** and recovery mechanisms

## Requirements Implemented

This implementation addresses the following requirements from the EMR to EKS migration spec:

- **2.2**: GPU-accelerated training with tree_method="gpu_hist" using AI on EKS GPU configurations
- **2.3**: Model artifacts saved to S3 in the same format as SageMaker
- **2.4**: Training job monitoring and logging functionality through AI on EKS monitoring patterns

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   S3 Data       │    │   Ray Cluster   │    │   S3 Models     │
│   (Features)    │───▶│   (GPU Workers) │───▶│   (Artifacts)   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                              │
                              ▼
                       ┌─────────────────┐
                       │   CloudWatch    │
                       │   (Monitoring)  │
                       └─────────────────┘
```

## Files Structure

```
ray-training/
├── ray_xgboost_trainer.py          # Main training script
├── training_monitor.py             # Monitoring and logging utilities
├── ray-xgboost-training-job.yaml   # Kubernetes job manifest
├── submit_training_job.sh           # Job submission script
├── requirements.txt                 # Python dependencies
└── README.md                        # This file
```

## Quick Start

### 1. Prerequisites

Ensure you have:
- EKS cluster with Ray operator deployed
- Ray cluster running in the `ray-ml` namespace
- S3 bucket with processed fraud detection features
- AWS credentials configured for S3 access
- GPU nodes available in the cluster

### 2. Submit Training Job

```bash
# Basic training job submission
./submit_training_job.sh submit \
  --s3-bucket your-fraud-detection-bucket \
  --data-prefix processed-data/features \
  --workers 4 \
  --rounds 100

# Advanced configuration
./submit_training_job.sh submit \
  --s3-bucket your-fraud-detection-bucket \
  --data-prefix processed-data/features \
  --model-prefix models/xgboost/v2 \
  --workers 8 \
  --rounds 200 \
  --max-depth 8 \
  --learning-rate 0.05 \
  --scale-pos-weight 15 \
  --max-files 100
```

### 3. Monitor Training

```bash
# Check job status
./submit_training_job.sh status

# View real-time logs
./submit_training_job.sh logs -j ray-xgboost-fraud-training-20240128-143022

# Monitor training progress
./submit_training_job.sh monitor -j ray-xgboost-fraud-training-20240128-143022
```

### 4. Manage Jobs

```bash
# List all training jobs
./submit_training_job.sh list

# Clean up completed jobs
./submit_training_job.sh cleanup

# Delete specific job
./submit_training_job.sh delete -j ray-xgboost-fraud-training-20240128-143022
```

## Configuration

### Training Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--s3-bucket` | Required | S3 bucket for data and models |
| `--data-prefix` | `processed-data/features` | S3 prefix for training data |
| `--model-prefix` | `models/xgboost` | S3 prefix for model output |
| `--workers` | `4` | Number of Ray workers |
| `--rounds` | `100` | Number of boosting rounds |
| `--max-files` | `50` | Maximum training files to load |
| `--max-depth` | `6` | XGBoost maximum tree depth |
| `--learning-rate` | `0.1` | Learning rate |
| `--scale-pos-weight` | `10` | Scale for positive class (fraud) |

### XGBoost GPU Configuration

The training automatically configures XGBoost for GPU acceleration:

```python
xgb_params = {
    'objective': 'binary:logistic',
    'eval_metric': ['auc', 'logloss'],
    'tree_method': 'gpu_hist',        # GPU acceleration
    'gpu_id': 0,
    'predictor': 'gpu_predictor',
    'max_depth': 6,
    'learning_rate': 0.1,
    'subsample': 0.8,
    'colsample_bytree': 0.8,
    'scale_pos_weight': 10,           # Handle class imbalance
    'random_state': 42
}
```

### Ray Scaling Configuration

```python
scaling_config = ScalingConfig(
    num_workers=4,                    # Distributed workers
    use_gpu=True,                     # Enable GPU usage
    resources_per_worker={
        "CPU": 4,
        "GPU": 1
    }
)
```

## Model Artifacts

The training produces SageMaker-compatible artifacts in S3:

```
s3://your-bucket/models/xgboost/
├── v_20240128_143022/
│   ├── model.xgb                    # XGBoost model file
│   ├── model_metadata.json          # Model metadata
│   └── feature_importance.csv       # Feature importance
└── latest/
    ├── model.xgb                    # Latest model (symlink)
    └── model_metadata.json          # Latest metadata
```

### Model Metadata Format

```json
{
  "model_version": "v_20240128_143022",
  "timestamp": "20240128_143022",
  "feature_names": ["feature1", "feature2", ...],
  "model_metrics": {
    "test_auc": 0.8542,
    "test_accuracy": 0.9123,
    "test_f1": 0.7834
  },
  "training_config": {
    "num_workers": 4,
    "num_boost_round": 100,
    "use_gpu": true
  },
  "xgboost_version": "1.7.6",
  "model_format": "xgboost"
}
```

## Monitoring and Logging

### CloudWatch Integration

Training metrics are automatically sent to CloudWatch:

- **Log Group**: `/aws/eks/ray-training`
- **Metrics**: Training loss, AUC, system resources
- **Alerts**: Memory usage, GPU utilization, training stalls

### Ray Metrics

Real-time metrics available through Ray dashboard:

- Training progress and performance
- Resource utilization (CPU, GPU, memory)
- Distributed training coordination
- Worker health and status

### System Monitoring

Comprehensive system monitoring includes:

```python
# Training metrics
- Training/validation loss and AUC
- Learning rate and epoch timing
- Model performance metrics

# System metrics  
- CPU and memory utilization
- GPU memory and utilization
- Network I/O and disk usage
- Ray cluster health
```

## Error Handling and Recovery

### Automatic Recovery

- **Spot instance interruption**: Automatic checkpoint and resume
- **Worker failures**: Ray handles worker replacement
- **Data loading errors**: Graceful degradation and retry
- **Memory issues**: Automatic garbage collection and optimization

### Manual Recovery

```bash
# Check failed job logs
./submit_training_job.sh logs -j failed-job-name

# Restart from checkpoint
./submit_training_job.sh submit --resume-from-checkpoint s3://bucket/checkpoints/path

# Debug Ray cluster
kubectl get raycluster -n ray-ml
kubectl describe raycluster fraud-training-cluster -n ray-ml
```

## Performance Optimization

### GPU Optimization

- **Tree method**: `gpu_hist` for GPU-accelerated training
- **Memory management**: Efficient GPU memory allocation
- **Batch processing**: Optimized data loading and preprocessing
- **Mixed precision**: Automatic FP16 optimization where supported

### Distributed Training

- **Data parallelism**: Efficient data distribution across workers
- **Gradient synchronization**: Optimized communication patterns
- **Load balancing**: Dynamic worker allocation based on data size
- **Fault tolerance**: Automatic recovery from worker failures

### Resource Management

```yaml
# Kubernetes resource configuration
resources:
  requests:
    cpu: "4"
    memory: "8Gi"
    nvidia.com/gpu: "1"
  limits:
    cpu: "8"
    memory: "16Gi"
    nvidia.com/gpu: "1"
```

## Troubleshooting

### Common Issues

1. **Ray cluster connection failed**
   ```bash
   # Check Ray cluster status
   kubectl get raycluster -n ray-ml
   kubectl get pods -n ray-ml -l app.kubernetes.io/name=ray
   ```

2. **GPU not available**
   ```bash
   # Check GPU nodes
   kubectl get nodes -l node.kubernetes.io/instance-type=g5.2xlarge
   kubectl describe node <gpu-node-name>
   ```

3. **S3 access denied**
   ```bash
   # Check service account and IAM role
   kubectl get serviceaccount ray-training-sa -n ray-ml -o yaml
   ```

4. **Out of memory errors**
   ```bash
   # Reduce batch size or number of files
   ./submit_training_job.sh submit --max-files 25 --workers 2
   ```

### Debug Commands

```bash
# Check job events
kubectl describe job ray-xgboost-fraud-training-20240128-143022 -n ray-ml

# Check pod logs
kubectl logs -n ray-ml -l job-name=ray-xgboost-fraud-training-20240128-143022

# Check Ray cluster resources
kubectl exec -it ray-head-pod -n ray-ml -- ray status

# Check GPU utilization
kubectl exec -it training-pod -n ray-ml -- nvidia-smi
```

## Migration from SageMaker

### Key Differences

| Aspect | SageMaker | Ray on EKS |
|--------|-----------|------------|
| **Scaling** | Fixed instance count | Dynamic auto-scaling |
| **Cost** | Pay per training job | Pay for cluster resources |
| **GPU Support** | Limited GPU types | Full GPU instance support |
| **Monitoring** | CloudWatch only | Ray + CloudWatch + Prometheus |
| **Customization** | Limited | Full Kubernetes flexibility |

### Migration Steps

1. **Data Compatibility**: Ensure feature data is in the same format
2. **Model Format**: XGBoost models are directly compatible
3. **Hyperparameters**: Transfer existing hyperparameter configurations
4. **Monitoring**: Update monitoring dashboards for Ray metrics
5. **CI/CD**: Update deployment pipelines for Kubernetes jobs

## Best Practices

### Resource Management

- Use spot instances for cost optimization
- Set appropriate resource requests and limits
- Monitor GPU utilization and scale accordingly
- Implement automatic cleanup of completed jobs

### Data Management

- Partition training data for optimal loading
- Use S3 Transfer Acceleration for large datasets
- Implement data validation and quality checks
- Cache frequently accessed data

### Model Management

- Version all model artifacts with timestamps
- Implement model validation before deployment
- Use feature stores for consistent feature engineering
- Maintain model lineage and experiment tracking

### Security

- Use IAM roles for service accounts (IRSA)
- Encrypt data in transit and at rest
- Implement network policies for pod communication
- Regular security scanning of container images

## Contributing

When contributing to this training system:

1. Follow the existing code structure and patterns
2. Add comprehensive logging and error handling
3. Update documentation for any configuration changes
4. Test with different data sizes and cluster configurations
5. Ensure backward compatibility with existing model formats

## Support

For issues and questions:

1. Check the troubleshooting section above
2. Review Ray and XGBoost documentation
3. Check Kubernetes cluster logs and events
4. Consult the EMR to EKS migration design document