# Fraud Detection EMR on EKS Templates

This directory contains EMR on EKS job templates and configurations for fraud detection feature engineering using RAPIDS GPU acceleration. The implementation provides high-performance data processing for financial fraud detection workloads on Kubernetes.

## 🏗️ Architecture Overview

The solution consists of:
- **Custom RAPIDS Docker Image**: GPU-accelerated data processing with cuDF, cuML, cuGraph
- **EMR on EKS Job Templates**: Optimized Spark configurations for fraud detection
- **Feature Engineering Pipeline**: Time-based window features and categorical encoding
- **Kubernetes Pod Templates**: GPU-optimized executor and CPU-optimized driver configurations

## 📁 Components

### 1. Docker Images
- `Dockerfile.rapids`: Custom Docker image with RAPIDS libraries (cuDF, cuML, cuGraph)
- `requirements.txt`: Python dependencies for fraud detection workloads
- `build_docker_image.sh`: Automated Docker build and ECR push script

### 2. Job Templates
- `fraud-detection-job-template.json`: EMR on EKS job configuration template
- `driver-pod-template.yaml`: Kubernetes pod template for Spark driver (CPU-optimized)
- `executor-pod-template.yaml`: Kubernetes pod template for Spark executors (GPU-optimized)

### 3. Scripts
- `fraud_detection_feature_engineering.py`: Main feature engineering script with RAPIDS
- `submit_fraud_detection_job.sh`: Interactive job submission script
- `validate_job_config.py`: Configuration validation utility

### 4. Configuration
- `config/spark-defaults.conf`: Spark configuration optimized for RAPIDS
- `config/example-env.sh`: Example environment configuration
- `config/`: Additional configuration files

## 🚀 Quick Start

### Prerequisites

1. **EMR on EKS Cluster**: Running cluster with GPU node groups
2. **AWS CLI**: Configured with appropriate permissions
3. **Docker**: For building custom images
4. **S3 Bucket**: For data storage and job artifacts

### Step 1: Configure Environment

```bash
# Copy and customize the example configuration
cp config/example-env.sh config/env.sh
# Edit config/env.sh with your specific values
```

### Step 2: Build Custom Docker Image

```bash
# Set your ECR repository details
export ECR_REPOSITORY="your-account/fraud-detection-rapids"
export IMAGE_TAG="v1.0.0"

# Build and push to ECR
./build_docker_image.sh
```

### Step 3: Prepare Data

Ensure your fraud detection data is available in S3 with the following structure:
```
s3://your-bucket/
├── data/
│   ├── customers/          # Customer data (Parquet format)
│   ├── terminals/          # Terminal data (Parquet format)
│   └── transactions/       # Transaction data (Parquet format)
└── output/
    └── fraud-detection/    # Output location
```

### Step 4: Submit Job

```bash
# Load environment configuration
source config/env.sh

# Submit the fraud detection job
./submit_fraud_detection_job.sh
```

## 🔧 Advanced Configuration

### Custom Spark Configuration

Modify `config/spark-defaults.conf` to tune performance:

```properties
# Increase GPU memory allocation
spark.rapids.memory.gpu.allocFraction=0.8

# Adjust executor resources
spark.executor.instances=16
spark.executor.memory=32g

# Enable additional RAPIDS features
spark.rapids.sql.castStringToFloat.enabled=true
```

### Pod Template Customization

Update pod templates for specific node requirements:

```yaml
# executor-pod-template.yaml
spec:
  nodeSelector:
    node.kubernetes.io/instance-type: "g5.4xlarge"
  tolerations:
  - key: "dedicated"
    operator: "Equal"
    value: "gpu-workloads"
    effect: "NoSchedule"
```

### Environment-Specific Configurations

Create environment-specific configurations:

```bash
# Development environment
cp config/example-env.sh config/dev-env.sh

# Production environment  
cp config/example-env.sh config/prod-env.sh
```

## 📊 Feature Engineering Pipeline

The fraud detection pipeline processes three main datasets:

### Input Data Schema

