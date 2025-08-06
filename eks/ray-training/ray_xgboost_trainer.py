#!/usr/bin/env python3
"""
Ray XGBoost Distributed Training for Fraud Detection
Migrated from SageMaker to EKS using EMR Spark RAPIDS patterns

This script implements distributed XGBoost training using Ray on EKS,
replacing the SageMaker training approach with GPU-accelerated training
compatible with existing EMR Spark RAPIDS infrastructure.

Requirements implemented:
- 2.2: GPU-accelerated training with tree_method="gpu_hist"
- 2.3: Model artifacts saved to S3 in SageMaker-compatible format
- 2.4: Training job monitoring and logging functionality
"""

import os
import sys
import time
import json
import logging
import argparse
from typing import Dict, List, Tuple, Optional, Any
from datetime import datetime
import traceback

import pandas as pd
import numpy as np
import boto3
import s3fs
from botocore.exceptions import ClientError

import ray
from ray import train
from ray.train import ScalingConfig, RunConfig, CheckpointConfig
from ray.train.xgboost import XGBoostTrainer
from ray.data import Dataset
import xgboost as xgb

from sklearn.model_selection import train_test_split
from sklearn.metrics import (
    classification_report, 
    roc_auc_score, 
    precision_recall_curve,
    confusion_matrix,
    accuracy_score,
    f1_score
)

# Configure comprehensive logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler('/tmp/ray_training.log')
    ]
)
logger = logging.getLogger(__name__)

