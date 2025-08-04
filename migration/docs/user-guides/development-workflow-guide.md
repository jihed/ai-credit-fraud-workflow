# Development Workflow Guide for EKS-based Fraud Detection

## Overview

This guide provides data scientists and ML engineers with comprehensive instructions for developing, testing, and deploying fraud detection models using the migrated EKS-based infrastructure.

## Table of Contents

1. [Getting Started](#getting-started)
2. [Development Environment Setup](#development-environment-setup)
3. [Notebook Integration](#notebook-integration)
4. [Data Processing Workflow](#data-processing-workflow)
5. [Model Training Workflow](#model-training-workflow)
6. [Model Deployment Workflow](#model-deployment-workflow)
7. [Testing and Validation](#testing-and-validation)
8. [Best Practices](#best-practices)
9. [Troubleshooting](#troubleshooting)

## Getting Started

### Prerequisites

- Access to EKS cluster and JupyterHub
- AWS CLI configured with appropriate permissions
- Basic knowledge of Kubernetes, Docker, and Python
- Familiarity with Spark, RAPIDS, and XGBoost

### Access Requirements

- JupyterHub account with appropriate permissions
- S3 bucket access for data and models
- EMR on EKS virtual cluster access
- Ray cluster access for distributed training

## Development Environment Setup

### 1. Accessing JupyterHub

1. **Navigate to JupyterHub URL:**
   ```
   https://jupyterhub.your-domain.com
   ```

2. **Login with your credentials**

3. **Select appropriate server options:**
   - **CPU-only notebook**: For data exploration and light processing
   - **GPU-enabled notebook**: For RAPIDS development and testing
   - **Large memory notebook**: For processing large datasets

### 2. Environment Configuration

Create a new notebook and run the following setup:

```python
# Install required packages (if not already available)
!pip install --quiet \
    cudf-cu11==23.06.* \
    cuml-cu11==23.06.* \
    xgboost==1.7.3 \
    ray[train]==2.8.0 \
    boto3==1.26.137 \
    s3fs==2023.6.0

# Import required libraries
import os
import pandas as pd
import numpy as np
import boto3
import s3fs
from datetime import datetime, timedelta

# RAPIDS imports (for GPU-enabled notebooks)
try:
    import cudf
    import cuml
    RAPIDS_AVAILABLE = True
    print("RAPIDS libraries loaded successfully")
except ImportError:
    RAPIDS_AVAILABLE = False
    print("RAPIDS not available - using CPU libraries")

# Configure AWS credentials (if needed)
import boto3
session = boto3.Session()
credentials = session.get_credentials()
print(f"AWS Account: {boto3.client('sts').get_caller_identity()['Account']}")
```

### 3. Connecting to EKS Services

```python
# Configure Kubernetes client
from kubernetes import client, config

# Load in-cluster config (when running in JupyterHub pod)
try:
    config.load_incluster_config()
    print("Loaded in-cluster Kubernetes config")
except:
    # Fallback to local config
    config.load_kube_config()
    print("Loaded local Kubernetes config")

k8s_client = client.ApiClient()

# Test connection
v1 = client.CoreV1Api()
print(f"Connected to cluster: {v1.list_namespace().items[0].metadata.name}")
```

## Notebook Integration

### 1. Data Exploration Notebook Template

Create a new notebook for data exploration:

```python
# Data Exploration Template
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns

# Configure S3 filesystem
s3_fs = s3fs.S3FileSystem()

# Data paths
DATA_BUCKET = "your-data-bucket"
CUSTOMERS_PATH = f"s3://{DATA_BUCKET}/fraud-data/customers.parquet"
TRANSACTIONS_PATH = f"s3://{DATA_BUCKET}/fraud-data/transactions.parquet"
TERMINALS_PATH = f"s3://{DATA_BUCKET}/fraud-data/terminals.parquet"

# Load sample data for exploration
print("Loading sample data...")
customers_df = pd.read_parquet(CUSTOMERS_PATH, filesystem=s3_fs).sample(n=10000)
transactions_df = pd.read_parquet(TRANSACTIONS_PATH, filesystem=s3_fs).sample(n=50000)
terminals_df = pd.read_parquet(TERMINALS_PATH, filesystem=s3_fs)

print(f"Customers: {len(customers_df)} rows")
print(f"Transactions: {len(transactions_df)} rows") 
print(f"Terminals: {len(terminals_df)} rows")

# Basic data exploration
print("\n=== Customer Data ===")
print(customers_df.head())
print(customers_df.info())

print("\n=== Transaction Data ===")
print(transactions_df.head())
print(transactions_df.info())

# Fraud distribution
fraud_dist = transactions_df['TX_FRAUD_1'].value_counts()
print(f"\nFraud Distribution:\n{fraud_dist}")
print(f"Fraud Rate: {fraud_dist[1] / len(transactions_df) * 100:.2f}%")

# Visualizations
plt.figure(figsize=(12, 4))

plt.subplot(1, 3, 1)
transactions_df['TX_AMOUNT'].hist(bins=50)
plt.title('Transaction Amount Distribution')
plt.xlabel('Amount')

plt.subplot(1, 3, 2)
fraud_dist.plot(kind='bar')
plt.title('Fraud vs Non-Fraud')
plt.xlabel('Fraud Label')

plt.subplot(1, 3, 3)
transactions_df.groupby('TX_FRAUD_1')['TX_AMOUNT'].mean().plot(kind='bar')
plt.title('Average Amount by Fraud Status')
plt.xlabel('Fraud Label')

plt.tight_layout()
plt.show()
```

### 2. Feature Engineering Notebook Template

```python
# Feature Engineering with RAPIDS
import cudf if RAPIDS_AVAILABLE else pd

def create_time_windows(df, time_col='TX_DATETIME', windows=[1, 7, 30]):
    """Create time-based aggregation windows"""
    
    if RAPIDS_AVAILABLE:
        # Use cuDF for GPU acceleration
        df = cudf.from_pandas(df) if isinstance(df, pd.DataFrame) else df
        df[time_col] = cudf.to_datetime(df[time_col])
    else:
        # Use pandas for CPU processing
        df[time_col] = pd.to_datetime(df[time_col])
    
    features = []
    
    for window in windows:
        window_start = df[time_col] - pd.Timedelta(days=window)
        
        # Customer-based features
        customer_features = df.groupby('CUSTOMER_ID').agg({
            'TX_AMOUNT': ['count', 'mean', 'std', 'sum'],
            'TERMINAL_ID': 'nunique'
        }).reset_index()
        
        # Flatten column names
        customer_features.columns = [
            'CUSTOMER_ID',
            f'customer_nb_txns_{window}d',
            f'customer_avg_amt_{window}d', 
            f'customer_std_amt_{window}d',
            f'customer_sum_amt_{window}d',
            f'customer_nb_terminals_{window}d'
        ]
        
        features.append(customer_features)
    
    return features

# Load full dataset for feature engineering
print("Loading full dataset for feature engineering...")
transactions_full = pd.read_parquet(TRANSACTIONS_PATH, filesystem=s3_fs)

# Create features
print("Creating time-based features...")
time_features = create_time_windows(transactions_full, windows=[1, 7, 30])

# Merge features back to main dataset
feature_df = transactions_full.copy()
for features in time_features:
    feature_df = feature_df.merge(features, on='CUSTOMER_ID', how='left')

print(f"Feature engineering complete. Shape: {feature_df.shape}")
print(f"New features: {[col for col in feature_df.columns if col not in transactions_full.columns]}")

# Save processed features
output_path = f"s3://{DATA_BUCKET}/processed-features/fraud_features_{datetime.now().strftime('%Y%m%d')}.parquet"
feature_df.to_parquet(output_path, filesystem=s3_fs)
print(f"Features saved to: {output_path}")
```

### 3. EMR on EKS Job Submission

```python
# Submit EMR on EKS job from notebook
import boto3
import json

def submit_emr_job(script_path, job_name, virtual_cluster_id, execution_role_arn):
    """Submit EMR on EKS job"""
    
    emr_containers = boto3.client('emr-containers')
    
    job_config = {
        'name': job_name,
        'virtualClusterId': virtual_cluster_id,
        'executionRoleArn': execution_role_arn,
        'releaseLabel': 'emr-6.15.0-latest',
        'jobDriver': {
            'sparkSubmitJobDriver': {
                'entryPoint': script_path,
                'sparkSubmitParameters': ' '.join([
                    '--conf spark.plugins=com.nvidia.spark.SQLPlugin',
                    '--conf spark.rapids.sql.enabled=true',
                    '--conf spark.executor.resource.gpu.amount=1',
                    '--conf spark.executor.instances=4',
                    '--conf spark.executor.memory=30G',
                    '--conf spark.executor.cores=4',
                    '--conf spark.driver.memory=8G',
                    '--conf spark.sql.adaptive.enabled=true'
                ])
            }
        },
        'configurationOverrides': {
            'monitoringConfiguration': {
                'persistentAppUI': 'ENABLED',
                'cloudWatchMonitoringConfiguration': {
                    'logGroupName': '/aws/emr-containers/fraud-detection'
                }
            }
        }
    }
    
    response = emr_containers.start_job_run(**job_config)
    job_run_id = response['id']
    
    print(f"Job submitted successfully!")
    print(f"Job Run ID: {job_run_id}")
    print(f"Monitor at: https://console.aws.amazon.com/emr/home#/containers/clusters/{virtual_cluster_id}/job-runs/{job_run_id}")
    
    return job_run_id

# Example usage
VIRTUAL_CLUSTER_ID = "your-virtual-cluster-id"
EXECUTION_ROLE_ARN = "arn:aws:iam::your-account:role/EMRContainers-JobExecutionRole"
SCRIPT_S3_PATH = f"s3://{DATA_BUCKET}/scripts/fraud_detection_feature_engineering.py"

job_id = submit_emr_job(
    script_path=SCRIPT_S3_PATH,
    job_name=f"fraud-feature-eng-{datetime.now().strftime('%Y%m%d-%H%M%S')}",
    virtual_cluster_id=VIRTUAL_CLUSTER_ID,
    execution_role_arn=EXECUTION_ROLE_ARN
)
```

## Data Processing Workflow

### 1. Large-Scale Data Processing with EMR on EKS

For processing large datasets, use EMR on EKS with RAPIDS:

```python
# Create Spark script for large-scale processing
spark_script = '''
from pyspark.sql import SparkSession
from pyspark.sql.functions import *
from pyspark.sql.types import *
import sys

# Initialize Spark with RAPIDS
spark = SparkSession.builder \\
    .appName("FraudDetectionFeatureEngineering") \\
    .config("spark.plugins", "com.nvidia.spark.SQLPlugin") \\
    .config("spark.rapids.sql.enabled", "true") \\
    .getOrCreate()

# Read data from S3
customers_df = spark.read.parquet("s3://your-bucket/fraud-data/customers.parquet")
transactions_df = spark.read.parquet("s3://your-bucket/fraud-data/transactions.parquet")
terminals_df = spark.read.parquet("s3://your-bucket/fraud-data/terminals.parquet")

# Feature engineering with Spark SQL
transactions_df.createOrReplaceTempView("transactions")
customers_df.createOrReplaceTempView("customers")
terminals_df.createOrReplaceTempView("terminals")

# Create time-based features using window functions
features_sql = """
SELECT 
    t.*,
    -- Customer features (1 day window)
    COUNT(*) OVER (
        PARTITION BY t.CUSTOMER_ID 
        ORDER BY UNIX_TIMESTAMP(t.TX_DATETIME) 
        RANGE BETWEEN 86400 PRECEDING AND CURRENT ROW
    ) as customer_nb_txns_1d,
    
    AVG(t.TX_AMOUNT) OVER (
        PARTITION BY t.CUSTOMER_ID 
        ORDER BY UNIX_TIMESTAMP(t.TX_DATETIME) 
        RANGE BETWEEN 86400 PRECEDING AND CURRENT ROW
    ) as customer_avg_amt_1d,
    
    -- Terminal features (1 day window)
    COUNT(*) OVER (
        PARTITION BY t.TERMINAL_ID 
        ORDER BY UNIX_TIMESTAMP(t.TX_DATETIME) 
        RANGE BETWEEN 86400 PRECEDING AND CURRENT ROW
    ) as terminal_nb_txns_1d,
    
    AVG(t.TX_AMOUNT) OVER (
        PARTITION BY t.TERMINAL_ID 
        ORDER BY UNIX_TIMESTAMP(t.TX_DATETIME) 
        RANGE BETWEEN 86400 PRECEDING AND CURRENT ROW
    ) as terminal_avg_amt_1d
    
FROM transactions t
ORDER BY t.TX_DATETIME
"""

features_df = spark.sql(features_sql)

# Write results back to S3
features_df.write \\
    .mode("overwrite") \\
    .parquet("s3://your-bucket/processed-features/fraud_features_large_scale")

spark.stop()
'''

# Save script to S3
script_path = f"s3://{DATA_BUCKET}/scripts/large_scale_feature_engineering.py"
with open('/tmp/large_scale_script.py', 'w') as f:
    f.write(spark_script)

# Upload to S3
s3_client = boto3.client('s3')
s3_client.upload_file('/tmp/large_scale_script.py', DATA_BUCKET, 'scripts/large_scale_feature_engineering.py')

print(f"Script uploaded to: {script_path}")

# Submit job
job_id = submit_emr_job(
    script_path=script_path,
    job_name=f"large-scale-features-{datetime.now().strftime('%Y%m%d-%H%M%S')}",
    virtual_cluster_id=VIRTUAL_CLUSTER_ID,
    execution_role_arn=EXECUTION_ROLE_ARN
)
```

### 2. Monitoring Job Progress

```python
def monitor_emr_job(virtual_cluster_id, job_run_id):
    """Monitor EMR job progress"""
    
    emr_containers = boto3.client('emr-containers')
    
    while True:
        response = emr_containers.describe_job_run(
            virtualClusterId=virtual_cluster_id,
            id=job_run_id
        )
        
        job_run = response['jobRun']
        state = job_run['state']
        
        print(f"Job {job_run_id} status: {state}")
        
        if state in ['COMPLETED', 'FAILED', 'CANCELLED']:
            break
            
        time.sleep(30)
    
    if state == 'COMPLETED':
        print("Job completed successfully!")
    else:
        print(f"Job failed with state: {state}")
        if 'stateDetails' in job_run:
            print(f"Details: {job_run['stateDetails']}")

# Monitor the submitted job
import time
monitor_emr_job(VIRTUAL_CLUSTER_ID, job_id)
```

## Model Training Workflow

### 1. Ray-based Distributed Training

```python
# Ray training from notebook
import ray
from ray import train
from ray.train.xgboost import XGBoostTrainer
from ray.train import ScalingConfig

def train_fraud_model_with_ray(data_path, model_output_path):
    """Train fraud detection model using Ray"""
    
    # Connect to Ray cluster
    ray.init(address="ray://ray-head.ml-team-a.svc.cluster.local:10001")
    
    # Load and prepare data
    @ray.remote
    def load_data():
        import pandas as pd
        import s3fs
        
        s3_fs = s3fs.S3FileSystem()
        df = pd.read_parquet(data_path, filesystem=s3_fs)
        
        # Prepare features and target
        feature_cols = [col for col in df.columns if col not in ['TX_FRAUD_1', 'TX_DATETIME', 'CUSTOMER_ID', 'TERMINAL_ID']]
        X = df[feature_cols]
        y = df['TX_FRAUD_1']
        
        return X, y, feature_cols
    
    # Load data
    X, y, feature_names = ray.get(load_data.remote())
    
    # Create Ray dataset
    dataset = ray.data.from_pandas(pd.concat([X, y], axis=1))
    
    # Configure XGBoost parameters
    xgb_params = {
        'objective': 'binary:logistic',
        'eval_metric': 'auc',
        'max_depth': 6,
        'learning_rate': 0.1,
        'subsample': 0.8,
        'colsample_bytree': 0.8,
        'tree_method': 'gpu_hist',  # Use GPU if available
        'random_state': 42
    }
    
    # Configure scaling
    scaling_config = ScalingConfig(
        num_workers=4,
        use_gpu=True,
        resources_per_worker={"CPU": 2, "GPU": 1}
    )
    
    # Create trainer
    trainer = XGBoostTrainer(
        scaling_config=scaling_config,
        label_column='TX_FRAUD_1',
        params=xgb_params,
        datasets={"train": dataset},
        num_boost_round=100
    )
    
    # Train model
    result = trainer.fit()
    
    # Save model
    checkpoint = result.checkpoint
    model_path = checkpoint.path + "/model.xgb"
    
    # Upload to S3
    s3_client = boto3.client('s3')
    bucket, key = model_output_path.replace('s3://', '').split('/', 1)
    s3_client.upload_file(model_path, bucket, key)
    
    # Save metadata
    metadata = {
        'model_path': model_output_path,
        'feature_names': feature_names,
        'training_params': xgb_params,
        'training_metrics': result.metrics,
        'timestamp': datetime.now().isoformat()
    }
    
    metadata_key = key.replace('.xgb', '_metadata.json')
    s3_client.put_object(
        Bucket=bucket,
        Key=metadata_key,
        Body=json.dumps(metadata, indent=2)
    )
    
    print(f"Model saved to: {model_output_path}")
    print(f"Training metrics: {result.metrics}")
    
    ray.shutdown()
    return result

# Train model
model_output_path = f"s3://{DATA_BUCKET}/models/fraud_model_{datetime.now().strftime('%Y%m%d_%H%M%S')}.xgb"
training_result = train_fraud_model_with_ray(
    data_path=f"s3://{DATA_BUCKET}/processed-features/fraud_features_large_scale",
    model_output_path=model_output_path
)
```

### 2. Hyperparameter Tuning

```python
# Hyperparameter tuning with Ray Tune
from ray import tune
from ray.tune.schedulers import ASHAScheduler

def tune_hyperparameters(data_path):
    """Tune XGBoost hyperparameters using Ray Tune"""
    
    def objective(config):
        # Training function for hyperparameter tuning
        trainer = XGBoostTrainer(
            scaling_config=ScalingConfig(num_workers=2, use_gpu=True),
            label_column='TX_FRAUD_1',
            params={
                'objective': 'binary:logistic',
                'eval_metric': 'auc',
                'max_depth': config['max_depth'],
                'learning_rate': config['learning_rate'],
                'subsample': config['subsample'],
                'colsample_bytree': config['colsample_bytree'],
                'tree_method': 'gpu_hist'
            },
            datasets={"train": ray.data.read_parquet(data_path)},
            num_boost_round=50
        )
        
        result = trainer.fit()
        return {"auc": result.metrics["train-auc"]}
    
    # Define search space
    search_space = {
        'max_depth': tune.randint(3, 10),
        'learning_rate': tune.loguniform(0.01, 0.3),
        'subsample': tune.uniform(0.6, 1.0),
        'colsample_bytree': tune.uniform(0.6, 1.0)
    }
    
    # Configure scheduler
    scheduler = ASHAScheduler(
        metric="auc",
        mode="max",
        max_t=100,
        grace_period=10,
        reduction_factor=2
    )
    
    # Run tuning
    tuner = tune.Tuner(
        objective,
        param_space=search_space,
        tune_config=tune.TuneConfig(
            scheduler=scheduler,
            num_samples=20
        )
    )
    
    results = tuner.fit()
    best_config = results.get_best_result(metric="auc", mode="max").config
    
    print(f"Best hyperparameters: {best_config}")
    return best_config

# Run hyperparameter tuning
best_params = tune_hyperparameters(f"s3://{DATA_BUCKET}/processed-features/fraud_features_large_scale")
```

## Model Deployment Workflow

### 1. Deploy Model to Inference Service

```python
def deploy_model_to_inference(model_s3_path, deployment_name="fraud-inference"):
    """Deploy model to Kubernetes inference service"""
    
    from kubernetes import client, config
    
    # Update deployment with new model path
    apps_v1 = client.AppsV1Api()
    
    # Get current deployment
    deployment = apps_v1.read_namespaced_deployment(
        name=deployment_name,
        namespace="ml-team-a"
    )
    
    # Update environment variable with new model path
    for container in deployment.spec.template.spec.containers:
        if container.name == "inference":
            for env_var in container.env:
                if env_var.name == "MODEL_S3_PATH":
                    env_var.value = model_s3_path
                    break
    
    # Apply update
    apps_v1.patch_namespaced_deployment(
        name=deployment_name,
        namespace="ml-team-a",
        body=deployment
    )
    
    print(f"Deployment updated with model: {model_s3_path}")
    
    # Wait for rollout to complete
    import time
    for i in range(60):  # Wait up to 5 minutes
        deployment = apps_v1.read_namespaced_deployment(
            name=deployment_name,
            namespace="ml-team-a"
        )
        
        if (deployment.status.ready_replicas == deployment.spec.replicas and
            deployment.status.updated_replicas == deployment.spec.replicas):
            print("Deployment rollout completed successfully!")
            break
        
        print(f"Waiting for rollout... ({i+1}/60)")
        time.sleep(5)
    else:
        print("Warning: Deployment rollout may not have completed")

# Deploy the trained model
deploy_model_to_inference(model_output_path)
```

### 2. Test Deployed Model

```python
def test_inference_service(service_url, test_data):
    """Test the deployed inference service"""
    
    import requests
    
    # Test health endpoint
    health_response = requests.get(f"{service_url}/health")
    print(f"Health check: {health_response.status_code}")
    
    # Test prediction endpoint
    sample_features = test_data.iloc[0].drop(['TX_FRAUD_1']).to_dict()
    
    prediction_response = requests.post(
        f"{service_url}/predict",
        json={"features": sample_features}
    )
    
    if prediction_response.status_code == 200:
        result = prediction_response.json()
        print(f"Prediction successful!")
        print(f"Prediction: {result['prediction']}")
        print(f"Probability: {result['probability']:.4f}")
    else:
        print(f"Prediction failed: {prediction_response.status_code}")
        print(prediction_response.text)

# Test the service
SERVICE_URL = "http://fraud-inference.ml-team-a.svc.cluster.local"
test_data = pd.read_parquet(f"s3://{DATA_BUCKET}/processed-features/fraud_features_large_scale", filesystem=s3_fs).sample(10)
test_inference_service(SERVICE_URL, test_data)
```

## Testing and Validation

### 1. Model Performance Validation

```python
def validate_model_performance(model_s3_path, test_data_path):
    """Validate model performance on test data"""
    
    import xgboost as xgb
    from sklearn.metrics import classification_report, roc_auc_score, confusion_matrix
    
    # Download model from S3
    s3_client = boto3.client('s3')
    bucket, key = model_s3_path.replace('s3://', '').split('/', 1)
    s3_client.download_file(bucket, key, '/tmp/model.xgb')
    
    # Load model
    model = xgb.Booster()
    model.load_model('/tmp/model.xgb')
    
    # Load test data
    test_df = pd.read_parquet(test_data_path, filesystem=s3_fs)
    
    # Prepare features
    feature_cols = [col for col in test_df.columns if col not in ['TX_FRAUD_1', 'TX_DATETIME', 'CUSTOMER_ID', 'TERMINAL_ID']]
    X_test = test_df[feature_cols]
    y_test = test_df['TX_FRAUD_1']
    
    # Make predictions
    dtest = xgb.DMatrix(X_test)
    y_pred_proba = model.predict(dtest)
    y_pred = (y_pred_proba > 0.5).astype(int)
    
    # Calculate metrics
    auc_score = roc_auc_score(y_test, y_pred_proba)
    
    print(f"Model Performance on Test Data:")
    print(f"AUC Score: {auc_score:.4f}")
    print("\nClassification Report:")
    print(classification_report(y_test, y_pred))
    print("\nConfusion Matrix:")
    print(confusion_matrix(y_test, y_pred))
    
    return {
        'auc_score': auc_score,
        'predictions': y_pred_proba,
        'actuals': y_test.values
    }

# Validate model performance
validation_results = validate_model_performance(
    model_s3_path=model_output_path,
    test_data_path=f"s3://{DATA_BUCKET}/test-data/fraud_test_data.parquet"
)
```

### 2. A/B Testing Setup

```python
def setup_ab_test(model_a_path, model_b_path, traffic_split=0.5):
    """Setup A/B test between two models"""
    
    # Create A/B test configuration
    ab_test_config = {
        'models': {
            'model_a': {
                'path': model_a_path,
                'traffic_percentage': int(traffic_split * 100)
            },
            'model_b': {
                'path': model_b_path,
                'traffic_percentage': int((1 - traffic_split) * 100)
            }
        },
        'metrics_to_track': [
            'prediction_latency',
            'prediction_accuracy',
            'false_positive_rate',
            'false_negative_rate'
        ],
        'duration_days': 7
    }
    
    # Save A/B test configuration
    config_path = f"s3://{DATA_BUCKET}/ab-tests/config_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
    s3_client = boto3.client('s3')
    bucket, key = config_path.replace('s3://', '').split('/', 1)
    s3_client.put_object(
        Bucket=bucket,
        Key=key,
        Body=json.dumps(ab_test_config, indent=2)
    )
    
    print(f"A/B test configuration saved to: {config_path}")
    print(f"Model A ({traffic_split*100:.0f}% traffic): {model_a_path}")
    print(f"Model B ({(1-traffic_split)*100:.0f}% traffic): {model_b_path}")
    
    return config_path

# Setup A/B test between current and new model
ab_test_config_path = setup_ab_test(
    model_a_path="s3://your-bucket/models/current_model.xgb",
    model_b_path=model_output_path,
    traffic_split=0.8  # 80% current model, 20% new model
)
```

## Best Practices

### 1. Code Organization

```python
# Recommended project structure in notebooks
"""
fraud-detection-notebooks/
├── 01_data_exploration.ipynb
├── 02_feature_engineering.ipynb
├── 03_model_training.ipynb
├── 04_model_evaluation.ipynb
├── 05_model_deployment.ipynb
├── utils/
│   ├── data_processing.py
│   ├── feature_engineering.py
│   ├── model_training.py
│   └── deployment.py
└── config/
    ├── data_config.yaml
    ├── model_config.yaml
    └── deployment_config.yaml
"""

# Create utility functions for reusability
def create_utility_functions():
    """Create reusable utility functions"""
    
    utils_code = '''
# utils/data_processing.py
import pandas as pd
import s3fs

class DataProcessor:
    def __init__(self, s3_bucket):
        self.s3_bucket = s3_bucket
        self.s3_fs = s3fs.S3FileSystem()
    
    def load_data(self, data_type):
        """Load data from S3"""
        path = f"s3://{self.s3_bucket}/fraud-data/{data_type}.parquet"
        return pd.read_parquet(path, filesystem=self.s3_fs)
    
    def save_data(self, df, output_path):
        """Save data to S3"""
        df.to_parquet(output_path, filesystem=self.s3_fs)
        print(f"Data saved to: {output_path}")

# utils/feature_engineering.py
def create_time_features(df, time_col='TX_DATETIME'):
    """Create time-based features"""
    df[time_col] = pd.to_datetime(df[time_col])
    df['hour'] = df[time_col].dt.hour
    df['day_of_week'] = df[time_col].dt.dayofweek
    df['is_weekend'] = df['day_of_week'].isin([5, 6]).astype(int)
    return df

def create_aggregation_features(df, group_cols, agg_cols, windows):
    """Create aggregation features with time windows"""
    features = []
    for window in windows:
        for group_col in group_cols:
            for agg_col in agg_cols:
                feature_name = f"{group_col}_{agg_col}_{window}d"
                # Implementation here
    return features
'''
    
    # Save utility functions
    with open('/tmp/utils.py', 'w') as f:
        f.write(utils_code)
    
    print("Utility functions created. Import with: from utils import *")

create_utility_functions()
```

### 2. Configuration Management

```python
# Use configuration files for reproducibility
import yaml

def create_config_files():
    """Create configuration files for different components"""
    
    # Data configuration
    data_config = {
        's3_bucket': 'your-data-bucket',
        'data_paths': {
            'customers': 'fraud-data/customers.parquet',
            'transactions': 'fraud-data/transactions.parquet',
            'terminals': 'fraud-data/terminals.parquet'
        },
        'feature_config': {
            'time_windows': [1, 7, 30],
            'aggregation_functions': ['count', 'mean', 'std', 'sum'],
            'categorical_features': ['TERMINAL_ID'],
            'numerical_features': ['TX_AMOUNT']
        }
    }
    
    # Model configuration
    model_config = {
        'xgboost_params': {
            'objective': 'binary:logistic',
            'eval_metric': 'auc',
            'max_depth': 6,
            'learning_rate': 0.1,
            'subsample': 0.8,
            'colsample_bytree': 0.8,
            'tree_method': 'gpu_hist'
        },
        'training_params': {
            'num_boost_round': 100,
            'early_stopping_rounds': 10,
            'verbose_eval': 10
        },
        'ray_config': {
            'num_workers': 4,
            'use_gpu': True,
            'resources_per_worker': {'CPU': 2, 'GPU': 1}
        }
    }
    
    # Deployment configuration
    deployment_config = {
        'kubernetes': {
            'namespace': 'ml-team-a',
            'deployment_name': 'fraud-inference',
            'service_name': 'fraud-inference',
            'replicas': 3
        },
        'inference_config': {
            'model_path_env': 'MODEL_S3_PATH',
            'health_check_path': '/health',
            'prediction_path': '/predict'
        }
    }
    
    # Save configurations
    configs = {
        'data_config.yaml': data_config,
        'model_config.yaml': model_config,
        'deployment_config.yaml': deployment_config
    }
    
    for filename, config in configs.items():
        with open(f'/tmp/{filename}', 'w') as f:
            yaml.dump(config, f, default_flow_style=False)
        print(f"Created {filename}")

create_config_files()

# Load and use configurations
with open('/tmp/data_config.yaml', 'r') as f:
    data_config = yaml.safe_load(f)

print(f"S3 Bucket: {data_config['s3_bucket']}")
print(f"Time windows: {data_config['feature_config']['time_windows']}")
```

### 3. Version Control and Reproducibility

```python
# Track experiment metadata
def track_experiment(experiment_name, config, metrics, artifacts):
    """Track experiment metadata for reproducibility"""
    
    experiment_metadata = {
        'experiment_name': experiment_name,
        'timestamp': datetime.now().isoformat(),
        'config': config,
        'metrics': metrics,
        'artifacts': artifacts,
        'environment': {
            'python_version': sys.version,
            'notebook_path': os.getcwd(),
            'git_commit': get_git_commit() if get_git_commit() else 'unknown'
        }
    }
    
    # Save metadata
    metadata_path = f"s3://{DATA_BUCKET}/experiments/{experiment_name}/metadata.json"
    s3_client = boto3.client('s3')
    bucket, key = metadata_path.replace('s3://', '').split('/', 1)
    s3_client.put_object(
        Bucket=bucket,
        Key=key,
        Body=json.dumps(experiment_metadata, indent=2)
    )
    
    print(f"Experiment metadata saved to: {metadata_path}")
    return experiment_metadata

def get_git_commit():
    """Get current git commit hash"""
    try:
        import subprocess
        result = subprocess.run(['git', 'rev-parse', 'HEAD'], 
                              capture_output=True, text=True)
        return result.stdout.strip() if result.returncode == 0 else None
    except:
        return None

# Example usage
experiment_metadata = track_experiment(
    experiment_name=f"fraud_model_v1_{datetime.now().strftime('%Y%m%d')}",
    config=model_config,
    metrics=validation_results,
    artifacts={'model_path': model_output_path}
)
```

## Troubleshooting

### Common Issues and Solutions

1. **RAPIDS Import Errors**
   ```python
   # Check CUDA availability
   try:
       import cudf
       print("RAPIDS available")
   except ImportError as e:
       print(f"RAPIDS not available: {e}")
       print("Using CPU-based alternatives")
   ```

2. **Memory Issues**
   ```python
   # Monitor memory usage
   import psutil
   
   def check_memory():
       memory = psutil.virtual_memory()
       print(f"Memory usage: {memory.percent}%")
       print(f"Available: {memory.available / 1024**3:.2f} GB")
   
   check_memory()
   ```

3. **S3 Access Issues**
   ```python
   # Test S3 connectivity
   def test_s3_access(bucket_name):
       try:
           s3_client = boto3.client('s3')
           response = s3_client.list_objects_v2(Bucket=bucket_name, MaxKeys=1)
           print("S3 access successful")
           return True
       except Exception as e:
           print(f"S3 access failed: {e}")
           return False
   
   test_s3_access(DATA_BUCKET)
   ```

4. **Kubernetes Connectivity Issues**
   ```python
   # Test Kubernetes connectivity
   def test_k8s_connectivity():
       try:
           v1 = client.CoreV1Api()
           namespaces = v1.list_namespace()
           print(f"Connected to Kubernetes. Found {len(namespaces.items)} namespaces")
           return True
       except Exception as e:
           print(f"Kubernetes connectivity failed: {e}")
           return False
   
   test_k8s_connectivity()
   ```

### Getting Help

- **Documentation**: Check the [troubleshooting runbook](../runbooks/troubleshooting-runbook.md)
- **Support Channels**: 
  - Slack: #ml-platform-support
  - Email: ml-platform@company.com
- **Office Hours**: Tuesdays and Thursdays, 2-4 PM PST

### Useful Commands

```bash
# Check JupyterHub pod status
kubectl get pods -n jupyterhub

# Check Ray cluster status
kubectl get raycluster -n ml-team-a

# Check inference service status
kubectl get deployment fraud-inference -n ml-team-a

# View logs
kubectl logs -f deployment/fraud-inference -n ml-team-a

# Port forward for local testing
kubectl port-forward -n ml-team-a svc/fraud-inference 8080:80
```