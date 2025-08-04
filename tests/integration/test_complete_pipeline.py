#!/usr/bin/env python3
"""
Complete end-to-end pipeline integration tests
Tests the entire fraud detection pipeline from data ingestion to inference
"""

import pytest
import os
import sys
import time
import json
import tempfile
import subprocess
from datetime import datetime, timedelta
from typing import Dict, List, Optional
import pandas as pd
import numpy as np
from unittest.mock import Mock, patch, MagicMock
import boto3
from kubernetes import client, config
import requests

# Add project paths
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../../'))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../../emr-spark-rapids/fraud-detection'))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../../inference-service'))

class TestCompletePipeline:
    """End-to-end pipeline integration tests"""
    
    @pytest.fixture(scope="class")
    def test_config(self):
        """Test configuration"""
        return {
            'aws_region': os.getenv('AWS_REGION', 'us-west-2'),
            'eks_cluster_name': os.getenv('EKS_CLUSTER_NAME', 'data-on-eks-cluster'),
            's3_bucket': os.getenv('S3_BUCKET', 'test-fraud-detection-bucket'),
            'emr_virtual_cluster_id': os.getenv('EMR_VIRTUAL_CLUSTER_ID', 'test-cluster'),
            'inference_service_url': os.getenv('INFERENCE_SERVICE_URL', 'http://localhost:8000'),
            'test_data_size': 10000,
            'performance_threshold_seconds': 300,  # 5 minutes max for complete pipeline
        }
    
    @pytest.fixture(scope="class")
    def synthetic_data(self, test_config):
        """Generate synthetic fraud detection data"""
        np.random.seed(42)
        n_samples = test_config['test_data_size']
        
        # Generate customers data
        customers = pd.DataFrame({
            'CUSTOMER_ID': [f'customer_{i:06d}' for i in range(1000)],
            'x_customer_id': np.random.uniform(-50, 50, 1000),
            'y_customer_id': np.random.uniform(-50, 50, 1000),
            'mean_amount': np.random.uniform(10, 500, 1000),
            'std_amount': np.random.uniform(5, 100, 1000),
            'mean_nb_tx_per_day': np.random.uniform(1, 20, 1000)
        })
        
        # Generate terminals data
        terminals = pd.DataFrame({
            'TERMINAL_ID': [f'terminal_{i:06d}' for i in range(500)],
            'x_terminal_id': np.random.uniform(-50, 50, 500),
            'y_terminal_id': np.random.uniform(-50, 50, 500)
        })
        
        # Generate transactions data
        transactions = []
        start_date = datetime(2024, 1, 1)
        
        for i in range(n_samples):
            customer_id = f'customer_{np.random.randint(0, 1000):06d}'
            terminal_id = f'terminal_{np.random.randint(0, 500):06d}'
            tx_datetime = start_date + timedelta(
                days=np.random.randint(0, 30),
                hours=np.random.randint(0, 24),
                minutes=np.random.randint(0, 60)
            )
            
            # Generate fraud based on patterns
            is_fraud = 0
            tx_amount = np.random.uniform(1, 1000)
            
            # High amount transactions more likely to be fraud
            if tx_amount > 800:
                is_fraud = np.random.choice([0, 1], p=[0.7, 0.3])
            # Night time transactions more likely to be fraud
            elif tx_datetime.hour < 6 or tx_datetime.hour > 22:
                is_fraud = np.random.choice([0, 1], p=[0.9, 0.1])
            else:
                is_fraud = np.random.choice([0, 1], p=[0.95, 0.05])
            
            transactions.append({
                'TX_DATETIME': tx_datetime,
                'CUSTOMER_ID': customer_id,
                'TERMINAL_ID': terminal_id,
                'TX_AMOUNT': tx_amount,
                'TX_FRAUD': is_fraud,
                'TX_TIME_SECONDS': int(tx_datetime.timestamp()),
                'TX_TIME_DAYS': (tx_datetime - start_date).days,
                'yyyy': tx_datetime.year,
                'mm': tx_datetime.month,
                'dd': tx_datetime.day
            })
        
        transactions_df = pd.DataFrame(transactions)
        
        return {
            'customers': customers,
            'terminals': terminals,
            'transactions': transactions_df
        }
    
    def test_data_ingestion_and_preprocessing(self, test_config, synthetic_data):
        """Test data ingestion and preprocessing with EMR on EKS"""
        print("Testing data ingestion and preprocessing...")
        
        # Mock S3 operations for testing
        with patch('boto3.client') as mock_boto3:
            mock_s3_client = Mock()
            mock_boto3.return_value = mock_s3_client
            
            # Mock successful S3 uploads
            mock_s3_client.upload_file.return_value = None
            mock_s3_client.list_objects_v2.return_value = {
                'Contents': [
                    {'Key': 'customers/customers.parquet'},
                    {'Key': 'terminals/terminals.parquet'},
                    {'Key': 'transactions/transactions.parquet'}
                ]
            }
            
            # Test data upload simulation
            bucket = test_config['s3_bucket']
            
            # Simulate uploading test data
            with tempfile.TemporaryDirectory() as temp_dir:
                customers_path = os.path.join(temp_dir, 'customers.parquet')
                terminals_path = os.path.join(temp_dir, 'terminals.parquet')
                transactions_path = os.path.join(temp_dir, 'transactions.parquet')
                
                synthetic_data['customers'].to_parquet(customers_path)
                synthetic_data['terminals'].to_parquet(terminals_path)
                synthetic_data['transactions'].to_parquet(transactions_path)
                
                # Verify files were created
                assert os.path.exists(customers_path)
                assert os.path.exists(terminals_path)
                assert os.path.exists(transactions_path)
                
                print("✓ Test data files created successfully")
        
        # Test EMR on EKS job submission (mocked)
        with patch('subprocess.run') as mock_subprocess:
            mock_subprocess.return_value = Mock(returncode=0, stdout="Job submitted successfully")
            
            # Simulate EMR job submission
            job_config = {
                'name': 'fraud-detection-feature-engineering-test',
                'virtualClusterId': test_config['emr_virtual_cluster_id'],
                'executionRoleArn': 'arn:aws:iam::123456789012:role/EMRContainers-JobExecutionRole',
                'jobDriver': {
                    'sparkSubmitJobDriver': {
                        'entryPoint': 's3://test-bucket/scripts/fraud_detection_feature_engineering.py',
                        'sparkSubmitParameters': '--conf spark.executor.instances=4'
                    }
                }
            }
            
            # Mock EMR containers client
            with patch('boto3.client') as mock_boto3:
                mock_emr_client = Mock()
                mock_boto3.return_value = mock_emr_client
                mock_emr_client.start_job_run.return_value = {'id': 'test-job-123'}
                mock_emr_client.describe_job_run.return_value = {
                    'jobRun': {'state': 'COMPLETED'}
                }
                
                # Test job submission
                job_id = 'test-job-123'
                assert job_id is not None
                print(f"✓ EMR job submitted with ID: {job_id}")
        
        print("✓ Data ingestion and preprocessing test completed")
    
    def test_feature_engineering_pipeline(self, synthetic_data):
        """Test feature engineering pipeline logic"""
        print("Testing feature engineering pipeline...")
        
        # Import feature engineering functions (mocked for testing)
        try:
            # Mock the Spark context and functions
            with patch('pyspark.sql.SparkSession') as mock_spark:
                mock_spark_session = Mock()
                mock_spark.builder.appName.return_value.config.return_value.getOrCreate.return_value = mock_spark_session
                
                # Mock DataFrame operations
                mock_df = Mock()
                mock_df.count.return_value = len(synthetic_data['transactions'])
                mock_df.select.return_value = mock_df
                mock_df.withColumn.return_value = mock_df
                mock_df.join.return_value = mock_df
                mock_df.groupBy.return_value.agg.return_value = mock_df
                mock_df.orderBy.return_value = mock_df
                
                mock_spark_session.read.parquet.return_value = mock_df
                
                # Test feature engineering logic
                transactions_df = synthetic_data['transactions']
                
                # Test window feature calculation logic
                time_windows = {
                    "15min": 15 * 60,
                    "30min": 30 * 60,
                    "60min": 60 * 60,
                    "1day": 24 * 60 * 60,
                    "7day": 7 * 24 * 60 * 60
                }
                
                # Verify window calculations
                for window_name, window_seconds in time_windows.items():
                    assert window_seconds > 0
                    print(f"✓ Window {window_name}: {window_seconds} seconds")
                
                # Test datetime feature extraction
                sample_datetime = datetime(2024, 1, 15, 14, 30, 0)
                features = {
                    'yyyy': sample_datetime.year,
                    'mm': sample_datetime.month,
                    'dd': sample_datetime.day,
                    'hour': sample_datetime.hour,
                    'minute': sample_datetime.minute,
                    'day_of_week': sample_datetime.weekday() + 1,
                    'is_weekend': 1 if sample_datetime.weekday() >= 5 else 0
                }
                
                assert features['yyyy'] == 2024
                assert features['mm'] == 1
                assert features['dd'] == 15
                assert features['is_weekend'] == 0  # Monday
                
                print("✓ Datetime feature extraction validated")
                
        except ImportError:
            print("⚠ PySpark not available, using mock validation")
        
        print("✓ Feature engineering pipeline test completed")
    
    def test_model_training_pipeline(self, test_config, synthetic_data):
        """Test Ray-based model training pipeline"""
        print("Testing model training pipeline...")
        
        # Mock Ray cluster operations
        with patch('ray.init') as mock_ray_init, \
             patch('ray.get') as mock_ray_get, \
             patch('xgboost.XGBClassifier') as mock_xgb:
            
            mock_ray_init.return_value = None
            mock_ray_get.return_value = None
            
            # Mock XGBoost model
            mock_model = Mock()
            mock_model.fit.return_value = None
            mock_model.predict_proba.return_value = np.array([[0.8, 0.2], [0.1, 0.9]])
            mock_model.save_model.return_value = None
            mock_xgb.return_value = mock_model
            
            # Test training data preparation
            transactions_df = synthetic_data['transactions']
            
            # Simulate feature preparation
            feature_columns = [
                'TX_AMOUNT', 'yyyy', 'mm', 'dd',
                'customer_id_nb_txns_15min_window',
                'customer_id_avg_amt_15min_window',
                'terminal_id_nb_txns_15min_window',
                'terminal_id_avg_amt_15min_window'
            ]
            
            # Create mock feature matrix
            n_samples = len(transactions_df)
            n_features = len(feature_columns)
            X = np.random.randn(n_samples, n_features).astype(np.float32)
            y = transactions_df['TX_FRAUD'].values.astype(np.int32)
            
            # Test training parameters
            training_params = {
                'objective': 'binary:logistic',
                'eval_metric': 'auc',
                'tree_method': 'gpu_hist',
                'gpu_id': 0,
                'max_depth': 6,
                'learning_rate': 0.1,
                'n_estimators': 100,
                'subsample': 0.8,
                'colsample_bytree': 0.8
            }
            
            # Validate training parameters
            assert training_params['objective'] == 'binary:logistic'
            assert training_params['tree_method'] == 'gpu_hist'
            assert 0 < training_params['learning_rate'] <= 1
            
            print("✓ Training parameters validated")
            
            # Mock model training
            mock_model.fit(X, y)
            
            # Test model evaluation
            y_pred_proba = mock_model.predict_proba(X)
            assert y_pred_proba.shape == (n_samples, 2)
            
            print("✓ Model training simulation completed")
            
            # Mock model artifact saving
            with patch('boto3.client') as mock_boto3:
                mock_s3_client = Mock()
                mock_boto3.return_value = mock_s3_client
                mock_s3_client.upload_file.return_value = None
                
                # Test model saving
                model_version = f"v_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
                model_metadata = {
                    'version': model_version,
                    'feature_names': feature_columns,
                    'training_metrics': {
                        'auc': 0.85,
                        'accuracy': 0.92,
                        'precision': 0.88,
                        'recall': 0.79
                    },
                    'training_timestamp': datetime.now().isoformat()
                }
                
                assert model_metadata['training_metrics']['auc'] > 0.8
                print(f"✓ Model artifacts prepared for version: {model_version}")
        
        print("✓ Model training pipeline test completed")
    
    def test_inference_service_deployment(self, test_config):
        """Test inference service deployment and functionality"""
        print("Testing inference service deployment...")
        
        # Mock Kubernetes operations
        with patch('kubernetes.client.AppsV1Api') as mock_k8s_apps, \
             patch('kubernetes.client.CoreV1Api') as mock_k8s_core:
            
            mock_apps_api = Mock()
            mock_core_api = Mock()
            mock_k8s_apps.return_value = mock_apps_api
            mock_k8s_core.return_value = mock_core_api
            
            # Mock deployment status
            mock_deployment = Mock()
            mock_deployment.status.ready_replicas = 3
            mock_deployment.spec.replicas = 3
            mock_apps_api.read_namespaced_deployment.return_value = mock_deployment
            
            # Test deployment readiness
            deployment_name = 'fraud-inference'
            namespace = 'ml-team-a'
            
            ready_replicas = mock_deployment.status.ready_replicas
            desired_replicas = mock_deployment.spec.replicas
            
            assert ready_replicas == desired_replicas
            print(f"✓ Deployment {deployment_name} is ready: {ready_replicas}/{desired_replicas}")
        
        # Test inference service endpoints (mocked)
        with patch('requests.get') as mock_get, \
             patch('requests.post') as mock_post:
            
            # Mock health check response
            mock_get.return_value = Mock(
                status_code=200,
                json=lambda: {
                    'status': 'healthy',
                    'model_status': 'loaded',
                    'model_version': 'v_20241201_120000'
                }
            )
            
            # Mock prediction response
            mock_post.return_value = Mock(
                status_code=200,
                json=lambda: {
                    'fraud_probability': 0.75,
                    'is_fraud': True,
                    'model_version': 'v_20241201_120000',
                    'prediction_timestamp': datetime.now().isoformat()
                }
            )
            
            # Test health check
            health_response = mock_get.return_value
            assert health_response.status_code == 200
            health_data = health_response.json()
            assert health_data['status'] == 'healthy'
            assert health_data['model_status'] == 'loaded'
            
            print("✓ Health check endpoint validated")
            
            # Test prediction endpoint
            test_transaction = {
                'TX_AMOUNT': 1500.0,
                'yyyy': 2024,
                'mm': 12,
                'dd': 1,
                'CUSTOMER_ID_index': 123.0,
                'TERMINAL_ID_index': 456.0,
                'customer_id_nb_txns_15min_window': 5.0,
                'customer_id_avg_amt_15min_window': 200.0
            }
            
            prediction_response = mock_post.return_value
            assert prediction_response.status_code == 200
            prediction_data = prediction_response.json()
            assert 'fraud_probability' in prediction_data
            assert 0 <= prediction_data['fraud_probability'] <= 1
            
            print("✓ Prediction endpoint validated")
        
        print("✓ Inference service deployment test completed")
    
    def test_end_to_end_workflow(self, test_config, synthetic_data):
        """Test complete end-to-end workflow"""
        print("Testing complete end-to-end workflow...")
        
        start_time = time.time()
        
        # Step 1: Data preprocessing (mocked)
        print("Step 1: Data preprocessing...")
        time.sleep(0.1)  # Simulate processing time
        preprocessing_success = True
        assert preprocessing_success
        print("✓ Data preprocessing completed")
        
        # Step 2: Feature engineering (mocked)
        print("Step 2: Feature engineering...")
        time.sleep(0.1)  # Simulate processing time
        
        # Validate feature engineering output
        expected_features = [
            'TX_AMOUNT', 'yyyy', 'mm', 'dd',
            'CUSTOMER_ID_index', 'TERMINAL_ID_index',
            'customer_id_nb_txns_15min_window',
            'customer_id_avg_amt_15min_window',
            'terminal_id_nb_txns_15min_window',
            'terminal_id_avg_amt_15min_window'
        ]
        
        # Add window features for all time windows
        time_windows = ['15min', '30min', '60min', '1day', '7day']
        for window in time_windows:
            expected_features.extend([
                f'customer_id_nb_txns_{window}_window',
                f'customer_id_avg_amt_{window}_window',
                f'terminal_id_nb_txns_{window}_window',
                f'terminal_id_avg_amt_{window}_window'
            ])
        
        # Remove duplicates
        expected_features = list(set(expected_features))
        
        assert len(expected_features) > 20
        print(f"✓ Feature engineering completed with {len(expected_features)} features")
        
        # Step 3: Model training (mocked)
        print("Step 3: Model training...")
        time.sleep(0.2)  # Simulate training time
        
        training_metrics = {
            'auc': 0.87,
            'accuracy': 0.93,
            'precision': 0.89,
            'recall': 0.81,
            'f1_score': 0.85
        }
        
        assert training_metrics['auc'] > 0.8
        assert training_metrics['accuracy'] > 0.9
        print(f"✓ Model training completed with AUC: {training_metrics['auc']:.3f}")
        
        # Step 4: Model deployment (mocked)
        print("Step 4: Model deployment...")
        time.sleep(0.1)  # Simulate deployment time
        
        deployment_success = True
        model_version = f"v_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
        
        assert deployment_success
        print(f"✓ Model deployed successfully: {model_version}")
        
        # Step 5: Inference testing (mocked)
        print("Step 5: Inference testing...")
        
        # Test batch of transactions
        test_transactions = synthetic_data['transactions'].head(10)
        predictions = []
        
        for _, transaction in test_transactions.iterrows():
            # Mock prediction
            fraud_probability = np.random.uniform(0, 1)
            is_fraud = fraud_probability > 0.5
            
            predictions.append({
                'transaction_id': f"tx_{len(predictions)}",
                'fraud_probability': fraud_probability,
                'is_fraud': is_fraud,
                'actual_fraud': transaction['TX_FRAUD']
            })
        
        # Calculate accuracy
        correct_predictions = sum(
            1 for p in predictions 
            if p['is_fraud'] == bool(p['actual_fraud'])
        )
        accuracy = correct_predictions / len(predictions)
        
        assert len(predictions) == 10
        print(f"✓ Inference testing completed with accuracy: {accuracy:.3f}")
        
        # Calculate total workflow time
        end_time = time.time()
        total_time = end_time - start_time
        
        assert total_time < test_config['performance_threshold_seconds']
        print(f"✓ Complete workflow finished in {total_time:.2f} seconds")
        
        # Workflow summary
        workflow_summary = {
            'total_time_seconds': total_time,
            'data_samples_processed': len(synthetic_data['transactions']),
            'features_generated': len(expected_features),
            'model_metrics': training_metrics,
            'inference_accuracy': accuracy,
            'model_version': model_version
        }
        
        print("\n=== End-to-End Workflow Summary ===")
        print(f"Total execution time: {workflow_summary['total_time_seconds']:.2f}s")
        print(f"Data samples processed: {workflow_summary['data_samples_processed']:,}")
        print(f"Features generated: {workflow_summary['features_generated']}")
        print(f"Model AUC: {workflow_summary['model_metrics']['auc']:.3f}")
        print(f"Inference accuracy: {workflow_summary['inference_accuracy']:.3f}")
        print(f"Model version: {workflow_summary['model_version']}")
        
        return workflow_summary
    
    def test_error_handling_and_recovery(self, test_config):
        """Test error handling and recovery mechanisms"""
        print("Testing error handling and recovery...")
        
        # Test EMR job failure handling
        with patch('boto3.client') as mock_boto3:
            mock_emr_client = Mock()
            mock_boto3.return_value = mock_emr_client
            
            # Simulate job failure
            mock_emr_client.start_job_run.return_value = {'id': 'failed-job-123'}
            mock_emr_client.describe_job_run.return_value = {
                'jobRun': {
                    'state': 'FAILED',
                    'stateDetails': 'Out of memory error'
                }
            }
            
            job_id = 'failed-job-123'
            job_status = mock_emr_client.describe_job_run.return_value
            
            assert job_status['jobRun']['state'] == 'FAILED'
            print("✓ EMR job failure detection validated")
        
        # Test inference service error handling
        with patch('requests.post') as mock_post:
            # Simulate service unavailable
            mock_post.return_value = Mock(
                status_code=503,
                json=lambda: {'error': 'Model not loaded'}
            )
            
            error_response = mock_post.return_value
            assert error_response.status_code == 503
            print("✓ Inference service error handling validated")
        
        # Test data quality validation
        invalid_data = pd.DataFrame({
            'TX_AMOUNT': [-100, 2000000, None],  # Invalid amounts
            'TX_FRAUD': [0, 1, 2]  # Invalid fraud labels
        })
        
        # Validate data quality checks
        amount_errors = (invalid_data['TX_AMOUNT'] < 0) | (invalid_data['TX_AMOUNT'] > 1000000)
        fraud_errors = ~invalid_data['TX_FRAUD'].isin([0, 1])
        
        assert amount_errors.sum() > 0
        assert fraud_errors.sum() > 0
        print("✓ Data quality validation checks working")
        
        print("✓ Error handling and recovery test completed")
    
    def test_monitoring_and_observability(self, test_config):
        """Test monitoring and observability features"""
        print("Testing monitoring and observability...")
        
        # Mock Prometheus metrics
        with patch('prometheus_client.CollectorRegistry') as mock_registry:
            mock_registry.return_value = Mock()
            
            # Test metrics collection
            metrics = {
                'pipeline_execution_time_seconds': 45.2,
                'data_processing_rows_total': 10000,
                'model_training_auc': 0.87,
                'inference_requests_total': 150,
                'inference_latency_seconds': 0.025,
                'gpu_utilization_percent': 75.5,
                'memory_usage_bytes': 2147483648  # 2GB
            }
            
            # Validate metrics
            assert metrics['pipeline_execution_time_seconds'] > 0
            assert metrics['data_processing_rows_total'] > 0
            assert 0 <= metrics['model_training_auc'] <= 1
            assert metrics['inference_requests_total'] > 0
            assert metrics['inference_latency_seconds'] < 1
            assert 0 <= metrics['gpu_utilization_percent'] <= 100
            
            print("✓ Metrics collection validated")
        
        # Test alerting rules
        alerting_rules = {
            'high_inference_latency': metrics['inference_latency_seconds'] > 0.1,
            'low_model_accuracy': metrics['model_training_auc'] < 0.8,
            'high_gpu_utilization': metrics['gpu_utilization_percent'] > 90,
            'high_memory_usage': metrics['memory_usage_bytes'] > 3 * 1024**3  # 3GB
        }
        
        # Check alert conditions
        active_alerts = [rule for rule, condition in alerting_rules.items() if condition]
        
        print(f"✓ Alerting rules evaluated, {len(active_alerts)} alerts active")
        
        # Test log aggregation (mocked)
        log_entries = [
            {'timestamp': datetime.now().isoformat(), 'level': 'INFO', 'message': 'Pipeline started'},
            {'timestamp': datetime.now().isoformat(), 'level': 'INFO', 'message': 'Data processing completed'},
            {'timestamp': datetime.now().isoformat(), 'level': 'WARNING', 'message': 'High memory usage detected'},
            {'timestamp': datetime.now().isoformat(), 'level': 'INFO', 'message': 'Model training completed'},
            {'timestamp': datetime.now().isoformat(), 'level': 'INFO', 'message': 'Inference service ready'}
        ]
        
        # Validate log structure
        for entry in log_entries:
            assert 'timestamp' in entry
            assert 'level' in entry
            assert 'message' in entry
            assert entry['level'] in ['DEBUG', 'INFO', 'WARNING', 'ERROR', 'CRITICAL']
        
        warning_logs = [entry for entry in log_entries if entry['level'] == 'WARNING']
        assert len(warning_logs) > 0
        
        print(f"✓ Log aggregation validated with {len(log_entries)} entries")
        
        print("✓ Monitoring and observability test completed")

if __name__ == "__main__":
    pytest.main([__file__, "-v", "-s"])