class RayXGBoostTrainer:
    """
    Ray-based XGBoost trainer for fraud detection
    Migrated from SageMaker with enhanced GPU acceleration and monitoring
    """
    
    def __init__(self, config: Dict[str, Any]):
        """
        Initialize the Ray XGBoost trainer
        
        Args:
            config: Training configuration dictionary
        """
        self.config = config
        self.s3_client = boto3.client('s3')
        self.s3_fs = s3fs.S3FileSystem()
        
        # Training metrics tracking
        self.training_metrics = {
            'start_time': None,
            'end_time': None,
            'training_duration': None,
            'data_loading_time': None,
            'preprocessing_time': None,
            'model_training_time': None,
            'evaluation_time': None,
            'model_save_time': None
        }
        
        # Model performance metrics
        self.model_metrics = {}
        
        logger.info(f"Initialized RayXGBoostTrainer with config: {json.dumps(config, indent=2)}")
    
    def load_data_from_s3(self) -> Tuple[pd.DataFrame, Dict[str, Any]]:
        """
        Load fraud detection data from S3 with enhanced error handling
        
        Returns:
            Tuple of (combined_dataframe, data_info)
        """
        start_time = time.time()
        logger.info(f"Loading data from s3://{self.config['s3_bucket']}/{self.config['data_prefix']}")
        
        try:
            # List all parquet files in the prefix
            files = self.s3_fs.glob(f"{self.config['s3_bucket']}/{self.config['data_prefix']}/*.parquet")
            
            if not files:
                raise ValueError(f"No parquet files found in s3://{self.config['s3_bucket']}/{self.config['data_prefix']}")
            
            logger.info(f"Found {len(files)} parquet files")
            
            # Read parquet files with size limit for training
            max_files = self.config.get('max_training_files', 50)
            selected_files = files[:max_files]
            
            dfs = []
            total_rows = 0
            
            for i, file in enumerate(selected_files):
                try:
                    df = pd.read_parquet(f"s3://{file}")
                    dfs.append(df)
                    total_rows += len(df)
                    
                    if i % 10 == 0:
                        logger.info(f"Loaded {i+1}/{len(selected_files)} files, {total_rows} total rows")
                        
                except Exception as e:
                    logger.warning(f"Failed to load file {file}: {str(e)}")
                    continue
            
            if not dfs:
                raise ValueError("No valid parquet files could be loaded")
            
            # Combine all dataframes
            combined_df = pd.concat(dfs, ignore_index=True)
            
            # Data information
            data_info = {
                'total_files': len(files),
                'loaded_files': len(selected_files),
                'total_rows': len(combined_df),
                'columns': list(combined_df.columns),
                'memory_usage_mb': combined_df.memory_usage(deep=True).sum() / 1024 / 1024
            }
            
            loading_time = time.time() - start_time
            self.training_metrics['data_loading_time'] = loading_time
            
            logger.info(f"Data loading completed in {loading_time:.2f} seconds")
            logger.info(f"Loaded {len(combined_df)} records from {len(selected_files)} files")
            logger.info(f"Memory usage: {data_info['memory_usage_mb']:.2f} MB")
            
            return combined_df, data_info
            
        except Exception as e:
            logger.error(f"Error loading data from S3: {str(e)}")
            logger.error(traceback.format_exc())
            raise
    
    def prepare_features(self, df: pd.DataFrame) -> Tuple[np.ndarray, np.ndarray, List[str], Dict[str, Any]]:
        """
        Prepare features for XGBoost training with enhanced preprocessing
        
        Args:
            df: Input dataframe
            
        Returns:
            Tuple of (X, y, feature_names, preprocessing_info)
        """
        start_time = time.time()
        logger.info("Preparing features for training")
        
        try:
            # Identify feature columns (excluding target and metadata)
            exclude_cols = {
                'TX_FRAUD_1', 'TX_FRAUD', 'TX_DATETIME', 'CUSTOMER_ID', 'TERMINAL_ID',
                'yyyy', 'mm', 'dd'  # Date components used for partitioning
            }
            
            available_cols = set(df.columns)
            feature_cols = [col for col in available_cols if col not in exclude_cols]
            
            logger.info(f"Available columns: {len(available_cols)}")
            logger.info(f"Feature columns: {len(feature_cols)}")
            
            # Handle target column (try both possible names)
            target_col = None
            if 'TX_FRAUD_1' in df.columns:
                target_col = 'TX_FRAUD_1'
            elif 'TX_FRAUD' in df.columns:
                target_col = 'TX_FRAUD'
            else:
                raise ValueError("No target column found (TX_FRAUD_1 or TX_FRAUD)")
            
            # Extract features and target
            X = df[feature_cols].copy()
            y = df[target_col].copy()
            
            # Handle missing values
            missing_counts = X.isnull().sum()
            if missing_counts.sum() > 0:
                logger.info(f"Handling {missing_counts.sum()} missing values")
                X = X.fillna(0)  # Simple imputation for now
            
            # Convert to appropriate data types
            X = X.astype(np.float32)
            y = y.astype(np.int32)
            
            # Data validation
            if len(X) != len(y):
                raise ValueError(f"Feature matrix and target have different lengths: {len(X)} vs {len(y)}")
            
            if X.shape[1] == 0:
                raise ValueError("No feature columns found")
            
            # Check for infinite values
            inf_mask = np.isinf(X.values).any(axis=1)
            if inf_mask.sum() > 0:
                logger.warning(f"Removing {inf_mask.sum()} rows with infinite values")
                X = X[~inf_mask]
                y = y[~inf_mask]
            
            # Preprocessing information
            preprocessing_info = {
                'feature_count': len(feature_cols),
                'sample_count': len(X),
                'target_distribution': dict(zip(*np.unique(y, return_counts=True))),
                'missing_values_handled': missing_counts.sum(),
                'infinite_values_removed': inf_mask.sum(),
                'feature_names': feature_cols
            }
            
            preprocessing_time = time.time() - start_time
            self.training_metrics['preprocessing_time'] = preprocessing_time
            
            logger.info(f"Feature preparation completed in {preprocessing_time:.2f} seconds")
            logger.info(f"Feature matrix shape: {X.shape}")
            logger.info(f"Target distribution: {preprocessing_info['target_distribution']}")
            
            return X.values, y.values, feature_cols, preprocessing_info
            
        except Exception as e:
            logger.error(f"Error preparing features: {str(e)}")
            logger.error(traceback.format_exc())
            raise
    
    def create_ray_datasets(self, X_train: np.ndarray, y_train: np.ndarray, 
                           X_test: np.ndarray, y_test: np.ndarray, 
                           feature_names: List[str]) -> Tuple[Dataset, Dataset]:
        """
        Create Ray datasets for distributed training
        
        Args:
            X_train, y_train: Training data
            X_test, y_test: Test data
            feature_names: List of feature names
            
        Returns:
            Tuple of (train_dataset, test_dataset)
        """
        logger.info("Creating Ray datasets for distributed training")
        
        try:
            # Create training dataset
            train_df = pd.DataFrame(X_train, columns=feature_names)
            train_df['target'] = y_train
            train_dataset = ray.data.from_pandas(train_df)
            
            # Create test dataset
            test_df = pd.DataFrame(X_test, columns=feature_names)
            test_df['target'] = y_test
            test_dataset = ray.data.from_pandas(test_df)
            
            logger.info(f"Created Ray datasets - Train: {len(train_df)}, Test: {len(test_df)}")
            
            return train_dataset, test_dataset
            
        except Exception as e:
            logger.error(f"Error creating Ray datasets: {str(e)}")
            raise
    
    def get_xgboost_params(self) -> Dict[str, Any]:
        """
        Get XGBoost parameters optimized for GPU training
        
        Returns:
            Dictionary of XGBoost parameters
        """
        # Base parameters optimized for fraud detection
        params = {
            'objective': 'binary:logistic',
            'eval_metric': ['auc', 'logloss'],
            'tree_method': 'gpu_hist' if self.config.get('use_gpu', True) else 'hist',
            'max_depth': self.config.get('max_depth', 6),
            'learning_rate': self.config.get('learning_rate', 0.1),
            'subsample': self.config.get('subsample', 0.8),
            'colsample_bytree': self.config.get('colsample_bytree', 0.8),
            'min_child_weight': self.config.get('min_child_weight', 1),
            'reg_alpha': self.config.get('reg_alpha', 0.1),
            'reg_lambda': self.config.get('reg_lambda', 1.0),
            'scale_pos_weight': self.config.get('scale_pos_weight', 10),  # Handle class imbalance
            'random_state': self.config.get('random_state', 42),
            'n_jobs': -1
        }
        
        # GPU-specific parameters
        if self.config.get('use_gpu', True):
            params.update({
                'gpu_id': 0,
                'predictor': 'gpu_predictor'
            })
        
        logger.info(f"XGBoost parameters: {json.dumps(params, indent=2)}")
        return params
    
    def train_model(self, train_dataset: Dataset, test_dataset: Dataset) -> train.Result:
        """
        Train XGBoost model using Ray distributed training
        
        Args:
            train_dataset: Ray training dataset
            test_dataset: Ray test dataset
            
        Returns:
            Ray training result
        """
        start_time = time.time()
        logger.info("Starting distributed XGBoost training")
        
        try:
            # Get XGBoost parameters
            xgb_params = self.get_xgboost_params()
            
            # Configure scaling
            scaling_config = ScalingConfig(
                num_workers=self.config.get('num_workers', 4),
                use_gpu=self.config.get('use_gpu', True),
                resources_per_worker={
                    "CPU": self.config.get('cpu_per_worker', 4),
                    "GPU": 1 if self.config.get('use_gpu', True) else 0
                }
            )
            
            # Configure checkpointing
            checkpoint_config = CheckpointConfig(
                num_to_keep=self.config.get('num_checkpoints_to_keep', 3),
                checkpoint_score_attribute="valid-auc",
                checkpoint_score_order="max"
            )
            
            # Configure run
            run_config = RunConfig(
                name=f"fraud_detection_xgboost_{datetime.now().strftime('%Y%m%d_%H%M%S')}",
                storage_path=f"s3://{self.config['s3_bucket']}/{self.config['model_output_prefix']}/checkpoints",
                checkpoint_config=checkpoint_config
            )
            
            # Create trainer
            trainer = XGBoostTrainer(
                scaling_config=scaling_config,
                label_column="target",
                params=xgb_params,
                datasets={"train": train_dataset, "valid": test_dataset},
                num_boost_round=self.config.get('num_boost_round', 100),
                run_config=run_config
            )
            
            # Train the model
            logger.info("Starting model training...")
            result = trainer.fit()
            
            training_time = time.time() - start_time
            self.training_metrics['model_training_time'] = training_time
            
            logger.info(f"Training completed in {training_time:.2f} seconds")
            logger.info(f"Training metrics: {result.metrics}")
            
            return result
            
        except Exception as e:
            logger.error(f"Error during model training: {str(e)}")
            logger.error(traceback.format_exc())
            raise
    
    def evaluate_model(self, model: xgb.Booster, X_test: np.ndarray, 
                      y_test: np.ndarray) -> Dict[str, Any]:
        """
        Evaluate trained model on test set
        
        Args:
            model: Trained XGBoost model
            X_test: Test features
            y_test: Test targets
            
        Returns:
            Dictionary of evaluation metrics
        """
        start_time = time.time()
        logger.info("Evaluating model on test set")
        
        try:
            # Make predictions
            test_dmatrix = xgb.DMatrix(X_test)
            y_pred_proba = model.predict(test_dmatrix)
            y_pred = (y_pred_proba > 0.5).astype(int)
            
            # Calculate metrics
            metrics = {
                'test_auc': float(roc_auc_score(y_test, y_pred_proba)),
                'test_accuracy': float(accuracy_score(y_test, y_pred)),
                'test_f1': float(f1_score(y_test, y_pred)),
                'test_precision': float(precision_recall_curve(y_test, y_pred_proba)[0].mean()),
                'test_recall': float(precision_recall_curve(y_test, y_pred_proba)[1].mean())
            }
            
            # Confusion matrix
            cm = confusion_matrix(y_test, y_pred)
            metrics['confusion_matrix'] = cm.tolist()
            
            # Classification report
            class_report = classification_report(y_test, y_pred, output_dict=True)
            metrics['classification_report'] = class_report
            
            evaluation_time = time.time() - start_time
            self.training_metrics['evaluation_time'] = evaluation_time
            
            logger.info(f"Model evaluation completed in {evaluation_time:.2f} seconds")
            logger.info(f"Test AUC: {metrics['test_auc']:.4f}")
            logger.info(f"Test Accuracy: {metrics['test_accuracy']:.4f}")
            logger.info(f"Test F1: {metrics['test_f1']:.4f}")
            
            self.model_metrics = metrics
            return metrics
            
        except Exception as e:
            logger.error(f"Error during model evaluation: {str(e)}")
            logger.error(traceback.format_exc())
            raise
    
    def save_model_artifacts(self, model: xgb.Booster, feature_names: List[str], 
                           model_metrics: Dict[str, Any], 
                           preprocessing_info: Dict[str, Any]) -> Dict[str, str]:
        """
        Save model artifacts to S3 in SageMaker-compatible format
        
        Args:
            model: Trained XGBoost model
            feature_names: List of feature names
            model_metrics: Model evaluation metrics
            preprocessing_info: Preprocessing information
            
        Returns:
            Dictionary of saved artifact paths
        """
        start_time = time.time()
        logger.info("Saving model artifacts to S3")
        
        try:
            timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
            model_version = f"v_{timestamp}"
            
            # Create local temporary directory
            local_model_dir = f"/tmp/model_artifacts_{timestamp}"
            os.makedirs(local_model_dir, exist_ok=True)
            
            # Save model in XGBoost format
            local_model_path = os.path.join(local_model_dir, "model.xgb")
            model.save_model(local_model_path)
            
            # Save model metadata (SageMaker compatible)
            metadata = {
                'model_version': model_version,
                'timestamp': timestamp,
                'feature_names': feature_names,
                'model_metrics': model_metrics,
                'preprocessing_info': preprocessing_info,
                'training_config': self.config,
                'training_metrics': self.training_metrics,
                'xgboost_version': xgb.__version__,
                'model_format': 'xgboost'
            }
            
            metadata_path = os.path.join(local_model_dir, "model_metadata.json")
            with open(metadata_path, 'w') as f:
                json.dump(metadata, f, indent=2, default=str)
            
            # Save feature importance
            importance_dict = model.get_score(importance_type='weight')
            importance_df = pd.DataFrame([
                {'feature': k, 'importance': v} 
                for k, v in importance_dict.items()
            ]).sort_values('importance', ascending=False)
            
            importance_path = os.path.join(local_model_dir, "feature_importance.csv")
            importance_df.to_csv(importance_path, index=False)
            
            # Upload to S3
            s3_paths = {}
            
            # Upload model
            model_s3_key = f"{self.config['model_output_prefix']}/{model_version}/model.xgb"
            self.s3_client.upload_file(local_model_path, self.config['s3_bucket'], model_s3_key)
            s3_paths['model'] = f"s3://{self.config['s3_bucket']}/{model_s3_key}"
            
            # Upload metadata
            metadata_s3_key = f"{self.config['model_output_prefix']}/{model_version}/model_metadata.json"
            self.s3_client.upload_file(metadata_path, self.config['s3_bucket'], metadata_s3_key)
            s3_paths['metadata'] = f"s3://{self.config['s3_bucket']}/{metadata_s3_key}"
            
            # Upload feature importance
            importance_s3_key = f"{self.config['model_output_prefix']}/{model_version}/feature_importance.csv"
            self.s3_client.upload_file(importance_path, self.config['s3_bucket'], importance_s3_key)
            s3_paths['feature_importance'] = f"s3://{self.config['s3_bucket']}/{importance_s3_key}"
            
            # Create latest symlink (for compatibility)
            latest_model_key = f"{self.config['model_output_prefix']}/latest/model.xgb"
            latest_metadata_key = f"{self.config['model_output_prefix']}/latest/model_metadata.json"
            
            # Copy to latest
            copy_source = {'Bucket': self.config['s3_bucket'], 'Key': model_s3_key}
            self.s3_client.copy_object(CopySource=copy_source, Bucket=self.config['s3_bucket'], Key=latest_model_key)
            
            copy_source = {'Bucket': self.config['s3_bucket'], 'Key': metadata_s3_key}
            self.s3_client.copy_object(CopySource=copy_source, Bucket=self.config['s3_bucket'], Key=latest_metadata_key)
            
            s3_paths['latest_model'] = f"s3://{self.config['s3_bucket']}/{latest_model_key}"
            s3_paths['latest_metadata'] = f"s3://{self.config['s3_bucket']}/{latest_metadata_key}"
            
            # Cleanup local files
            import shutil
            shutil.rmtree(local_model_dir)
            
            save_time = time.time() - start_time
            self.training_metrics['model_save_time'] = save_time
            
            logger.info(f"Model artifacts saved in {save_time:.2f} seconds")
            logger.info(f"Model paths: {json.dumps(s3_paths, indent=2)}")
            
            return s3_paths
            
        except Exception as e:
            logger.error(f"Error saving model artifacts: {str(e)}")
            logger.error(traceback.format_exc())
            raise
    
    def run_training_pipeline(self) -> Dict[str, Any]:
        """
        Run the complete training pipeline
        
        Returns:
            Dictionary with training results and artifact paths
        """
        self.training_metrics['start_time'] = datetime.now()
        logger.info("Starting Ray XGBoost training pipeline")
        
        try:
            # Load data
            df, data_info = self.load_data_from_s3()
            
            # Prepare features
            X, y, feature_names, preprocessing_info = self.prepare_features(df)
            
            # Split data
            X_train, X_test, y_train, y_test = train_test_split(
                X, y, 
                test_size=self.config.get('test_size', 0.2),
                random_state=self.config.get('random_state', 42),
                stratify=y
            )
            
            logger.info(f"Data split - Train: {len(X_train)}, Test: {len(X_test)}")
            
            # Create Ray datasets
            train_dataset, test_dataset = self.create_ray_datasets(
                X_train, y_train, X_test, y_test, feature_names
            )
            
            # Train model
            result = self.train_model(train_dataset, test_dataset)
            
            # Get trained model
            model = XGBoostTrainer.get_model(result.checkpoint)
            
            # Evaluate model
            model_metrics = self.evaluate_model(model, X_test, y_test)
            
            # Save model artifacts
            s3_paths = self.save_model_artifacts(
                model, feature_names, model_metrics, preprocessing_info
            )
            
            # Final metrics
            self.training_metrics['end_time'] = datetime.now()
            self.training_metrics['training_duration'] = (
                self.training_metrics['end_time'] - self.training_metrics['start_time']
            ).total_seconds()
            
            # Compile results
            results = {
                'success': True,
                'model_metrics': model_metrics,
                'training_metrics': self.training_metrics,
                'data_info': data_info,
                'preprocessing_info': preprocessing_info,
                's3_paths': s3_paths,
                'ray_result': {
                    'metrics': result.metrics,
                    'checkpoint_path': str(result.checkpoint.path) if result.checkpoint else None
                }
            }
            
            logger.info("Training pipeline completed successfully!")
            logger.info(f"Total training time: {self.training_metrics['training_duration']:.2f} seconds")
            logger.info(f"Final test AUC: {model_metrics['test_auc']:.4f}")
            
            return results
            
        except Exception as e:
            logger.error(f"Training pipeline failed: {str(e)}")
            logger.error(traceback.format_exc())
            
            # Return error results
            return {
                'success': False,
                'error': str(e),
                'traceback': traceback.format_exc(),
                'training_metrics': self.training_metrics
            }


