#!/usr/bin/env python3
"""
Test script for Ray XGBoost training implementation
Validates the training pipeline with synthetic data

This script tests the core functionality without requiring
a full Ray cluster or S3 data, useful for development and CI/CD.
"""

import os
import sys
import tempfile
import shutil
import json
import logging
from unittest.mock import Mock, patch, MagicMock
import pandas as pd
import numpy as np
import pytest

# Add the current directory to Python path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def create_synthetic_fraud_data(n_samples=10000, n_features=20):
    """
    Create synthetic fraud detection data for testing
    
    Args:
        n_samples: Number of samples to generate
        n_features: Number of features to generate
        
    Returns:
        pandas.DataFrame with synthetic fraud data
    """
    np.random.seed(42)
    
    # Generate features
    feature_names = [f'feature_{i}' for i in range(n_features)]
    X = np.random.randn(n_samples, n_features)
    
    # Create some correlation patterns for fraud
    fraud_pattern = (X[:, 0] > 1.5) | (X[:, 1] < -1.5) | ((X[:, 2] > 0.5) & (X[:, 3] > 0.5))
    
    # Generate target with class imbalance (5% fraud)
    y = np.zeros(n_samples)
    fraud_indices = np.where(fraud_pattern)[0]
    fraud_sample_size = min(len(fraud_indices), int(0.05 * n_samples))
    y[fraud_indices[:fraud_sample_size]] = 1
    
    # Add some random fraud cases
    random_fraud = np.random.choice(
        np.where(y == 0)[0], 
        size=int(0.02 * n_samples), 
        replace=False
    )
    y[random_fraud] = 1
    
    # Create DataFrame
    df = pd.DataFrame(X, columns=feature_names)
    df['TX_FRAUD_1'] = y.astype(int)
    df['CUSTOMER_ID'] = [f'customer_{i}' for i in range(n_samples)]
    df['TERMINAL_ID'] = [f'terminal_{i % 1000}' for i in range(n_samples)]
    df['TX_DATETIME'] = pd.date_range('2024-01-01', periods=n_samples, freq='1min')
    
    logger.info(f"Created synthetic data: {len(df)} samples, {df['TX_FRAUD_1'].sum()} fraud cases")
    return df

def test_data_loading():
    """Test data loading functionality"""
    logger.info("Testing data loading...")
    
    # Create synthetic data
    df = create_synthetic_fraud_data(1000, 10)
    
    # Save to temporary parquet file
    with tempfile.TemporaryDirectory() as temp_dir:
        parquet_path = os.path.join(temp_dir, 'test_data.parquet')
        df.to_parquet(parquet_path)
        
        # Mock S3 filesystem
        with patch('s3fs.S3FileSystem') as mock_s3fs:
            mock_fs = Mock()
            mock_fs.glob.return_value = [f"bucket/prefix/{os.path.basename(parquet_path)}"]
            mock_s3fs.return_value = mock_fs
            
            # Mock pandas read_parquet to read from local file
            with patch('pandas.read_parquet') as mock_read_parquet:
                mock_read_parquet.return_value = df
                
                # Import and test
                from ray_xgboost_trainer import RayXGBoostTrainer
                
                config = {
                    's3_bucket': 'test-bucket',
                    'data_prefix': 'test-prefix',
                    'model_output_prefix': 'models/test'
                }
                
                trainer = RayXGBoostTrainer(config)
                loaded_df, data_info = trainer.load_data_from_s3()
                
                assert len(loaded_df) == len(df)
                assert 'total_rows' in data_info
                assert data_info['total_rows'] == len(df)
                
    logger.info("Data loading test passed")

def test_feature_preparation():
    """Test feature preparation functionality"""
    logger.info("Testing feature preparation...")
    
    # Create synthetic data
    df = create_synthetic_fraud_data(1000, 10)
    
    from ray_xgboost_trainer import RayXGBoostTrainer
    
    config = {'s3_bucket': 'test', 'data_prefix': 'test', 'model_output_prefix': 'test'}
    trainer = RayXGBoostTrainer(config)
    
    X, y, feature_names, preprocessing_info = trainer.prepare_features(df)
    
    # Validate results
    assert X.shape[0] == len(df)
    assert len(y) == len(df)
    assert len(feature_names) > 0
    assert 'feature_count' in preprocessing_info
    assert 'target_distribution' in preprocessing_info
    
    # Check data types
    assert X.dtype == np.float32
    assert y.dtype == np.int32
    
    # Check target distribution
    fraud_count = preprocessing_info['target_distribution'].get(1, 0)
    normal_count = preprocessing_info['target_distribution'].get(0, 0)
    assert fraud_count > 0
    assert normal_count > 0
    
    logger.info("Feature preparation test passed")

def test_xgboost_params():
    """Test XGBoost parameter generation"""
    logger.info("Testing XGBoost parameter generation...")
    
    from ray_xgboost_trainer import RayXGBoostTrainer
    
    # Test with GPU enabled
    config = {
        's3_bucket': 'test',
        'data_prefix': 'test',
        'model_output_prefix': 'test',
        'use_gpu': True,
        'max_depth': 8,
        'learning_rate': 0.05
    }
    
    trainer = RayXGBoostTrainer(config)
    params = trainer.get_xgboost_params()
    
    # Validate GPU parameters
    assert params['tree_method'] == 'gpu_hist'
    assert params['gpu_id'] == 0
    assert params['predictor'] == 'gpu_predictor'
    assert params['max_depth'] == 8
    assert params['learning_rate'] == 0.05
    
    # Test with GPU disabled
    config['use_gpu'] = False
    trainer = RayXGBoostTrainer(config)
    params = trainer.get_xgboost_params()
    
    assert params['tree_method'] == 'hist'
    assert 'gpu_id' not in params or params.get('gpu_id') is None
    
    logger.info("XGBoost parameter test passed")

