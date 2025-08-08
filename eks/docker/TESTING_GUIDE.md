# EMR on EKS Testing Guide

This guide walks you through testing the EMR on EKS fraud detection utilities step by step.

## Prerequisites

### 1. Infrastructure Setup

First, ensure you have the EMR on EKS infrastructure deployed:

```bash
# Check if EKS cluster exists
kubectl cluster-info

# Check if EMR virtual cluster is created
aws emr-containers list-virtual-clusters

# Verify namespace exists
kubectl get namespace emr-fraud-detection
```

### 2. Environment Variables

Set these environment variables in your JupyterHub environment:

```bash
export VIRTUAL_CLUSTER_ID="your-emr-virtual-cluster-id"
export EMR_EXECUTION_ROLE_ARN="arn:aws:iam::123456789012:role/EMRContainers-JobExecutionRole"
export AWS_DEFAULT_REGION="us-west-2"
export S3_BUCKET="your-fraud-detection-bucket"
export KUBERNETES_NAMESPACE="emr-fraud-detection"
```

### 3. Verify AWS Permissions

Test AWS access:

```bash
# Test EMR containers access
aws emr-containers list-virtual-clusters

# Test S3 access
aws s3 ls s3://nvidia-aws-fraud-detection-demo-training-data/

# Test your S3 bucket
aws s3 ls s3://$S3_BUCKET/
```

## Testing Approach

We'll test in this order:
1. **Unit Testing** - Test utilities without submitting jobs
2. **Integration Testing** - Test with small EMR jobs
3. **End-to-End Testing** - Full fraud detection pipeline
4. **Performance Testing** - Large-scale jobs

## 1. Unit Testing

### Test 1: Verify Utilities Load

Create a test notebook or run in JupyterHub:

```python
# Test basic imports
import sys
sys.path.append('/home/jovyan/src')

try:
    from emr_eks_utils import (
        create_job_manager,
        EMROnEKSJobManager,
        quick_submit_feature_engineering
    )
    print("✅ All imports successful")
except ImportError as e:
    print(f"❌ Import failed: {e}")
```

### Test 2: Environment Configuration

```python
import os

# Check required environment variables
required_vars = [
    'VIRTUAL_CLUSTER_ID',
    'EMR_EXECUTION_ROLE_ARN', 
    'AWS_DEFAULT_REGION',
    'S3_BUCKET'
]

print("Environment Check:")
for var in required_vars:
    value = os.environ.get(var)
    status = "✅" if value else "❌"
    print(f"{status} {var}: {value or 'NOT SET'}")
```

### Test 3: Job Manager Creation

```python
try:
    job_manager = create_job_manager()
    print("✅ Job manager created successfully")
    print(f"Virtual Cluster: {job_manager.virtual_cluster_id}")
    print(f"Region: {job_manager.region}")
    print(f"S3 Bucket: {job_manager.s3_bucket}")
except Exception as e:
    print(f"❌ Job manager creation failed: {e}")
```

### Test 4: AWS Connectivity

```python
try:
    job_manager = create_job_manager()
    
    # Test listing jobs (should work even if no jobs exist)
    jobs = job_manager.list_jobs(max_results=5)
    print(f"✅ AWS connectivity working - Found {len(jobs)} recent jobs")
    
    for job in jobs[:3]:  # Show first 3 jobs
        print(f"  - {job['name']} ({job['state']})")
        
except Exception as e:
    print(f"❌ AWS connectivity failed: {e}")
```

## 2. Integration Testing

### Test 5: Submit a Simple Test Job

First, let's create a minimal test script:

```python
# Create a simple test script
test_script_content = '''
from pyspark.sql import SparkSession
import sys

spark = SparkSession.builder.appName("EMR-Test").getOrCreate()
print("✅ Spark session created successfully")
print(f"Spark version: {spark.version}")

# Create a simple DataFrame
data = [(1, "test"), (2, "data")]
df = spark.createDataFrame(data, ["id", "value"])
print(f"✅ DataFrame created with {df.count()} rows")

spark.stop()
print("✅ Test completed successfully")
'''

# Save test script to local file
with open('/home/jovyan/src/test_job.py', 'w') as f:
    f.write(test_script_content)

print("✅ Test script created")
```

### Test 6: Upload Test Script to S3