def parse_arguments() -> argparse.Namespace:
    """Parse command line arguments"""
    parser = argparse.ArgumentParser(description='Ray XGBoost Distributed Training for Fraud Detection')
    
    # Data parameters
    parser.add_argument('--s3-bucket', type=str, required=True,
                       help='S3 bucket name for data and model storage')
    parser.add_argument('--data-prefix', type=str, required=True,
                       help='S3 prefix for training data')
    parser.add_argument('--model-output-prefix', type=str, default='models/xgboost',
                       help='S3 prefix for model output')
    
    # Training parameters
    parser.add_argument('--num-workers', type=int, default=4,
                       help='Number of Ray workers for training')
    parser.add_argument('--num-boost-round', type=int, default=100,
                       help='Number of boosting rounds')
    parser.add_argument('--use-gpu', action='store_true', default=True,
                       help='Use GPU acceleration')
    parser.add_argument('--max-training-files', type=int, default=50,
                       help='Maximum number of training files to load')
    
    # Model parameters
    parser.add_argument('--max-depth', type=int, default=6,
                       help='Maximum tree depth')
    parser.add_argument('--learning-rate', type=float, default=0.1,
                       help='Learning rate')
    parser.add_argument('--scale-pos-weight', type=float, default=10,
                       help='Scale positive weight for class imbalance')
    
    # Ray cluster parameters
    parser.add_argument('--ray-address', type=str, 
                       default='ray://fraud-training-cluster-head-svc.ray-ml.svc.cluster.local:10001',
                       help='Ray cluster address')
    
    return parser.parse_args()


