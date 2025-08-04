#!/usr/bin/env python3
"""
SageMaker to EKS Model Migration Script

This script migrates XGBoost models and training jobs from SageMaker to EKS-based
Ray training and inference services.
"""

import json
import boto3
import yaml
import argparse
import logging
import tarfile
import pickle
import joblib
import os
import shutil
from datetime import datetime
from typing import Dict, List, Optional, Any
import subprocess

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class SageMakerToEKSMigrator:
    """Handles migration from SageMaker to EKS-based ML services"""
    
    def __init__(self, region: str = 'us-west-2'):
        self.region = region
        self.sagemaker_client = boto3.client('sagemaker', region_name=region)
        self.s3_client = boto3.client('s3', region_name=region)
        self.sts_client = boto3.client('sts', region_name=region)
        
    def extract_training_job_config(self, training_job_name: str) -> Dict:
        """Extract configuration from SageMaker training job"""
        
        try:
            response = self.sagemaker_client.describe_training_job(
                TrainingJobName=training_job_name
            )
            
            config = {
                'job_name': response['TrainingJobName'],
                'algorithm_specification': response['AlgorithmSpecification'],
                'role_arn': response['RoleArn'],
                'input_data_config': response['InputDataConfig'],
                'output_data_config': response['OutputDataConfig'],
                'resource_config': response['ResourceConfig'],
                'stopping_condition': response['StoppingCondition'],
                'hyperparameters': response.get('HyperParameters', {}),
                'environment': response.get('Environment', {}),
                'tags': response.get('Tags', [])
            }
            
            return config
            
        except Exception as e:
            logger.error(f"Failed to extract training job config: {e}")
            raise
    
    def convert_to_ray_training_config(self, sagemaker_config: Dict) -> Dict:
        """Convert SageMaker training configuration to Ray training format"""
        
        # Extract hyperparameters
        hyperparams = sagemaker_config['hyperparameters']
        
        # Map SageMaker instance types to Ray worker configuration
        instance_type = sagemaker_config['resource_config']['InstanceType']
        instance_count = sagemaker_config['resource_config']['InstanceCount']
        
        # Determine if GPU training is needed
        gpu_instances = ['ml.p3', 'ml.p4', 'ml.g4dn', 'ml.g5']
        use_gpu = any(gpu_type in instance_type for gpu_type in gpu_instances)
        
        ray_config = {
            'apiVersion': 'ray.io/v1alpha1',
            'kind': 'RayJob',
            'metadata': {
                'name': f"fraud-training-{datetime.now().strftime('%Y%m%d-%H%M%S')}",
                'namespace': 'ml-team-a'
            },
            'spec': {
                'entrypoint': 'python /app/train_xgboost_ray.py',
                'runtimeEnv': json.dumps({
                    'pip': [
                        'xgboost==1.7.3',
                        'ray[train]==2.8.0',
                        'pandas==1.5.3',
                        'numpy==1.24.3',
                        's3fs==2023.6.0',
                        'boto3==1.26.137'
                    ]
                }),
                'rayClusterSpec': {
                    'rayVersion': '2.8.0',
                    'headGroupSpec': {
                        'replicas': 1,
                        'rayStartParams': {
                            'dashboard-host': '0.0.0.0'
                        },
                        'template': {
                            'spec': {
                                'containers': [{
                                    'name': 'ray-head',
                                    'image': 'rayproject/ray-ml:2.8.0-gpu' if use_gpu else 'rayproject/ray-ml:2.8.0',
                                    'resources': {
                                        'requests': {
                                            'cpu': '2',
                                            'memory': '8Gi'
                                        },
                                        'limits': {
                                            'cpu': '4',
                                            'memory': '16Gi'
                                        }
                                    },
                                    'env': [
                                        {'name': 'AWS_DEFAULT_REGION', 'value': self.region},
                                        {'name': 'TRAINING_JOB_NAME', 'value': sagemaker_config['job_name']}
                                    ]
                                }]
                            }
                        }
                    },
                    'workerGroupSpecs': [{
                        'replicas': instance_count,
                        'minReplicas': 1,
                        'maxReplicas': instance_count * 2,
                        'groupName': 'gpu-workers' if use_gpu else 'cpu-workers',
                        'rayStartParams': {},
                        'template': {
                            'spec': {
                                'containers': [{
                                    'name': 'ray-worker',
                                    'image': 'rayproject/ray-ml:2.8.0-gpu' if use_gpu else 'rayproject/ray-ml:2.8.0',
                                    'resources': {
                                        'requests': {
                                            'cpu': '4',
                                            'memory': '16Gi'
                                        },
                                        'limits': {
                                            'cpu': '8',
                                            'memory': '32Gi'
                                        }
                                    }
                                }]
                            }
                        }
                    }]
                },
                'submitterPodTemplate': {
                    'spec': {
                        'containers': [{
                            'name': 'ray-job-submitter',
                            'image': 'rayproject/ray-ml:2.8.0-gpu' if use_gpu else 'rayproject/ray-ml:2.8.0',
                            'env': [
                                {'name': 'AWS_DEFAULT_REGION', 'value': self.region}
                            ]
                        }]
                    }
                }
            }
        }
        
        # Add GPU resources if needed
        if use_gpu:
            for worker_spec in ray_config['spec']['rayClusterSpec']['workerGroupSpecs']:
                worker_spec['template']['spec']['containers'][0]['resources']['requests']['nvidia.com/gpu'] = '1'
                worker_spec['template']['spec']['containers'][0]['resources']['limits']['nvidia.com/gpu'] = '1'
        
        return ray_config
    
    def create_ray_training_script(self, sagemaker_config: Dict, output_path: str):
        """Create Ray training script from SageMaker configuration"""
        
        hyperparams = sagemaker_config['hyperparameters']
        
        script_content = f'''#!/usr/bin/env python3
"""
Ray XGBoost Training Script
Migrated from SageMaker training job: {sagemaker_config['job_name']}
"""

import os
import json
import pandas as pd
import numpy as np
import xgboost as xgb
import ray
from ray import train
from ray.train import ScalingConfig
from ray.train.xgboost import XGBoostTrainer
import boto3
import s3fs
from datetime import datetime

def load_data_from_s3(input_config):
    """Load training data from S3"""
    
    s3_fs = s3fs.S3FileSystem()
    
    # Extract S3 paths from input configuration
    train_data_path = None
    validation_data_path = None
    
    for input_data in input_config:
        channel_name = input_data['ChannelName']
        s3_uri = input_data['DataSource']['S3DataSource']['S3Uri']
        
        if channel_name == 'training':
            train_data_path = s3_uri
        elif channel_name == 'validation':
            validation_data_path = s3_uri
    
    # Load training data
    if train_data_path:
        train_df = pd.read_parquet(train_data_path.replace('s3://', ''), filesystem=s3_fs)
    else:
        raise ValueError("Training data path not found")
    
    # Load validation data if available
    validation_df = None
    if validation_data_path:
        validation_df = pd.read_parquet(validation_data_path.replace('s3://', ''), filesystem=s3_fs)
    
    return train_df, validation_df

def prepare_datasets(train_df, validation_df=None):
    """Prepare datasets for XGBoost training"""
    
    # Assume target column is 'TX_FRAUD_1'
    target_column = 'TX_FRAUD_1'
    
    # Separate features and target
    X_train = train_df.drop(columns=[target_column])
    y_train = train_df[target_column]
    
    train_dataset = ray.data.from_pandas(pd.concat([X_train, y_train], axis=1))
    
    validation_dataset = None
    if validation_df is not None:
        X_val = validation_df.drop(columns=[target_column])
        y_val = validation_df[target_column]
        validation_dataset = ray.data.from_pandas(pd.concat([X_val, y_val], axis=1))
    
    return train_dataset, validation_dataset

def train_model():
    """Train XGBoost model using Ray"""
    
    # Initialize Ray
    ray.init(ignore_reinit_error=True)
    
    # Load hyperparameters from SageMaker configuration
    hyperparams = {hyperparams}
    
    # Load input data configuration
    input_config = {sagemaker_config['input_data_config']}
    
    # Load and prepare data
    train_df, validation_df = load_data_from_s3(input_config)
    train_dataset, validation_dataset = prepare_datasets(train_df, validation_df)
    
    # Configure XGBoost parameters
    xgb_params = {{
        'objective': hyperparams.get('objective', 'binary:logistic'),
        'eval_metric': hyperparams.get('eval_metric', 'auc'),
        'max_depth': int(hyperparams.get('max_depth', 6)),
        'learning_rate': float(hyperparams.get('eta', 0.3)),
        'subsample': float(hyperparams.get('subsample', 1.0)),
        'colsample_bytree': float(hyperparams.get('colsample_bytree', 1.0)),
        'min_child_weight': int(hyperparams.get('min_child_weight', 1)),
        'tree_method': 'gpu_hist' if os.getenv('CUDA_VISIBLE_DEVICES') else 'hist',
        'random_state': 42
    }}
    
    # Configure scaling
    scaling_config = ScalingConfig(
        num_workers=int(hyperparams.get('num_workers', 4)),
        use_gpu=bool(os.getenv('CUDA_VISIBLE_DEVICES'))
    )
    
    # Create trainer
    trainer = XGBoostTrainer(
        scaling_config=scaling_config,
        label_column='TX_FRAUD_1',
        params=xgb_params,
        datasets={{"train": train_dataset, "valid": validation_dataset}} if validation_dataset else {{"train": train_dataset}},
        num_boost_round=int(hyperparams.get('num_round', 100))
    )
    
    # Train model
    result = trainer.fit()
    
    # Save model to S3
    output_config = {sagemaker_config['output_data_config']}
    model_s3_path = output_config['S3OutputPath']
    
    # Get trained model
    checkpoint = result.checkpoint
    model_path = os.path.join(checkpoint.path, "model.xgb")
    
    # Upload to S3
    s3_client = boto3.client('s3')
    bucket, key = model_s3_path.replace('s3://', '').split('/', 1)
    model_key = f"{{key}}/model.xgb"
    
    s3_client.upload_file(model_path, bucket, model_key)
    
    # Save training metadata
    metadata = {{
        'training_job_name': os.getenv('TRAINING_JOB_NAME'),
        'model_s3_path': f"s3://{{bucket}}/{{model_key}}",
        'hyperparameters': hyperparams,
        'training_metrics': result.metrics,
        'timestamp': datetime.now().isoformat()
    }}
    
    metadata_key = f"{{key}}/training_metadata.json"
    s3_client.put_object(
        Bucket=bucket,
        Key=metadata_key,
        Body=json.dumps(metadata, indent=2)
    )
    
    print(f"Model saved to: s3://{{bucket}}/{{model_key}}")
    print(f"Metadata saved to: s3://{{bucket}}/{{metadata_key}}")
    
    return result

if __name__ == '__main__':
    result = train_model()
    print("Training completed successfully!")
'''
        
        with open(output_path, 'w') as f:
            f.write(script_content)
        
        logger.info(f"Ray training script created: {output_path}")
    
    def extract_model_artifacts(self, model_name: str, local_dir: str) -> Dict:
        """Extract model artifacts from SageMaker model"""
        
        try:
            # Get model information
            response = self.sagemaker_client.describe_model(ModelName=model_name)
            
            model_data_url = response['PrimaryContainer']['ModelDataUrl']
            
            # Download model artifacts
            bucket, key = model_data_url.replace('s3://', '').split('/', 1)
            local_tar_path = os.path.join(local_dir, 'model.tar.gz')
            
            self.s3_client.download_file(bucket, key, local_tar_path)
            
            # Extract tar file
            extract_dir = os.path.join(local_dir, 'extracted')
            os.makedirs(extract_dir, exist_ok=True)
            
            with tarfile.open(local_tar_path, 'r:gz') as tar:
                tar.extractall(extract_dir)
            
            # Find model files
            model_files = []
            for root, dirs, files in os.walk(extract_dir):
                for file in files:
                    if file.endswith(('.pkl', '.joblib', '.json', '.xgb')):
                        model_files.append(os.path.join(root, file))
            
            model_info = {
                'model_name': model_name,
                'model_data_url': model_data_url,
                'local_extract_dir': extract_dir,
                'model_files': model_files,
                'container_image': response['PrimaryContainer']['Image']
            }
            
            return model_info
            
        except Exception as e:
            logger.error(f"Failed to extract model artifacts: {e}")
            raise
    
    def create_inference_service_config(self, model_info: Dict) -> Dict:
        """Create Kubernetes deployment configuration for inference service"""
        
        config = {
            'apiVersion': 'apps/v1',
            'kind': 'Deployment',
            'metadata': {
                'name': 'fraud-inference',
                'namespace': 'ml-team-a',
                'labels': {
                    'app': 'fraud-inference',
                    'version': 'v1'
                }
            },
            'spec': {
                'replicas': 3,
                'selector': {
                    'matchLabels': {
                        'app': 'fraud-inference'
                    }
                },
                'template': {
                    'metadata': {
                        'labels': {
                            'app': 'fraud-inference'
                        }
                    },
                    'spec': {
                        'containers': [{
                            'name': 'inference',
                            'image': 'fraud-detection/inference:latest',
                            'ports': [{
                                'containerPort': 8000,
                                'name': 'http'
                            }],
                            'env': [
                                {
                                    'name': 'MODEL_S3_PATH',
                                    'value': model_info['model_data_url']
                                },
                                {
                                    'name': 'AWS_DEFAULT_REGION',
                                    'value': self.region
                                }
                            ],
                            'resources': {
                                'requests': {
                                    'cpu': '500m',
                                    'memory': '1Gi'
                                },
                                'limits': {
                                    'cpu': '2',
                                    'memory': '4Gi'
                                }
                            },
                            'livenessProbe': {
                                'httpGet': {
                                    'path': '/health',
                                    'port': 8000
                                },
                                'initialDelaySeconds': 30,
                                'periodSeconds': 10
                            },
                            'readinessProbe': {
                                'httpGet': {
                                    'path': '/ready',
                                    'port': 8000
                                },
                                'initialDelaySeconds': 5,
                                'periodSeconds': 5
                            }
                        }],
                        'serviceAccountName': 'fraud-inference-sa'
                    }
                }
            }
        }
        
        return config
    
    def create_inference_service(self, model_info: Dict, output_dir: str):
        """Create FastAPI inference service code"""
        
        service_code = '''#!/usr/bin/env python3
"""
FastAPI Inference Service
Migrated from SageMaker endpoint
"""

import os
import json
import pickle
import joblib
import xgboost as xgb
import pandas as pd
import numpy as np
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import List, Dict, Any
import boto3
import logging
from datetime import datetime

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="Fraud Detection Inference Service", version="1.0.0")

# Global model variable
model = None
feature_names = None

class PredictionRequest(BaseModel):
    features: Dict[str, Any]

class PredictionResponse(BaseModel):
    prediction: float
    probability: float
    timestamp: str

def load_model():
    """Load model from S3"""
    global model, feature_names
    
    try:
        model_s3_path = os.getenv('MODEL_S3_PATH')
        if not model_s3_path:
            raise ValueError("MODEL_S3_PATH environment variable not set")
        
        # Download model from S3
        s3_client = boto3.client('s3')
        bucket, key = model_s3_path.replace('s3://', '').split('/', 1)
        
        local_model_path = '/tmp/model.xgb'
        s3_client.download_file(bucket, key, local_model_path)
        
        # Load XGBoost model
        model = xgb.Booster()
        model.load_model(local_model_path)
        
        # Try to load feature names
        try:
            metadata_key = key.replace('model.xgb', 'training_metadata.json')
            metadata_obj = s3_client.get_object(Bucket=bucket, Key=metadata_key)
            metadata = json.loads(metadata_obj['Body'].read())
            feature_names = metadata.get('feature_names', [])
        except:
            logger.warning("Could not load feature names from metadata")
            feature_names = []
        
        logger.info("Model loaded successfully")
        
    except Exception as e:
        logger.error(f"Failed to load model: {e}")
        raise

@app.on_event("startup")
async def startup_event():
    """Load model on startup"""
    load_model()

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy", "timestamp": datetime.now().isoformat()}

@app.get("/ready")
async def readiness_check():
    """Readiness check endpoint"""
    if model is None:
        raise HTTPException(status_code=503, detail="Model not loaded")
    return {"status": "ready", "timestamp": datetime.now().isoformat()}

@app.post("/predict", response_model=PredictionResponse)
async def predict(request: PredictionRequest):
    """Make fraud prediction"""
    
    if model is None:
        raise HTTPException(status_code=503, detail="Model not loaded")
    
    try:
        # Convert features to DataFrame
        features_df = pd.DataFrame([request.features])
        
        # Ensure feature order matches training
        if feature_names:
            features_df = features_df.reindex(columns=feature_names, fill_value=0)
        
        # Convert to DMatrix
        dmatrix = xgb.DMatrix(features_df)
        
        # Make prediction
        prediction_prob = model.predict(dmatrix)[0]
        prediction = 1 if prediction_prob > 0.5 else 0
        
        return PredictionResponse(
            prediction=float(prediction),
            probability=float(prediction_prob),
            timestamp=datetime.now().isoformat()
        )
        
    except Exception as e:
        logger.error(f"Prediction failed: {e}")
        raise HTTPException(status_code=500, detail=f"Prediction failed: {str(e)}")

@app.get("/model/info")
async def model_info():
    """Get model information"""
    if model is None:
        raise HTTPException(status_code=503, detail="Model not loaded")
    
    return {
        "model_type": "XGBoost",
        "feature_count": len(feature_names) if feature_names else "unknown",
        "feature_names": feature_names[:10] if feature_names else [],  # First 10 features
        "loaded_at": datetime.now().isoformat()
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
'''
        
        # Create service directory
        service_dir = os.path.join(output_dir, 'inference-service')
        os.makedirs(service_dir, exist_ok=True)
        
        # Write service code
        with open(os.path.join(service_dir, 'main.py'), 'w') as f:
            f.write(service_code)
        
        # Create requirements.txt
        requirements = '''fastapi==0.104.1
uvicorn==0.24.0
pandas==1.5.3
numpy==1.24.3
xgboost==1.7.3
boto3==1.26.137
pydantic==2.5.0
'''
        
        with open(os.path.join(service_dir, 'requirements.txt'), 'w') as f:
            f.write(requirements)
        
        # Create Dockerfile
        dockerfile = '''FROM python:3.9-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py .

EXPOSE 8000

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
'''
        
        with open(os.path.join(service_dir, 'Dockerfile'), 'w') as f:
            f.write(dockerfile)
        
        logger.info(f"Inference service created in: {service_dir}")
    
    def create_migration_manifest(self, training_job_name: str, model_name: str, output_file: str):
        """Create comprehensive migration manifest"""
        
        try:
            # Extract configurations
            training_config = self.extract_training_job_config(training_job_name)
            ray_config = self.convert_to_ray_training_config(training_config)
            
            # Create temporary directory for model extraction
            temp_dir = '/tmp/model_migration'
            os.makedirs(temp_dir, exist_ok=True)
            
            try:
                model_info = self.extract_model_artifacts(model_name, temp_dir)
                inference_config = self.create_inference_service_config(model_info)
            except Exception as e:
                logger.warning(f"Could not extract model artifacts: {e}")
                model_info = {'model_name': model_name}
                inference_config = {}
            finally:
                # Clean up temporary directory
                if os.path.exists(temp_dir):
                    shutil.rmtree(temp_dir)
            
            manifest = {
                'migration_info': {
                    'timestamp': datetime.now().isoformat(),
                    'source_training_job': training_job_name,
                    'source_model': model_name,
                    'migrated_by': os.getenv('USER', 'unknown')
                },
                'sagemaker_training_config': training_config,
                'ray_training_config': ray_config,
                'model_info': model_info,
                'inference_service_config': inference_config,
                'migration_steps': [
                    'Extract SageMaker training job configuration',
                    'Convert to Ray training configuration',
                    'Extract model artifacts',
                    'Create inference service configuration',
                    'Generate deployment manifests',
                    'Validate migration'
                ]
            }
            
            with open(output_file, 'w') as f:
                json.dump(manifest, f, indent=2, default=str)
            
            logger.info(f"Migration manifest created: {output_file}")
            
        except Exception as e:
            logger.error(f"Failed to create migration manifest: {e}")
            raise