```python
import boto3

s3_client = boto3.client('s3')
bucket = os.environ.get('S3_BUCKET')

try:
    # Upload test script
    s3_client.upload_file(
        '/home/jovyan/src/test_job.py',
        bucket,
        'fraud-detection-scripts/test_job.py'
    )
    print("✅ Test script uploaded to S3")
    
    # Verify upload
    script_path = f"s3://{bucket}/fraud-detection-scripts/test_job.py"
    print(f"Script location: {script_path}")
    
except Exception as e:
    print(f"❌ Script upload failed: {e}")
```

### Test 7: Submit Test Job

```python
try:
    job_manager = create_job_manager()
    
    # Submit a simple test job
    script_path = f"s3://{bucket}/fraud-detection-scripts/test_job.py"
    
    job_id = job_manager.submit_job(
        job_type='feature_engineering',  # Use existing template
        entry_point=script_path,
        job_name='emr-connectivity-test',
        custom_configs={
            'spark.executor.instances': '1',  # Minimal resources
            'spark.executor.memory': '2G'
        }
    )
    
    print(f"✅ Test job submitted: {job_id}")
    
    # Store job ID for monitoring
    test_job_id = job_id
    
except Exception as e:
    print(f"❌ Job submission failed: {e}")
```

### Test 8: Monitor Test Job

```python
if 'test_job_id' in locals():
    try:
        from emr_eks_utils import print_job_status
        
        print("Monitoring test job...")
        print_job_status(test_job_id)
        
        # Wait a bit and check again
        import time
        time.sleep(30)
        
        print("\nStatus after 30 seconds:")
        print_job_status(test_job_id)
        
    except Exception as e:
        print(f"❌ Job monitoring failed: {e}")
else:
    print("❌ No test job ID available")
```

## 3. Feature Engineering Testing

### Test 9: Test Feature Engineering Notebook

Open the notebook: `eks/docker/notebooks/01_fraud_detection_feature_engineering_emr_eks.ipynb`

Run the first few cells to test:
1. Environment setup
2. Spark session creation
3. Data loading (with a small sample)

### Test 10: Submit Feature Engineering Job

```python
try:
    job_manager = create_job_manager()
    
    # Submit with reduced resources for testing
    custom_configs = {
        'spark.executor.instances': '2',  # Reduced from 12
        'spark.executor.memory': '8G',   # Reduced from 30G
        'spark.sql.shuffle.partitions': '200'  # Reduced from 20000
    }
    
    output_path = f"s3://{bucket}/fraud-data/test-features-{int(time.time())}/"
    
    fe_job_id = job_manager.submit_feature_engineering_job(
        output_path=output_path,
        custom_configs=custom_configs
    )
    
    print(f"✅ Feature engineering job submitted: {fe_job_id}")
    print(f"Output path: {output_path}")
    
except Exception as e:
    print(f"❌ Feature engineering job failed: {e}")
```

### Test 11: Monitor Feature Engineering Job

```python
if 'fe_job_id' in locals():
    print("Monitoring feature engineering job...")
    
    # Check status every 2 minutes for 10 minutes
    for i in range(5):
        print(f"\n--- Check {i+1}/5 ---")
        print_job_status(fe_job_id)
        
        status = job_manager.get_job_status(fe_job_id)
        if status['state'] in ['COMPLETED', 'FAILED', 'CANCELLED']:
            break
            
        time.sleep(120)  # Wait 2 minutes
    
    print("\nFinal status:")
    print_job_status(fe_job_id)
```

## 4. End-to-End Testing

### Test 12: Full Pipeline Test