**Customers Dataset:**
- `CUSTOMER_ID`: Unique customer identifier
- `x_customer_id`, `y_customer_id`: Customer location coordinates
- `mean_amount`, `std_amount`: Customer spending patterns
- `mean_nb_tx_per_day`: Average daily transaction count

**Terminals Dataset:**
- `TERMINAL_ID`: Unique terminal identifier
- `x_terminal_id`, `y_terminal_id`: Terminal location coordinates
- `merchant`: Merchant information

**Transactions Dataset:**
- `TX_DATETIME`: Transaction timestamp
- `CUSTOMER_ID`: Customer identifier
- `TERMINAL_ID`: Terminal identifier
- `TX_AMOUNT`: Transaction amount
- `TX_FRAUD`: Fraud label (0/1)

### Generated Features

The pipeline creates time-based window features:

- **Transaction Counts**: Number of transactions in time windows (1min, 5min, 15min, 30min, 1hour, 6hour, 12hour, 1day, 3day, 7day)
- **Amount Statistics**: Average, standard deviation, min, max transaction amounts per window
- **Customer Features**: Customer-specific aggregations
- **Terminal Features**: Terminal-specific aggregations
- **Categorical Encoding**: String indexing for categorical variables

## 🔍 Monitoring and Troubleshooting

### Job Monitoring

```bash
# Check job status
aws emr-containers describe-job-run \
  --virtual-cluster-id $EMR_VIRTUAL_CLUSTER_ID \
  --id $JOB_RUN_ID

# Monitor logs
aws logs tail $CLOUDWATCH_LOG_GROUP --follow

# Check Spark UI (if persistent app UI is enabled)
# Available in EMR console
```

### Common Issues

1. **GPU Resource Allocation**
   - Ensure GPU nodes are available
   - Check NVIDIA device plugin status
   - Verify GPU tolerations in executor template

2. **Memory Issues**
   - Adjust `spark.executor.memory` and `spark.executor.memoryOverhead`
   - Tune RAPIDS memory settings
   - Consider reducing `spark.executor.instances`

3. **Data Access Issues**
   - Verify S3 bucket permissions
   - Check IAM role policies
   - Ensure data paths are correct

### Validation

```bash
# Validate configuration before submission
python3 validate_job_config.py --templates-only

# Full validation (requires boto3)
python3 validate_job_config.py $EMR_VIRTUAL_CLUSTER_ID $EMR_EXECUTION_ROLE_ARN $S3_BUCKET
```

## 📈 Performance Tuning

### GPU Optimization

- **Concurrent GPU Tasks**: Set `spark.rapids.sql.concurrentGpuTasks=2` for better GPU utilization
- **Memory Pool**: Use `spark.rapids.memory.gpu.pool=ASYNC` for efficient memory management
- **Spill Configuration**: Enable `CUDF_SPILL=1` for handling large datasets

### Spark Optimization

- **Adaptive Query Execution**: Enable `spark.sql.adaptive.enabled=true`
- **Partition Coalescing**: Use `spark.sql.adaptive.coalescePartitions.enabled=true`
- **File Format**: Optimize with Parquet and Snappy compression

### Cost Optimization

- **Spot Instances**: Use Spot instances for executor nodes
- **Auto Scaling**: Configure Karpenter for dynamic scaling
- **Resource Right-sizing**: Monitor resource utilization and adjust accordingly

## 🔐 Security Considerations

- **IAM Roles**: Use least-privilege IAM policies
- **Network Security**: Configure VPC and security groups appropriately
- **Data Encryption**: Enable S3 encryption and EBS encryption
- **Image Scanning**: Enable ECR vulnerability scanning

## 📚 Additional Resources

- [EMR on EKS Documentation](https://docs.aws.amazon.com/emr/latest/EMR-on-EKS-DevelopmentGuide/)
- [RAPIDS Documentation](https://rapids.ai/)
- [Spark RAPIDS Plugin](https://nvidia.github.io/spark-rapids/)
- [Kubernetes GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/overview.html)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test with validation script
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.