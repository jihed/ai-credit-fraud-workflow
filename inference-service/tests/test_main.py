#!/usr/bin/env python3
"""
Comprehensive tests for FastAPI Fraud Detection Inference Service
Tests all endpoints, error handling, and model integration
"""

import pytest
import json
import numpy as np
from unittest.mock import Mock, patch, AsyncMock
from fastapi.testclient import TestClient
from datetime import datetime

# Import the application
import sys
import os
sys.path.append(os.path.join(os.path.dirname(__file__), '..'))

from app.main import app, model_manager, TransactionFeatures

# Test client
client = TestClient(app)

class TestInferenceService:
    """Test suite for the inference service"""
    
    def setup_method(self):
        """Setup for each test method"""
        # Mock model manager for testing
        self.mock_model = Mock()
        self.mock_model.predict.return_value = np.array([0.75])  # High fraud probability
        
    def test_root_endpoint(self):
        """Test root endpoint returns service information"""
        response = client.get("/")
        assert response.status_code == 200
        
        data = response.json()
        assert data["service"] == "Fraud Detection Inference Service"
        assert data["version"] == "1.0.0"
        assert "health_check" in data
        assert "prediction_endpoint" in data
    
    def test_health_check_healthy(self):
        """Test health check when model is loaded"""
        with patch.object(model_manager, 'get_model_info') as mock_info:
            mock_info.return_value = {
                "status": "loaded",
                "version": "v_20231201_120000",
                "last_loaded": "2023-12-01T12:00:00",
                "feature_count": 35
            }
            
            response = client.get("/health")
            assert response.status_code == 200
            
            data = response.json()
            assert data["status"] == "healthy"
            assert data["model_status"] == "loaded"
            assert "uptime_seconds" in data
            assert "timestamp" in data
    
    def test_health_check_model_not_loaded(self):
        """Test health check when model is not loaded"""
        with patch.object(model_manager, 'get_model_info') as mock_info, \
             patch.object(model_manager, 'load_model_from_s3') as mock_load:
            
            # First call returns not loaded
            mock_info.side_effect = [
                {"status": "not_loaded"},
                {"status": "loaded", "version": "v_test"}  # After reload attempt
            ]
            mock_load.return_value = True
            
            response = client.get("/health")
            assert response.status_code == 200
            
            data = response.json()
            assert data["status"] == "healthy"  # Should be healthy after reload
    
    def test_single_prediction_success(self):
        """Test successful single transaction prediction"""
        # Mock model manager
        with patch.object(model_manager, 'is_model_loaded') as mock_loaded, \
             patch.object(model_manager, 'predict') as mock_predict, \
             patch.object(model_manager, 'feature_names', []), \
             patch.object(model_manager, 'model_version', 'v_test'):
            
            mock_loaded.return_value = True
            mock_predict.return_value = np.array([0.85])  # High fraud probability
            
            # Create test transaction
            transaction_data = {
                "TX_AMOUNT": 1500.0,
                "yyyy": 2023,
                "mm": 12,
                "dd": 1,
                "CUSTOMER_ID_index": 123.0,
                "TERMINAL_ID_index": 456.0,
                "customer_id_nb_txns_15min_window": 5.0,
                "customer_id_avg_amt_15min_window": 200.0,
                "terminal_id_nb_txns_15min_window": 10.0,
                "terminal_id_avg_amt_15min_window": 150.0
            }
            
            response = client.post("/predict", json=transaction_data)
            assert response.status_code == 200
            
            data = response.json()
            assert data["fraud_probability"] == 0.85
            assert data["is_fraud"] == True
            assert data["model_version"] == "v_test"
            assert "prediction_timestamp" in data
    
    def test_single_prediction_model_not_loaded(self):
        """Test prediction when model is not loaded"""
        with patch.object(model_manager, 'is_model_loaded') as mock_loaded:
            mock_loaded.return_value = False
            
            transaction_data = {
                "TX_AMOUNT": 100.0,
                "yyyy": 2023,
                "mm": 12,
                "dd": 1,
                "CUSTOMER_ID_index": 123.0,
                "TERMINAL_ID_index": 456.0
            }
            
            response = client.post("/predict", json=transaction_data)
            assert response.status_code == 503
            assert "Model not loaded" in response.json()["message"]
    
    def test_batch_prediction_success(self):
        """Test successful batch prediction"""
        with patch.object(model_manager, 'is_model_loaded') as mock_loaded, \
             patch.object(model_manager, 'predict') as mock_predict, \
             patch.object(model_manager, 'feature_names', []), \
             patch.object(model_manager, 'model_version', 'v_test'):
            
            mock_loaded.return_value = True
            mock_predict.return_value = np.array([0.2, 0.8, 0.1])  # Mixed predictions
            
            # Create batch of transactions
            batch_data = {
                "transactions": [
                    {
                        "TX_AMOUNT": 50.0,
                        "yyyy": 2023,
                        "mm": 12,
                        "dd": 1,
                        "CUSTOMER_ID_index": 123.0,
                        "TERMINAL_ID_index": 456.0
                    },
                    {
                        "TX_AMOUNT": 2000.0,
                        "yyyy": 2023,
                        "mm": 12,
                        "dd": 1,
                        "CUSTOMER_ID_index": 124.0,
                        "TERMINAL_ID_index": 457.0
                    },
                    {
                        "TX_AMOUNT": 25.0,
                        "yyyy": 2023,
                        "mm": 12,
                        "dd": 1,
                        "CUSTOMER_ID_index": 125.0,
                        "TERMINAL_ID_index": 458.0
                    }
                ]
            }
            
            response = client.post("/predict/batch", json=batch_data)
            assert response.status_code == 200
            
            data = response.json()
            assert data["batch_size"] == 3
            assert len(data["predictions"]) == 3
            assert data["predictions"][0]["fraud_probability"] == 0.2
            assert data["predictions"][0]["is_fraud"] == False
            assert data["predictions"][1]["fraud_probability"] == 0.8
            assert data["predictions"][1]["is_fraud"] == True
            assert data["predictions"][2]["fraud_probability"] == 0.1
            assert data["predictions"][2]["is_fraud"] == False
            assert "processing_time_ms" in data
    
    def test_batch_prediction_empty_batch(self):
        """Test batch prediction with empty batch"""
        batch_data = {"transactions": []}
        
        response = client.post("/predict/batch", json=batch_data)
        assert response.status_code == 422  # Validation error
    
    def test_batch_prediction_oversized_batch(self):
        """Test batch prediction with oversized batch"""
        # Create batch with too many transactions
        transactions = []
        for i in range(1001):  # Exceeds limit of 1000
            transactions.append({
                "TX_AMOUNT": 100.0,
                "yyyy": 2023,
                "mm": 12,
                "dd": 1,
                "CUSTOMER_ID_index": float(i),
                "TERMINAL_ID_index": float(i)
            })
        
        batch_data = {"transactions": transactions}
        
        response = client.post("/predict/batch", json=batch_data)
        assert response.status_code == 422  # Validation error
    
    def test_model_reload_endpoint(self):
        """Test model reload endpoint"""
        with patch.object(model_manager, 'load_model_from_s3') as mock_load:
            mock_load.return_value = True
            
            response = client.post("/model/reload")
            assert response.status_code == 200
            
            data = response.json()
            assert "Model reload initiated" in data["message"]
            assert "timestamp" in data
    
    def test_model_info_endpoint(self):
        """Test model info endpoint"""
        with patch.object(model_manager, 'get_model_info') as mock_info:
            mock_info.return_value = {
                "status": "loaded",
                "version": "v_20231201_120000",
                "last_loaded": "2023-12-01T12:00:00",
                "feature_count": 35,
                "metadata": {"training_auc": 0.95}
            }
            
            response = client.get("/model/info")
            assert response.status_code == 200
            
            data = response.json()
            assert data["status"] == "loaded"
            assert data["version"] == "v_20231201_120000"
            assert data["feature_count"] == 35
    
    def test_transaction_validation_negative_amount(self):
        """Test transaction validation with negative amount"""
        transaction_data = {
            "TX_AMOUNT": -100.0,  # Invalid negative amount
            "yyyy": 2023,
            "mm": 12,
            "dd": 1,
            "CUSTOMER_ID_index": 123.0,
            "TERMINAL_ID_index": 456.0
        }
        
        response = client.post("/predict", json=transaction_data)
        assert response.status_code == 422  # Validation error
    
    def test_transaction_validation_excessive_amount(self):
        """Test transaction validation with excessive amount"""
        transaction_data = {
            "TX_AMOUNT": 2000000.0,  # Exceeds maximum
            "yyyy": 2023,
            "mm": 12,
            "dd": 1,
            "CUSTOMER_ID_index": 123.0,
            "TERMINAL_ID_index": 456.0
        }
        
        response = client.post("/predict", json=transaction_data)
        assert response.status_code == 422  # Validation error
    
    def test_transaction_validation_invalid_date(self):
        """Test transaction validation with invalid date"""
        transaction_data = {
            "TX_AMOUNT": 100.0,
            "yyyy": 2023,
            "mm": 13,  # Invalid month
            "dd": 1,
            "CUSTOMER_ID_index": 123.0,
            "TERMINAL_ID_index": 456.0
        }
        
        response = client.post("/predict", json=transaction_data)
        assert response.status_code == 422  # Validation error
    
    def test_prediction_error_handling(self):
        """Test error handling during prediction"""
        with patch.object(model_manager, 'is_model_loaded') as mock_loaded, \
             patch.object(model_manager, 'predict') as mock_predict:
            
            mock_loaded.return_value = True
            mock_predict.side_effect = Exception("Model prediction failed")
            
            transaction_data = {
                "TX_AMOUNT": 100.0,
                "yyyy": 2023,
                "mm": 12,
                "dd": 1,
                "CUSTOMER_ID_index": 123.0,
                "TERMINAL_ID_index": 456.0
            }
            
            response = client.post("/predict", json=transaction_data)
            assert response.status_code == 500
            assert "Prediction failed" in response.json()["message"]