```python
def run_full_pipeline_test():
    """Run a complete fraud detection pipeline test"""
    
    job_manager = create_job_manager()
    timestamp = int(time.time())
    
    # Paths for this test run
    features_path = f"s3://{bucket}/fraud-data/test-features-{timestamp}/"
    model_path = f"s3://{bucket}/fraud-models/test-model-{timestamp}/"
    predictions_path = f"s3://{bucket}/fraud-predictions/test-predictions-{timestamp}/"
    
    print("🚀 Starting full pipeline test...")
    print(f"Features: {features_path}")
    print(f"Model: {model_path}")
    print(f"Predictions: {predictions_path}")
    
    try:
        # Step 1: Feature Engineering
        print("\n📊 Step 1: Feature Engineering")
        fe_job_id = job_manager.submit_feature_engineering_job(
            output_path=features_path,
            custom_configs={'spark.executor.instances': '2'}
        )
        print(f"Job ID: {fe_job_id}")
        
        # Wait for completion
        fe_status = job_manager.wait_for_job_completion(fe_job_id, max_wait_time=1800)
        
        if fe_status['state'] != 'COMPLETED':
            print(f"❌ Feature engineering failed: {fe_status['state']}")
            return
        
        print("✅ Feature engineering completed")
        
        # Step 2: Training
        print("\n🤖 Step 2: Model Training")
        train_job_id = job_manager.submit_training_job(
            features_path=features_path,
            model_output_path=model_path,
            custom_configs={'spark.executor.instances': '2'}
        )
        print(f"Job ID: {train_job_id}")
        
        # Wait for completion
        train_status = job_manager.wait_for_job_completion(train_job_id, max_wait_time=1800)
        
        if train_status['state'] != 'COMPLETED':
            print(f"❌ Training failed: {train_status['state']}")
            return
            
        print("✅ Training completed")
        
        # Step 3: Inference
        print("\n🔮 Step 3: Batch Inference")
        infer_job_id = job_manager.submit_inference_job(
            model_path=model_path,
            input_data_path="s3://nvidia-aws-fraud-detection-demo-training-data/transactions_parquet/",
            predictions_output_path=predictions_path,
            custom_configs={'spark.executor.instances': '1'}
        )
        print(f"Job ID: {infer_job_id}")
        
        # Wait for completion
        infer_status = job_manager.wait_for_job_completion(infer_job_id, max_wait_time=1800)
        
        if infer_status['state'] != 'COMPLETED':
            print(f"❌ Inference failed: {infer_status['state']}")
            return
            
        print("✅ Inference completed")
        
        print("\n🎉 Full pipeline test completed successfully!")
        print(f"Check results in: {predictions_path}")
        
        return {
            'features_path': features_path,
            'model_path': model_path,
            'predictions_path': predictions_path,
            'job_ids': {
                'feature_engineering': fe_job_id,
                'training': train_job_id,
                'inference': infer_job_id
            }
        }
        
    except Exception as e:
        print(f"❌ Pipeline test failed: {e}")
        return None

# Run the test (this will take 30-60 minutes)
# pipeline_results = run_full_pipeline_test()
```

## 5. Performance Testing

### Test 13: Resource Scaling Test

```python
def test_resource_scaling():
    """Test different resource configurations"""
    
    job_manager = create_job_manager()
    
    # Test configurations
    configs = [
        {'name': 'small', 'executors': '2', 'memory': '4G'},
        {'name': 'medium', 'executors': '4', 'memory': '8G'},
        {'name': 'large', 'executors': '8', 'memory': '16G'}
    ]
    
    for config in configs:
        print(f"\n🧪 Testing {config['name']} configuration...")
        
        custom_configs = {
            'spark.executor.instances': config['executors'],
            'spark.executor.memory': config['memory']
        }
        
        try:
            job_id = job_manager.submit_feature_engineering_job(
                output_path=f"s3://{bucket}/fraud-data/scale-test-{config['name']}/",
                custom_configs=custom_configs
            )
            
            print(f"✅ {config['name']} job submitted: {job_id}")
            
        except Exception as e:
            print(f"❌ {config['name']} job failed: {e}")

# Run scaling test
# test_resource_scaling()
```

## 6. Troubleshooting Tests

### Test 14: Common Error Scenarios

```python
def test_error_scenarios():
    """Test common error scenarios and error handling"""
    
    job_manager = create_job_manager()
    
    print("🔍 Testing error scenarios...")
    
    # Test 1: Invalid S3 path
    try:
        job_id = job_manager.submit_feature_engineering_job(
            output_path="s3://non-existent-bucket-12345/test/"
        )
        print("❌ Should have failed with invalid S3 path")
    except Exception as e:
        print(f"✅ Correctly caught S3 error: {type(e).__name__}")
    
    # Test 2: Invalid job type
    try:
        job_id = job_manager.submit_job(
            job_type='invalid_job_type',
            entry_point='s3://bucket/script.py'
        )
        print("❌ Should have failed with invalid job type")
    except Exception as e:
        print(f"✅ Correctly caught job type error: {type(e).__name__}")
    
    # Test 3: Get status of non-existent job
    try:
        status = job_manager.get_job_status('non-existent-job-id')
        print("❌ Should have failed with invalid job ID")
    except Exception as e:
        print(f"✅ Correctly caught job status error: {type(e).__name__}")

# Run error tests
test_error_scenarios()
```

## 7. Validation and Cleanup

### Test 15: Validate Results

