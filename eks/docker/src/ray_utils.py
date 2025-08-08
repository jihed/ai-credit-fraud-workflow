"""
Ray utilities for fraud detection notebooks
Provides helper functions for Ray cluster connectivity and distributed training
"""

import os
import ray
import boto3
import pandas as pd
import numpy as np
from typing import Dict, Any, Optional, Tuple
from ray.train.xgboost import XGBoostTrainer
from ray.train import ScalingConfig, RunConfig
from ray.data import Dataset
import xgboost as xgb
from sklearn.metrics import classification_report, confusion_matrix, roc_auc_score
import joblib
import json
from datetime import datetime


class RayClusterClient:
    """Client for interacting with Ray cluster on EKS"""
    
    def __init__(self, ray_address: str = None):
        self.ray_address = ray_address or os.environ.get('RAY_ADDRESS', 'ray://ray-cluster-head:10001')
        self.connected = False
        
    def connect(self):
        """Connect to Ray cluster"""
        if not self.connected:
            try:
                ray.init(address=self.ray_address, ignore_reinit_error=True)
                self.connected = True
                print(f"Connected to Ray cluster at {self.ray_address}")
                print(f"Ray cluster resources: {ray.cluster_resources()}")
            except Exception as e:
                print(f"Failed to connect to Ray cluster: {e}")
                print("Falling back to local Ray instance")
                ray.init(ignore_reinit_error=True)
                self.connected = True
    
    def disconnect(self):
        """Disconnect from Ray cluster"""
        if self.connected:
            ray.shutdown()
            self.connected = False
            print("Disconnected from Ray cluster")
    
    def get_cluster_info(self) -> Dict[str, Any]:
        """Get Ray cluster information"""
        if not self.connected:
            self.connect()
            
        return {
            'nodes': ray.nodes(),
            'resources': ray.cluster_resources(),
            'available_resources': ray.available_resources()
        }