class TestTransactionFeatures:
    """Test suite for TransactionFeatures model"""
    
    def test_valid_transaction_features(self):
        """Test valid transaction features creation"""
        features = TransactionFeatures(
            TX_AMOUNT=150.0,
            yyyy=2023,
            mm=12,
            dd=1,
            CUSTOMER_ID_index=123.0,
            TERMINAL_ID_index=456.0
        )
        
        assert features.TX_AMOUNT == 150.0
        assert features.yyyy == 2023
        assert features.mm == 12
        assert features.dd == 1
        assert features.CUSTOMER_ID_index == 123.0
        assert features.TERMINAL_ID_index == 456.0
    
    def test_transaction_features_to_array(self):
        """Test conversion to feature array"""
        features = TransactionFeatures(
            TX_AMOUNT=150.0,
            yyyy=2023,
            mm=12,
            dd=1,
            CUSTOMER_ID_index=123.0,
            TERMINAL_ID_index=456.0,
            customer_id_nb_txns_15min_window=5.0,
            customer_id_avg_amt_15min_window=200.0
        )
        
        # Test without feature names
        array = features.to_feature_array()
        assert array.shape[0] == 1  # Single sample
        assert array.dtype == np.float32
        
        # Test with feature names
        feature_names = ["TX_AMOUNT", "yyyy", "CUSTOMER_ID_index", "missing_feature"]
        array = features.to_feature_array(feature_names)
        assert array.shape == (1, 4)
        assert array[0, 0] == 150.0  # TX_AMOUNT
        assert array[0, 1] == 2023.0  # yyyy
        assert array[0, 2] == 123.0  # CUSTOMER_ID_index
        assert array[0, 3] == 0.0  # missing_feature (default)
    
    def test_transaction_features_validation(self):
        """Test transaction features validation"""
        # Test negative amount validation
        with pytest.raises(ValueError, match="Transaction amount must be non-negative"):
            TransactionFeatures(
                TX_AMOUNT=-100.0,
                yyyy=2023,
                mm=12,
                dd=1,
                CUSTOMER_ID_index=123.0,
                TERMINAL_ID_index=456.0
            )
        
        # Test excessive amount validation
        with pytest.raises(ValueError, match="Transaction amount exceeds maximum"):
            TransactionFeatures(
                TX_AMOUNT=2000000.0,
                yyyy=2023,
                mm=12,
                dd=1,
                CUSTOMER_ID_index=123.0,
                TERMINAL_ID_index=456.0
            )