```python
def validate_results(results_path):
    """Validate job results in S3"""
    
    print(f"🔍 Validating results in: {results_path}")
    
    try:
        # List files in results path
        import boto3
        s3_client = boto3.client('s3')
        
        bucket_name = results_path.replace('s3://', '').split('/')[0]
        prefix = '/'.join(results_path.replace('s3://', '').split('/')[1:])
        
        response = s3_client.list_objects_v2(
            Bucket=bucket_name,
            Prefix=prefix
        )
        
        if 'Contents' in response:
            files = response['Contents']
            total_size = sum(obj['Size'] for obj in files)
            
            print(f"✅ Found {len(files)} files")
            print(f"✅ Total size: {total_size / (1024*1024):.2f} MB")
            
            # Show first few files
            for obj in files[:5]:
                size_mb = obj['Size'] / (1024*1024)
                print(f"  - {obj['Key']} ({size_mb:.2f} MB)")
                
        else:
            print("❌ No files found in results path")
            
    except Exception as e:
        print(f"❌ Validation failed: {e}")

# Example usage:
# if 'pipeline_results' in locals() and pipeline_results:
#     validate_results(pipeline_results['predictions_path'])
```

### Test 16: Cleanup Test Resources

```python
def cleanup_test_resources():
    """Clean up test resources"""
    
    print("🧹 Cleaning up test resources...")
    
    try:
        import boto3
        s3_client = boto3.client('s3')
        bucket = os.environ.get('S3_BUCKET')
        
        # List and delete test objects
        prefixes = [
            'fraud-data/test-features-',
            'fraud-models/test-model-',
            'fraud-predictions/test-predictions-',
            'fraud-data/scale-test-'
        ]
        
        for prefix in prefixes:
            response = s3_client.list_objects_v2(
                Bucket=bucket,
                Prefix=prefix
            )
            
            if 'Contents' in response:
                objects = [{'Key': obj['Key']} for obj in response['Contents']]
                
                if objects:
                    s3_client.delete_objects(
                        Bucket=bucket,
                        Delete={'Objects': objects}
                    )
                    print(f"✅ Deleted {len(objects)} objects with prefix: {prefix}")
        
        print("✅ Cleanup completed")
        
    except Exception as e:
        print(f"❌ Cleanup failed: {e}")

# Run cleanup
# cleanup_test_resources()
```

## Quick Test Checklist

Use this checklist for rapid testing:

### ✅ Pre-flight Checks
- [ ] EKS cluster accessible (`kubectl cluster-info`)
- [ ] EMR virtual cluster exists (`aws emr-containers list-virtual-clusters`)
- [ ] Environment variables set
- [ ] S3 bucket accessible
- [ ] IAM permissions configured

### ✅ Unit Tests
- [ ] Utilities import successfully
- [ ] Job manager creates without errors
- [ ] AWS connectivity works
- [ ] Job templates load correctly

### ✅ Integration Tests
- [ ] Simple test job submits and runs
- [ ] Job monitoring works
- [ ] Feature engineering job completes
- [ ] Results appear in S3

### ✅ End-to-End Tests
- [ ] Full pipeline runs successfully
- [ ] All job types work (feature engineering, training, inference)
- [ ] Results are valid and accessible

## Common Issues and Solutions

### Issue: "Virtual cluster not found"
**Solution:** Check `VIRTUAL_CLUSTER_ID` environment variable and verify cluster exists

### Issue: "Access denied" errors
**Solution:** Verify EMR execution role has proper S3 and EMR permissions

### Issue: Jobs stuck in PENDING
**Solution:** Check EKS node capacity and resource requests

### Issue: "No space left on device"
**Solution:** Increase EBS volume size or use larger instance types

### Issue: RAPIDS/GPU errors
**Solution:** Ensure GPU nodes are available and properly configured

## Next Steps

After successful testing:

1. **Production Deployment**: Scale up resources for production workloads
2. **Monitoring Setup**: Configure CloudWatch alarms and dashboards
3. **Cost Optimization**: Implement spot instances and auto-scaling
4. **CI/CD Integration**: Automate job submission in your deployment pipeline
5. **Custom Templates**: Create job templates for your specific use cases

## Support

If you encounter issues:

1. Check CloudWatch logs: `/aws/emr-containers/{virtual-cluster-id}`
2. Check Kubernetes pod logs: `kubectl logs -n emr-fraud-detection <pod-name>`
3. Verify AWS permissions and resource limits
4. Review the troubleshooting section in the main README

Happy testing! 🚀