def main():
    parser = argparse.ArgumentParser(description='Migrate SageMaker models to EKS')
    parser.add_argument('--training-job-name', required=True, help='SageMaker training job name')
    parser.add_argument('--model-name', required=True, help='SageMaker model name')
    parser.add_argument('--output-dir', default='./migration-output', help='Output directory for migration artifacts')
    parser.add_argument('--region', default='us-west-2', help='AWS region')
    
    args = parser.parse_args()
    
    # Create output directory
    os.makedirs(args.output_dir, exist_ok=True)
    
    migrator = SageMakerToEKSMigrator(region=args.region)
    
    try:
        # Create migration manifest
        manifest_file = os.path.join(args.output_dir, 'sagemaker-migration-manifest.json')
        migrator.create_migration_manifest(args.training_job_name, args.model_name, manifest_file)
        
        # Create Ray training script
        training_config = migrator.extract_training_job_config(args.training_job_name)
        script_path = os.path.join(args.output_dir, 'train_xgboost_ray.py')
        migrator.create_ray_training_script(training_config, script_path)
        
        # Create inference service
        temp_dir = '/tmp/model_migration'
        os.makedirs(temp_dir, exist_ok=True)
        
        try:
            model_info = migrator.extract_model_artifacts(args.model_name, temp_dir)
            migrator.create_inference_service(model_info, args.output_dir)
        except Exception as e:
            logger.warning(f"Could not create inference service: {e}")
        finally:
            if os.path.exists(temp_dir):
                shutil.rmtree(temp_dir)
        
        # Create Ray training job YAML
        ray_config = migrator.convert_to_ray_training_config(training_config)
        ray_yaml_path = os.path.join(args.output_dir, 'ray-training-job.yaml')
        with open(ray_yaml_path, 'w') as f:
            yaml.dump(ray_config, f, default_flow_style=False)
        
        # Create inference deployment YAML
        try:
            model_info = migrator.extract_model_artifacts(args.model_name, temp_dir)
            inference_config = migrator.create_inference_service_config(model_info)
            inference_yaml_path = os.path.join(args.output_dir, 'inference-deployment.yaml')
            with open(inference_yaml_path, 'w') as f:
                yaml.dump(inference_config, f, default_flow_style=False)
        except:
            pass
        
        logger.info(f"Migration completed successfully. Output directory: {args.output_dir}")
        
    except Exception as e:
        logger.error(f"Migration failed: {e}")
        exit(1)

if __name__ == '__main__':
    main()