class FraudDetectionTrainer:
    """XGBoost trainer for fraud detection using Ray Train"""
    
    def __init__(self, ray_client: RayClusterClient = None):
        self.ray_client = ray_client or RayClusterClient()
        self.model = None
        self.training_results = None
        
    def prepare_data(self, 
                    features_path: str,
                    target_column: str = 'TX_FRAUD_1',
                    test_size: float = 0.2) -> Tuple[Dataset, Dataset]:
        """
        Prepare training and validation datasets from S3
        
        Args:
            features_path: S3 path to processed features
            target_column: Name of target column
            test_size: Fraction of data for validation
            
        Returns:
            Tuple of (train_dataset, val_dataset)
        """
        
        # Connect to Ray if not already connected
        if not self.ray_client.connected:
            self.ray_client.connect()
        
        # Load data using Ray Data
        print(f"Loading data from {features_path}")
        dataset = ray.data.read_parquet(features_path)
        
        # Split into train and validation
        train_dataset, val_dataset = dataset.train_test_split(test_size=test_size, seed=42)
        
        print(f"Training samples: {train_dataset.count()}")
        print(f"Validation samples: {val_dataset.count()}")
        
        return train_dataset, val_dataset
    
    def train_model(self,
                   train_dataset: Dataset,
                   val_dataset: Dataset,
                   target_column: str = 'TX_FRAUD_1',
                   num_workers: int = 4,
                   use_gpu: bool = True,
                   xgb_params: Dict[str, Any] = None) -> Dict[str, Any]:
        """
        Train XGBoost model using Ray Train
        
        Args:
            train_dataset: Training dataset
            val_dataset: Validation dataset
            target_column: Name of target column
            num_workers: Number of Ray workers
            use_gpu: Whether to use GPU acceleration
            xgb_params: XGBoost parameters
            
        Returns:
            Training results
        """
        
        # Default XGBoost parameters optimized for fraud detection
        default_params = {
            "objective": "binary:logistic",
            "eval_metric": ["logloss", "error", "auc"],
            "tree_method": "gpu_hist" if use_gpu else "hist",
            "max_depth": 6,
            "learning_rate": 0.1,
            "subsample": 0.8,
            "colsample_bytree": 0.8,
            "min_child_weight": 1,
            "gamma": 0,
            "reg_alpha": 0,
            "reg_lambda": 1,
            "scale_pos_weight": 1,  # Will be adjusted based on class imbalance
            "random_state": 42
        }
        
        if xgb_params:
            default_params.update(xgb_params)
        
        # Calculate class weights for imbalanced dataset
        sample_data = train_dataset.take(10000)  # Sample for class weight calculation
        df_sample = pd.DataFrame(sample_data)
        if target_column in df_sample.columns:
            pos_count = df_sample[target_column].sum()
            neg_count = len(df_sample) - pos_count
            if pos_count > 0:
                scale_pos_weight = neg_count / pos_count
                default_params['scale_pos_weight'] = scale_pos_weight
                print(f"Calculated scale_pos_weight: {scale_pos_weight:.2f}")
        
        # Configure Ray Train scaling
        scaling_config = ScalingConfig(
            num_workers=num_workers,
            use_gpu=use_gpu,
            resources_per_worker={"GPU": 1, "CPU": 4} if use_gpu else {"CPU": 4}
        )
        
        # Configure training run
        run_config = RunConfig(
            name=f"fraud_detection_xgboost_{datetime.now().strftime('%Y%m%d_%H%M%S')}",
            storage_path="s3://fraud-detection-models/ray_results/"
        )
        
        # Create trainer
        trainer = XGBoostTrainer(
            scaling_config=scaling_config,
            run_config=run_config,
            datasets={"train": train_dataset, "valid": val_dataset},
            params=default_params,
            label_column=target_column,
            num_boost_round=100
        )
        
        print("Starting XGBoost training...")
        print(f"Parameters: {default_params}")
        print(f"Scaling config: num_workers={num_workers}, use_gpu={use_gpu}")
        
        # Train the model
        result = trainer.fit()
        self.training_results = result
        
        print("Training completed!")
        print(f"Best validation score: {result.metrics.get('valid-auc', 'N/A')}")
        
        return result
    
    def evaluate_model(self, 
                      val_dataset: Dataset,
                      target_column: str = 'TX_FRAUD_1') -> Dict[str, Any]:
        """
        Evaluate trained model on validation dataset
        
        Args:
            val_dataset: Validation dataset
            target_column: Name of target column
            
        Returns:
            Evaluation metrics
        """
        
        if not self.training_results:
            raise ValueError("No trained model available. Run train_model first.")
        
        # Get the trained model
        checkpoint = self.training_results.checkpoint
        model = XGBoostTrainer.get_model(checkpoint)
        
        # Convert validation dataset to pandas for evaluation
        val_df = val_dataset.to_pandas()
        
        # Separate features and target
        feature_columns = [col for col in val_df.columns if col != target_column]
        X_val = val_df[feature_columns]
        y_val = val_df[target_column]
        
        # Make predictions
        y_pred_proba = model.predict_proba(X_val)[:, 1]
        y_pred = (y_pred_proba > 0.5).astype(int)
        
        # Calculate metrics
        auc_score = roc_auc_score(y_val, y_pred_proba)
        classification_rep = classification_report(y_val, y_pred, output_dict=True)
        confusion_mat = confusion_matrix(y_val, y_pred)
        
        metrics = {
            'auc_score': auc_score,
            'classification_report': classification_rep,
            'confusion_matrix': confusion_mat.tolist(),
            'accuracy': classification_rep['accuracy'],
            'precision': classification_rep['1']['precision'],
            'recall': classification_rep['1']['recall'],
            'f1_score': classification_rep['1']['f1-score']
        }
        
        print("=== Model Evaluation Results ===")
        print(f"AUC Score: {auc_score:.4f}")
        print(f"Accuracy: {metrics['accuracy']:.4f}")
        print(f"Precision: {metrics['precision']:.4f}")
        print(f"Recall: {metrics['recall']:.4f}")
        print(f"F1 Score: {metrics['f1_score']:.4f}")
        
        return metrics
    
    def save_model(self, s3_path: str) -> str:
        """
        Save trained model to S3
        
        Args:
            s3_path: S3 path to save model
            
        Returns:
            Full S3 path of saved model
        """
        
        if not self.training_results:
            raise ValueError("No trained model available. Run train_model first.")
        
        # Get the trained model
        checkpoint = self.training_results.checkpoint
        model = XGBoostTrainer.get_model(checkpoint)
        
        # Save model locally first
        local_model_path = "/tmp/fraud_detection_model.json"
        model.save_model(local_model_path)
        
        # Upload to S3
        s3_client = boto3.client('s3')
        bucket_name = s3_path.replace('s3://', '').split('/')[0]
        s3_key = '/'.join(s3_path.replace('s3://', '').split('/')[1:])
        
        if not s3_key.endswith('.json'):
            s3_key = f"{s3_key}/model.json"
        
        s3_client.upload_file(local_model_path, bucket_name, s3_key)
        
        full_s3_path = f"s3://{bucket_name}/{s3_key}"
        print(f"Model saved to: {full_s3_path}")
        
        return full_s3_path


def setup_ray_environment():
    """Setup Ray environment for notebooks"""
    
    print("=== Ray Environment Setup ===")
    
    # Get Ray cluster info
    ray_address = os.environ.get('RAY_ADDRESS', 'ray://ray-cluster-head:10001')
    print(f"Ray Address: {ray_address}")
    
    # Create Ray client
    ray_client = RayClusterClient(ray_address)
    
    try:
        ray_client.connect()
        cluster_info = ray_client.get_cluster_info()
        
        print(f"Connected to Ray cluster with {len(cluster_info['nodes'])} nodes")
        print(f"Available resources: {cluster_info['available_resources']}")
        
        return ray_client
        
    except Exception as e:
        print(f"Failed to connect to Ray cluster: {e}")
        print("You can still use local Ray for development")
        return None


def load_model_from_s3(s3_path: str):
    """
    Load XGBoost model from S3
    
    Args:
        s3_path: S3 path to model file
        
    Returns:
        Loaded XGBoost model
    """
    
    # Download model from S3
    s3_client = boto3.client('s3')
    bucket_name = s3_path.replace('s3://', '').split('/')[0]
    s3_key = '/'.join(s3_path.replace('s3://', '').split('/')[1:])
    
    local_model_path = "/tmp/downloaded_model.json"
    s3_client.download_file(bucket_name, s3_key, local_model_path)
    
    # Load model
    model = xgb.Booster()
    model.load_model(local_model_path)
    
    print(f"Model loaded from: {s3_path}")
    return model