class TestModelManager:
    """Test suite for ModelManager"""
    
    @pytest.fixture
    def model_manager_instance(self):
        """Create a ModelManager instance for testing"""
        from app.main import ModelManager
        return ModelManager()
    
    def test_model_manager_initialization(self, model_manager_instance):
        """Test ModelManager initialization"""
        assert model_manager_instance.model is None
        assert model_manager_instance.model_metadata is None
        assert model_manager_instance.feature_names is None
        assert model_manager_instance.model_version is None
        assert model_manager_instance.last_loaded is None
    
    def test_is_model_loaded(self, model_manager_instance):
        """Test model loaded check"""
        assert not model_manager_instance.is_model_loaded()
        
        # Mock loaded model
        model_manager_instance.model = Mock()
        assert model_manager_instance.is_model_loaded()
    
    def test_get_model_info_not_loaded(self, model_manager_instance):
        """Test get model info when not loaded"""
        info = model_manager_instance.get_model_info()
        assert info["status"] == "not_loaded"
    
    def test_get_model_info_loaded(self, model_manager_instance):
        """Test get model info when loaded"""
        # Mock loaded model
        model_manager_instance.model = Mock()
        model_manager_instance.model_version = "v_test"
        model_manager_instance.last_loaded = datetime.now()
        model_manager_instance.feature_names = ["feature1", "feature2"]
        model_manager_instance.model_metadata = {"test": "data"}
        
        info = model_manager_instance.get_model_info()
        assert info["status"] == "loaded"
        assert info["version"] == "v_test"
        assert info["feature_count"] == 2
        assert "last_loaded" in info
        assert info["metadata"] == {"test": "data"}

if __name__ == "__main__":
    pytest.main([__file__, "-v"])