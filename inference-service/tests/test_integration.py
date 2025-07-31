#!/usr/bin/env python3
"""
Integration tests for the FastAPI Fraud Detection Inference Service
Tests integration with S3, model loading, and end-to-end functionality
"""

import pytest
import os
import json
import time
import asyncio
from unittest.mock import patch, Mock
import numpy as np
import xgboost as xgb
from fastapi.testclient import TestClient

# Import the application
import sys
sys.path.append(os.path.join(os.path.dirname(__file__), '..'))

from app.main import app, model_manager

# Test client
client = TestClient(app)

class TestIntegration:
    """Integration test suite"""
    
    @pytest.fixture(scope="class")
    def mock_xgboost_model(self):
        """Create a mock XGBoost model for testing"""
        # Create a simple XGBoost model
        from sklearn.datasets import make_classification
        from sklearn.model_selection import train_test_split
        
        # Generate sample data
        X, y = make_classification(
            n_samples=1000,
            n_features=10,
            n_classes=2,
            random_state=42
        )
        
        X_train, X_test, y_train, y_test = train_test_split(
            X, y, test_size=0.2, random_state=42
        )
        
        # Train a simple model
        model = xgb.XGBClassifier(
            objective='binary:logistic',
            n_estimators=10,
            max_depth=3,
            random_state=42
        )
        model.fit(X_train, y_train)
        
        # Save model to temporary file
        model_path = '/tmp/test_model.xgb'
        model.save_model(model_path)
        
        # Create metadata
        metadata = {
            'model_version': 'v_test_integration',
            'feature_names': [f'feature_{i}' for i in range(10)],
            'model_metrics': {'test_auc': 0.85},
            'timestamp': '2023-12-01T12:00:00'
        }
        
        metadata_path = '/tmp/test_model_metadata.json'
        with open(metadata_path, 'w') as f:
            json.dump(metadata, f)
        
        return {
            'model_path': model_path,
            'metadata_path': metadata_path,
            'metadata': metadata,
            'feature_names': metadata['feature_names']
        }
    
    def test_model_loading_integration(self, mock_xgboost_model):
        """Test model loading from local files (simulating S3)"""
        
        # Mock S3 client to use local files
        def mock_download_file(bucket, key, local_path):
            if 'model.xgb' in key:
                import shutil
                shutil.copy(mock_xgboost_model['model_path'], local_path)
            elif 'metadata.json' in key:
                import shutil
                shutil.copy(mock_xgboost_model['metadata_path'], local_path)
        
        with patch.object(model_manager.s3_client, 'download_file', side_effect=mock_download_file):
            # Test model loading
            success = asyncio.run(model_manager.load_model_from_s3())
            assert success
            
            # Verify model is loaded
            assert model_manager.is_model_loaded()
            assert model_manager.model_version == 'v_test_integration'
            assert len(model_manager.feature_names) == 10
    
    def test_end_to_end_prediction_flow(self, mock_xgboost_model):
        """Test complete prediction flow with loaded model"""
        
        # Mock S3 client
        def mock_download_file(bucket, key, local_path):
            if 'model.xgb' in key:
                import shutil
                shutil.copy(mock_xgboost_model['model_path'], local_path)
            elif 'metadata.json' in key:
                import shutil
                shutil.copy(mock_xgboost_model['metadata_path'], local_path)
        
        with patch.object(model_manager.s3_client, 'download_file', side_effect=mock_download_file):
            # Load model
            success = asyncio.run(model_manager.load_model_from_s3())
            assert success
            
            # Test health check
            response = client.get("/health")
            assert response.status_code == 200
            data = response.json()
            assert data["status"] == "healthy"
            assert data["model_status"] == "loaded"
            
            # Test single prediction with simplified features
            transaction_data = {
                "TX_AMOUNT": 150.0,
                "yyyy": 2023,
                "mm": 12,
                "dd": 1,
                "CUSTOMER_ID_index": 123.0,
                "TERMINAL_ID_index": 456.0
            }
            
            response = client.post("/predict", json=transaction_data)
            assert response.status_code == 200
            
            data = response.json()
            assert "fraud_probability" in data
            assert "is_fraud" in data
            assert data["model_version"] == "v_test_integration"
            assert 0.0 <= data["fraud_probability"] <= 1.0
            
            # Test batch prediction
            batch_data = {
                "transactions": [transaction_data, transaction_data]
            }
            
            response = client.post("/predict/batch", json=batch_data)
            assert response.status_code == 200
            
            data = response.json()
            assert data["batch_size"] == 2
            assert len(data["predictions"]) == 2
            assert "processing_time_ms" in data
    
    def test_model_reload_integration(self, mock_xgboost_model):
        """Test model reload functionality"""
        
        def mock_download_file(bucket, key, local_path):
            if 'model.xgb' in key:
                import shutil
                shutil.copy(mock_xgboost_model['model_path'], local_path)
            elif 'metadata.json' in key:
                import shutil
                shutil.copy(mock_xgboost_model['metadata_path'], local_path)
        
        with patch.object(model_manager.s3_client, 'download_file', side_effect=mock_download_file):
            # Initial load
            success = asyncio.run(model_manager.load_model_from_s3())
            assert success
            
            initial_load_time = model_manager.last_loaded
            
            # Wait a moment
            time.sleep(0.1)
            
            # Trigger reload
            response = client.post("/model/reload")
            assert response.status_code == 200
            
            # Give background task time to complete
            time.sleep(1)
            
            # Verify model was reloaded
            assert model_manager.last_loaded > initial_load_time
    
    def test_error_handling_integration(self):
        """Test error handling with various failure scenarios"""
        
        # Test with S3 access error
        with patch.object(model_manager.s3_client, 'download_file', 
                         side_effect=Exception("S3 access denied")):
            
            success = asyncio.run(model_manager.load_model_from_s3())
            assert not success
            
            # Health check should show degraded status
            response = client.get("/health")
            assert response.status_code == 200
            data = response.json()
            assert data["model_status"] == "not_loaded"
            
            # Predictions should fail
            transaction_data = {
                "TX_AMOUNT": 150.0,
                "yyyy": 2023,
                "mm": 12,
                "dd": 1,
                "CUSTOMER_ID_index": 123.0,
                "TERMINAL_ID_index": 456.0
            }
            
            response = client.post("/predict", json=transaction_data)
            assert response.status_code == 503
            assert "Model not loaded" in response.json()["message"]
    
    def test_performance_benchmarks(self, mock_xgboost_model):
        """Test performance benchmarks for the service"""
        
        def mock_download_file(bucket, key, local_path):
            if 'model.xgb' in key:
                import shutil
                shutil.copy(mock_xgboost_model['model_path'], local_path)
            elif 'metadata.json' in key:
                import shutil
                shutil.copy(mock_xgboost_model['metadata_path'], local_path)
        
        with patch.object(model_manager.s3_client, 'download_file', side_effect=mock_download_file):
            # Load model
            success = asyncio.run(model_manager.load_model_from_s3())
            assert success
            
            # Benchmark single predictions
            transaction_data = {
                "TX_AMOUNT": 150.0,
                "yyyy": 2023,
                "mm": 12,
                "dd": 1,
                "CUSTOMER_ID_index": 123.0,
                "TERMINAL_ID_index": 456.0
            }
            
            # Warm up
            for _ in range(5):
                client.post("/predict", json=transaction_data)
            
            # Measure latency
            start_time = time.time()
            num_requests = 50
            
            for _ in range(num_requests):
                response = client.post("/predict", json=transaction_data)
                assert response.status_code == 200
            
            end_time = time.time()
            avg_latency = (end_time - start_time) / num_requests
            
            print(f"Average single prediction latency: {avg_latency*1000:.2f}ms")
            assert avg_latency < 0.1  # Should be under 100ms
            
            # Benchmark batch predictions
            batch_data = {
                "transactions": [transaction_data] * 10
            }
            
            start_time = time.time()
            response = client.post("/predict/batch", json=batch_data)
            end_time = time.time()
            
            assert response.status_code == 200
            batch_latency = end_time - start_time
            
            print(f"Batch prediction latency (10 items): {batch_latency*1000:.2f}ms")
            assert batch_latency < 0.5  # Should be under 500ms for 10 items
    
    def test_concurrent_requests(self, mock_xgboost_model):
        """Test handling of concurrent requests"""
        import threading
        
        def mock_download_file(bucket, key, local_path):
            if 'model.xgb' in key:
                import shutil
                shutil.copy(mock_xgboost_model['model_path'], local_path)
            elif 'metadata.json' in key:
                import shutil
                shutil.copy(mock_xgboost_model['metadata_path'], local_path)
        
        with patch.object(model_manager.s3_client, 'download_file', side_effect=mock_download_file):
            # Load model
            success = asyncio.run(model_manager.load_model_from_s3())
            assert success
            
            transaction_data = {
                "TX_AMOUNT": 150.0,
                "yyyy": 2023,
                "mm": 12,
                "dd": 1,
                "CUSTOMER_ID_index": 123.0,
                "TERMINAL_ID_index": 456.0
            }
            
            results = []
            errors = []
            
            def make_request():
                try:
                    response = client.post("/predict", json=transaction_data)
                    results.append(response.status_code)
                except Exception as e:
                    errors.append(str(e))
            
            # Create multiple threads
            threads = []
            num_threads = 10
            
            for _ in range(num_threads):
                thread = threading.Thread(target=make_request)
                threads.append(thread)
            
            # Start all threads
            start_time = time.time()
            for thread in threads:
                thread.start()
            
            # Wait for all threads to complete
            for thread in threads:
                thread.join()
            
            end_time = time.time()
            
            # Verify results
            assert len(errors) == 0, f"Errors occurred: {errors}"
            assert len(results) == num_threads
            assert all(status == 200 for status in results)
            
            total_time = end_time - start_time
            print(f"Concurrent requests ({num_threads} threads) completed in {total_time:.2f}s")
            assert total_time < 5.0  # Should complete within 5 seconds

if __name__ == "__main__":
    pytest.main([__file__, "-v", "-s"])