def main():
    """Main training function"""
    args = parse_arguments()
    
    # Create training configuration
    config = {
        's3_bucket': args.s3_bucket,
        'data_prefix': args.data_prefix,
        'model_output_prefix': args.model_output_prefix,
        'num_workers': args.num_workers,
        'num_boost_round': args.num_boost_round,
        'use_gpu': args.use_gpu,
        'max_training_files': args.max_training_files,
        'max_depth': args.max_depth,
        'learning_rate': args.learning_rate,
        'scale_pos_weight': args.scale_pos_weight,
        'cpu_per_worker': 4,
        'test_size': 0.2,
        'random_state': 42
    }
    
    logger.info(f"Starting training with configuration: {json.dumps(config, indent=2)}")
    
    # Initialize Ray cluster
    try:
        ray.init(address=args.ray_address)
        logger.info("Ray cluster initialized")
        logger.info(f"Ray cluster resources: {ray.cluster_resources()}")
    except Exception as e:
        logger.error(f"Failed to initialize Ray cluster: {str(e)}")
        sys.exit(1)
    
    try:
        # Create trainer and run pipeline
        trainer = RayXGBoostTrainer(config)
        results = trainer.run_training_pipeline()
        
        if results['success']:
            logger.info("Training completed successfully!")
            logger.info(f"Model saved to: {results['s3_paths']['latest_model']}")
            
            # Save training results
            results_path = f"/tmp/training_results_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
            with open(results_path, 'w') as f:
                json.dump(results, f, indent=2, default=str)
            logger.info(f"Training results saved to: {results_path}")
            
        else:
            logger.error("Training failed!")
            logger.error(f"Error: {results['error']}")
            sys.exit(1)
            
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        logger.error(traceback.format_exc())
        sys.exit(1)
        
    finally:
        ray.shutdown()


if __name__ == "__main__":
    main()