def test_model_artifact_saving():
    """Test model artifact saving functionality"""
    logger.info("Testing model artifact saving...")
    
    # Mock XGBoost model
    mock_model = Mock()
    mock_model.save_model = Mock()
    mock_model.get_score.return_value = {'feature_0': 0.5, 'feature_1': 0.3}
    
    # Mock boto3 S3 client
    with patch('boto3.client') as mock_boto3:
        mock_s3_client = Mock()
        mock_boto3.return_value = mock_s3_client
        
        from ray_xgboost_trainer import RayXGBoostTrainer
        
        config = {
            's3_bucket': 'test-bucket',
            'data_prefix': 'test-prefix',
            'model_output_prefix': 'models/test'
        }
        
        trainer = RayXGBoostTrainer(config)
        
        feature_names = ['feature_0', 'feature_1', 'feature_2']
        model_metrics = {'test_auc': 0.85, 'test_accuracy': 0.92}
        preprocessing_info = {'feature_count': 3, 'sample_count': 1000}
        
        # Test saving
        s3_paths = trainer.save_model_artifacts(
            mock_model, feature_names, model_metrics, preprocessing_info
        )
        
        # Validate results
        assert 'model' in s3_paths
        assert 'metadata' in s3_paths
        assert 'feature_importance' in s3_paths
        assert 'latest_model' in s3_paths
        
        # Check that S3 upload was called
        assert mock_s3_client.upload_file.call_count >= 2
        assert mock_s3_client.copy_object.call_count >= 2
        
    logger.info("Model artifact saving test passed")

def test_training_monitor():
    """Test training monitoring functionality"""
    logger.info("Testing training monitor...")
    
    from training_monitor import TrainingMonitor, TrainingMetrics
    
    config = {
        'enable_cloudwatch': False,  # Disable for testing
        'memory_alert_threshold': 90,
        'gpu_memory_alert_threshold': 95
    }
    
    monitor = TrainingMonitor(config)
    
    # Test metrics logging
    monitor.log_training_metrics(
        epoch=1,
        train_loss=0.5,
        train_auc=0.75,
        valid_loss=0.6,
        valid_auc=0.73,
        training_time=30.0
    )
    
    # Validate metrics were stored
    assert len(monitor.training_metrics_history) == 1
    metrics = monitor.training_metrics_history[0]
    assert metrics.epoch == 1
    assert metrics.train_loss == 0.5
    assert metrics.train_auc == 0.75
    
    # Test summary generation
    summary = monitor.get_training_summary()
    assert 'total_epochs' in summary
    assert summary['total_epochs'] == 1
    assert 'best_train_auc' in summary
    assert summary['best_train_auc'] == 0.75
    
    logger.info("Training monitor test passed")

def test_gpu_monitor():
    """Test GPU monitoring functionality"""
    logger.info("Testing GPU monitor...")
    
    from training_monitor import GPUMonitor
    
    # Test with mocked pynvml
    with patch('training_monitor.pynvml') as mock_pynvml:
        # Mock successful initialization
        mock_pynvml.nvmlInit.return_value = None
        mock_pynvml.nvmlDeviceGetCount.return_value = 1
        
        # Mock GPU metrics
        mock_handle = Mock()
        mock_pynvml.nvmlDeviceGetHandleByIndex.return_value = mock_handle
        
        mock_mem_info = Mock()
        mock_mem_info.used = 1024 * 1024 * 1024  # 1GB
        mock_mem_info.total = 8 * 1024 * 1024 * 1024  # 8GB
        mock_pynvml.nvmlDeviceGetMemoryInfo.return_value = mock_mem_info
        
        mock_util = Mock()
        mock_util.gpu = 75
        mock_pynvml.nvmlDeviceGetUtilizationRates.return_value = mock_util
        
        # Test GPU monitor
        gpu_monitor = GPUMonitor()
        assert gpu_monitor.gpu_available == True
        
        metrics = gpu_monitor.get_gpu_metrics()
        assert metrics is not None
        assert 'gpu_memory_used_mb' in metrics
        assert 'gpu_utilization_percent' in metrics
        assert metrics['gpu_utilization_percent'] == 75
        
    logger.info("GPU monitor test passed")

def run_all_tests():
    """Run all tests"""
    logger.info("Starting Ray XGBoost training tests...")
    
    try:
        test_data_loading()
        test_feature_preparation()
        test_xgboost_params()
        test_model_artifact_saving()
        test_training_monitor()
        test_gpu_monitor()
        
        logger.info("All tests passed successfully!")
        return True
        
    except Exception as e:
        logger.error(f"Test failed: {str(e)}")
        import traceback
        logger.error(traceback.format_exc())
        return False

if __name__ == "__main__":
    success = run_all_tests()
    sys.exit(0 if success else 1)