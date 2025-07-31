#!/usr/bin/env python3
"""
FastAPI-based Inference Service for XGBoost Fraud Detection Model
EMR to EKS Migration - Task 7 Implementation

This service provides REST API endpoints for fraud detection predictions
using XGBoost models trained on EKS with Ray, implementing requirements 3.1 and 3.2.

Features:
- Model loading from S3 using existing patterns
- REST API endpoints for fraud detection predictions  
- Health check endpoints and comprehensive error handling
- Auto-scaling compatible design
- Prometheus metrics integration
"""

import os
import sys
import json
import logging
import asyncio
import traceback
from typing import Dict, List, Optional, Any
from datetime import datetime
from contextlib import asynccontextmanager

import uvicorn
import numpy as np
import pandas as pd
import xgboost as xgb
import boto3
from botocore.exceptions import ClientError, NoCredentialsError
from fastapi import FastAPI, HTTPException, Request, BackgroundTasks
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field, validator
from prometheus_client import Counter, Histogram, Gauge, generate_latest
from prometheus_fastapi_instrumentator import Instrumentator

# Configure comprehensive logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

# Prometheus metrics
PREDICTION_COUNTER = Counter('fraud_predictions_total', 'Total number of predictions made', ['model_version', 'prediction'])
PREDICTION_LATENCY = Histogram('fraud_prediction_duration_seconds', 'Time spent on predictions')
MODEL_LOAD_COUNTER = Counter('model_loads_total', 'Total number of model loads', ['status'])
ACTIVE_REQUESTS = Gauge('fraud_active_requests', 'Number of active prediction requests')
MODEL_VERSION_GAUGE = Gauge('fraud_model_version_info', 'Current model version info', ['version', 'timestamp'])

class ModelManager:
    """
    Manages XGBoost model loading from S3 using existing EMR Spark RAPIDS patterns
    Implements requirement 3.2: Model loading from S3 using existing patterns
    """
    
    def __init__(self):
        self.model: Optional[xgb.Booster] = None
        self.model_metadata: Optional[Dict[str, Any]] = None
        self.feature_names: Optional[List[str]] = None
        self.model_version: Optional[str] = None
        self.last_loaded: Optional[datetime] = None
        
        # S3 configuration using existing patterns
        self.s3_client = boto3.client('s3')
        self.s3_bucket = os.getenv('MODEL_S3_BUCKET', 'your-fraud-models-bucket')
        self.model_prefix = os.getenv('MODEL_S3_PREFIX', 'models/xgboost')
        self.model_path = os.getenv('MODEL_S3_PATH', f's3://{self.s3_bucket}/{self.model_prefix}/latest/model.xgb')
        
        logger.info(f"ModelManager initialized with S3 path: {self.model_path}")
    
    async def load_model_from_s3(self) -> bool:
        """
        Load XGBoost model from S3 using existing EMR Spark RAPIDS patterns
        Returns True if successful, False otherwise
        """
        try:
            logger.info(f"Loading model from S3: {self.model_path}")
            
            # Parse S3 path
            if not self.model_path.startswith('s3://'):
                raise ValueError(f"Invalid S3 path format: {self.model_path}")
            
            path_parts = self.model_path[5:].split('/', 1)
            bucket = path_parts[0]
            key = path_parts[1]
            
            # Download model file
            local_model_path = '/tmp/model.xgb'
            self.s3_client.download_file(bucket, key, local_model_path)
            
            # Load XGBoost model
            self.model = xgb.Booster()
            self.model.load_model(local_model_path)
            
            # Load metadata if available
            metadata_key = key.replace('model.xgb', 'model_metadata.json')
            try:
                local_metadata_path = '/tmp/model_metadata.json'
                self.s3_client.download_file(bucket, metadata_key, local_metadata_path)
                
                with open(local_metadata_path, 'r') as f:
                    self.model_metadata = json.load(f)
                    self.feature_names = self.model_metadata.get('feature_names', [])
                    self.model_version = self.model_metadata.get('model_version', 'unknown')
                    
                logger.info(f"Loaded model metadata: version {self.model_version}")
                
            except ClientError as e:
                logger.warning(f"Could not load model metadata: {e}")
                self.model_metadata = {}
                self.feature_names = []
                self.model_version = 'unknown'
            
            self.last_loaded = datetime.now()
            
            # Update Prometheus metrics
            MODEL_LOAD_COUNTER.labels(status='success').inc()
            if self.model_version != 'unknown':
                MODEL_VERSION_GAUGE.labels(
                    version=self.model_version,
                    timestamp=self.last_loaded.isoformat()
                ).set(1)
            
            # Cleanup temporary files
            if os.path.exists(local_model_path):
                os.remove(local_model_path)
            if os.path.exists(local_metadata_path):
                os.remove(local_metadata_path)
            
            logger.info(f"Model loaded successfully: version {self.model_version}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to load model from S3: {str(e)}")
            logger.error(traceback.format_exc())
            MODEL_LOAD_COUNTER.labels(status='error').inc()
            return False
    
    def is_model_loaded(self) -> bool:
        """Check if model is loaded and ready for predictions"""
        return self.model is not None
    
    def get_model_info(self) -> Dict[str, Any]:
        """Get information about the loaded model"""
        if not self.is_model_loaded():
            return {"status": "not_loaded"}
        
        return {
            "status": "loaded",
            "version": self.model_version,
            "last_loaded": self.last_loaded.isoformat() if self.last_loaded else None,
            "feature_count": len(self.feature_names) if self.feature_names else 0,
            "metadata": self.model_metadata
        }
    
    async def predict(self, features: np.ndarray) -> np.ndarray:
        """
        Make predictions using the loaded model
        
        Args:
            features: Input features as numpy array
            
        Returns:
            Prediction probabilities
        """
        if not self.is_model_loaded():
            raise ValueError("Model not loaded")
        
        try:
            # Create DMatrix for XGBoost
            dmatrix = xgb.DMatrix(features)
            
            # Make predictions
            predictions = self.model.predict(dmatrix)
            
            return predictions
            
        except Exception as e:
            logger.error(f"Prediction failed: {str(e)}")
            raise

# Global model manager instance
model_manager = ModelManager()

# Pydantic models for API
class TransactionFeatures(BaseModel):
    """
    Transaction features for fraud detection prediction
    Based on the feature engineering output from EMR Spark RAPIDS pipeline
    """
    
    # Basic transaction info
    TX_AMOUNT: float = Field(..., description="Transaction amount", ge=0)
    yyyy: int = Field(..., description="Year", ge=2020, le=2030)
    mm: int = Field(..., description="Month", ge=1, le=12)
    dd: int = Field(..., description="Day", ge=1, le=31)
    
    # Customer features (using indexed values from feature engineering)
    CUSTOMER_ID_index: float = Field(..., description="Customer ID index")
    customer_name_index: Optional[float] = Field(0, description="Customer name index")
    customer_email_index: Optional[float] = Field(0, description="Customer email index")
    phone_index: Optional[float] = Field(0, description="Phone index")
    billing_zip: Optional[float] = Field(0, description="Billing ZIP code")
    billing_city_index: Optional[float] = Field(0, description="Billing city index")
    billing_state_index: Optional[float] = Field(0, description="Billing state index")
    x_customer_id: Optional[float] = Field(0, description="Customer X coordinate")
    y_customer_id: Optional[float] = Field(0, description="Customer Y coordinate")
    
    # Terminal features
    TERMINAL_ID_index: float = Field(..., description="Terminal ID index")
    merchant_index: Optional[float] = Field(0, description="Merchant index")
    
    # Customer window features (15min, 30min, 60min, 1day, 7day, 15day, 30day)
    customer_id_nb_txns_15min_window: Optional[float] = Field(0, description="Customer transactions in 15min window")
    customer_id_nb_txns_30min_window: Optional[float] = Field(0, description="Customer transactions in 30min window")
    customer_id_nb_txns_60min_window: Optional[float] = Field(0, description="Customer transactions in 60min window")
    customer_id_nb_txns_1day_window: Optional[float] = Field(0, description="Customer transactions in 1day window")
    customer_id_nb_txns_7day_window: Optional[float] = Field(0, description="Customer transactions in 7day window")
    customer_id_nb_txns_15day_window: Optional[float] = Field(0, description="Customer transactions in 15day window")
    customer_id_nb_txns_30day_window: Optional[float] = Field(0, description="Customer transactions in 30day window")
    
    customer_id_avg_amt_15min_window: Optional[float] = Field(0, description="Customer avg amount in 15min window")
    customer_id_avg_amt_30min_window: Optional[float] = Field(0, description="Customer avg amount in 30min window")
    customer_id_avg_amt_60min_window: Optional[float] = Field(0, description="Customer avg amount in 60min window")
    customer_id_avg_amt_1day_window: Optional[float] = Field(0, description="Customer avg amount in 1day window")
    customer_id_avg_amt_7day_window: Optional[float] = Field(0, description="Customer avg amount in 7day window")
    customer_id_avg_amt_15day_window: Optional[float] = Field(0, description="Customer avg amount in 15day window")
    customer_id_avg_amt_30day_window: Optional[float] = Field(0, description="Customer avg amount in 30day window")
    
    # Terminal window features
    terminal_id_nb_txns_15min_window: Optional[float] = Field(0, description="Terminal transactions in 15min window")
    terminal_id_nb_txns_30min_window: Optional[float] = Field(0, description="Terminal transactions in 30min window")
    terminal_id_nb_txns_60min_window: Optional[float] = Field(0, description="Terminal transactions in 60min window")
    terminal_id_nb_txns_1day_window: Optional[float] = Field(0, description="Terminal transactions in 1day window")
    terminal_id_nb_txns_7day_window: Optional[float] = Field(0, description="Terminal transactions in 7day window")
    terminal_id_nb_txns_15day_window: Optional[float] = Field(0, description="Terminal transactions in 15day window")
    terminal_id_nb_txns_30day_window: Optional[float] = Field(0, description="Terminal transactions in 30day window")
    
    terminal_id_avg_amt_15min_window: Optional[float] = Field(0, description="Terminal avg amount in 15min window")
    terminal_id_avg_amt_30min_window: Optional[float] = Field(0, description="Terminal avg amount in 30min window")
    terminal_id_avg_amt_60min_window: Optional[float] = Field(0, description="Terminal avg amount in 60min window")
    terminal_id_avg_amt_1day_window: Optional[float] = Field(0, description="Terminal avg amount in 1day window")
    terminal_id_avg_amt_7day_window: Optional[float] = Field(0, description="Terminal avg amount in 7day window")
    terminal_id_avg_amt_15day_window: Optional[float] = Field(0, description="Terminal avg amount in 15day window")
    terminal_id_avg_amt_30day_window: Optional[float] = Field(0, description="Terminal avg amount in 30day window")
    
    @validator('TX_AMOUNT')
    def validate_amount(cls, v):
        if v < 0:
            raise ValueError('Transaction amount must be non-negative')
        if v > 1000000:  # Reasonable upper limit
            raise ValueError('Transaction amount exceeds maximum allowed value')
        return v
    
    def to_feature_array(self, feature_names: Optional[List[str]] = None) -> np.ndarray:
        """
        Convert to numpy array for model prediction
        
        Args:
            feature_names: Expected feature names from model
            
        Returns:
            Feature array ready for prediction
        """
        # Get all feature values as dict
        feature_dict = self.dict()
        
        if feature_names:
            # Use model's expected feature order
            features = []
            for name in feature_names:
                if name in feature_dict:
                    features.append(feature_dict[name])
                else:
                    logger.warning(f"Missing feature {name}, using default value 0")
                    features.append(0.0)
            return np.array([features], dtype=np.float32)
        else:
            # Use all features in order
            return np.array([list(feature_dict.values())], dtype=np.float32)

class BatchTransactionFeatures(BaseModel):
    """Batch prediction request"""
    transactions: List[TransactionFeatures] = Field(..., description="List of transactions to predict")
    
    @validator('transactions')
    def validate_batch_size(cls, v):
        if len(v) == 0:
            raise ValueError('Batch must contain at least one transaction')
        if len(v) > 1000:  # Reasonable batch size limit
            raise ValueError('Batch size exceeds maximum allowed (1000)')
        return v

class PredictionResponse(BaseModel):
    """Single prediction response"""
    fraud_probability: float = Field(..., description="Probability of fraud (0-1)")
    is_fraud: bool = Field(..., description="Binary fraud prediction (threshold 0.5)")
    model_version: str = Field(..., description="Model version used for prediction")
    prediction_timestamp: str = Field(..., description="Timestamp of prediction")

class BatchPredictionResponse(BaseModel):
    """Batch prediction response"""
    predictions: List[PredictionResponse] = Field(..., description="List of predictions")
    batch_size: int = Field(..., description="Number of predictions in batch")
    model_version: str = Field(..., description="Model version used for predictions")
    processing_time_ms: float = Field(..., description="Total processing time in milliseconds")

class HealthResponse(BaseModel):
    """Health check response"""
    status: str = Field(..., description="Service status")
    model_status: str = Field(..., description="Model loading status")
    model_info: Dict[str, Any] = Field(..., description="Model information")
    uptime_seconds: float = Field(..., description="Service uptime in seconds")
    timestamp: str = Field(..., description="Current timestamp")

# Application lifecycle management
@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Application lifecycle management
    Load model on startup and cleanup on shutdown
    """
    # Startup
    logger.info("Starting fraud detection inference service...")
    
    # Load model from S3
    success = await model_manager.load_model_from_s3()
    if not success:
        logger.error("Failed to load model on startup")
        # Continue anyway - model can be loaded later via health check
    
    # Store startup time
    app.state.startup_time = datetime.now()
    
    yield
    
    # Shutdown
    logger.info("Shutting down fraud detection inference service...")

# Create FastAPI application
app = FastAPI(
    title="Fraud Detection Inference Service",
    description="XGBoost-based fraud detection inference service for EMR to EKS migration",
    version="1.0.0",
    lifespan=lifespan
)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure appropriately for production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Add Prometheus instrumentation
instrumentator = Instrumentator()
instrumentator.instrument(app).expose(app)

# Exception handlers
@app.exception_handler(Exception)
async def general_exception_handler(request: Request, exc: Exception):
    """
    Global exception handler with comprehensive error logging
    Implements requirement 3.1: Error handling
    """
    logger.error(f"Unhandled exception in {request.method} {request.url}: {str(exc)}")
    logger.error(traceback.format_exc())
    
    return JSONResponse(
        status_code=500,
        content={
            "error": "Internal server error",
            "message": "An unexpected error occurred during processing",
            "timestamp": datetime.now().isoformat(),
            "request_id": getattr(request.state, 'request_id', 'unknown')
        }
    )

@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException):
    """HTTP exception handler with detailed logging"""
    logger.warning(f"HTTP exception in {request.method} {request.url}: {exc.status_code} - {exc.detail}")
    
    return JSONResponse(
        status_code=exc.status_code,
        content={
            "error": "Request error",
            "message": exc.detail,
            "status_code": exc.status_code,
            "timestamp": datetime.now().isoformat()
        }
    )

# Middleware for request tracking
@app.middleware("http")
async def track_requests(request: Request, call_next):
    """Middleware to track active requests and add request IDs"""
    import uuid
    
    request_id = str(uuid.uuid4())
    request.state.request_id = request_id
    
    ACTIVE_REQUESTS.inc()
    start_time = datetime.now()
    
    try:
        response = await call_next(request)
        return response
    finally:
        ACTIVE_REQUESTS.dec()
        duration = (datetime.now() - start_time).total_seconds()
        logger.info(f"Request {request_id} completed in {duration:.3f}s")

# API Endpoints

@app.get("/", response_model=Dict[str, str])
async def root():
    """Root endpoint with service information"""
    return {
        "service": "Fraud Detection Inference Service",
        "version": "1.0.0",
        "description": "XGBoost-based fraud detection for EMR to EKS migration",
        "health_check": "/health",
        "prediction_endpoint": "/predict",
        "batch_prediction_endpoint": "/predict/batch",
        "metrics": "/metrics"
    }

@app.get("/health", response_model=HealthResponse)
async def health_check():
    """
    Comprehensive health check endpoint
    Implements requirement 3.1: Health check endpoints
    """
    try:
        # Calculate uptime
        uptime = (datetime.now() - app.state.startup_time).total_seconds()
        
        # Check model status
        model_info = model_manager.get_model_info()
        model_status = model_info["status"]
        
        # Determine overall status
        if model_status == "loaded":
            status = "healthy"
        elif model_status == "not_loaded":
            status = "degraded"
            # Try to reload model
            logger.info("Model not loaded, attempting to reload...")
            await model_manager.load_model_from_s3()
            model_info = model_manager.get_model_info()
            if model_info["status"] == "loaded":
                status = "healthy"
        else:
            status = "unhealthy"
        
        return HealthResponse(
            status=status,
            model_status=model_status,
            model_info=model_info,
            uptime_seconds=uptime,
            timestamp=datetime.now().isoformat()
        )
        
    except Exception as e:
        logger.error(f"Health check failed: {str(e)}")
        raise HTTPException(status_code=500, detail="Health check failed")

@app.post("/predict", response_model=PredictionResponse)
async def predict_fraud(transaction: TransactionFeatures):
    """
    Single transaction fraud prediction endpoint
    Implements requirement 3.1: REST API endpoints for fraud detection predictions
    """
    if not model_manager.is_model_loaded():
        raise HTTPException(status_code=503, detail="Model not loaded")
    
    try:
        with PREDICTION_LATENCY.time():
            # Convert transaction to feature array
            features = transaction.to_feature_array(model_manager.feature_names)
            
            # Make prediction
            prediction_proba = await model_manager.predict(features)
            fraud_probability = float(prediction_proba[0])
            is_fraud = fraud_probability > 0.5
            
            # Update metrics
            PREDICTION_COUNTER.labels(
                model_version=model_manager.model_version,
                prediction='fraud' if is_fraud else 'legitimate'
            ).inc()
            
            return PredictionResponse(
                fraud_probability=fraud_probability,
                is_fraud=is_fraud,
                model_version=model_manager.model_version,
                prediction_timestamp=datetime.now().isoformat()
            )
            
    except Exception as e:
        logger.error(f"Prediction failed: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Prediction failed: {str(e)}")

@app.post("/predict/batch", response_model=BatchPredictionResponse)
async def predict_fraud_batch(batch: BatchTransactionFeatures):
    """
    Batch transaction fraud prediction endpoint
    Implements requirement 3.1: REST API endpoints for fraud detection predictions
    """
    if not model_manager.is_model_loaded():
        raise HTTPException(status_code=503, detail="Model not loaded")
    
    start_time = datetime.now()
    
    try:
        with PREDICTION_LATENCY.time():
            # Convert all transactions to feature arrays
            feature_arrays = []
            for transaction in batch.transactions:
                features = transaction.to_feature_array(model_manager.feature_names)
                feature_arrays.append(features[0])  # Remove batch dimension
            
            # Combine into single array for batch prediction
            batch_features = np.array(feature_arrays, dtype=np.float32)
            
            # Make batch prediction
            prediction_probas = await model_manager.predict(batch_features)
            
            # Create response for each prediction
            predictions = []
            for i, prob in enumerate(prediction_probas):
                fraud_probability = float(prob)
                is_fraud = fraud_probability > 0.5
                
                predictions.append(PredictionResponse(
                    fraud_probability=fraud_probability,
                    is_fraud=is_fraud,
                    model_version=model_manager.model_version,
                    prediction_timestamp=datetime.now().isoformat()
                ))
                
                # Update metrics
                PREDICTION_COUNTER.labels(
                    model_version=model_manager.model_version,
                    prediction='fraud' if is_fraud else 'legitimate'
                ).inc()
            
            processing_time = (datetime.now() - start_time).total_seconds() * 1000
            
            return BatchPredictionResponse(
                predictions=predictions,
                batch_size=len(predictions),
                model_version=model_manager.model_version,
                processing_time_ms=processing_time
            )
            
    except Exception as e:
        logger.error(f"Batch prediction failed: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Batch prediction failed: {str(e)}")

@app.post("/model/reload")
async def reload_model(background_tasks: BackgroundTasks):
    """
    Endpoint to trigger model reload from S3
    Useful for updating to new model versions
    """
    async def reload_task():
        logger.info("Reloading model from S3...")
        success = await model_manager.load_model_from_s3()
        if success:
            logger.info("Model reloaded successfully")
        else:
            logger.error("Model reload failed")
    
    background_tasks.add_task(reload_task)
    
    return {
        "message": "Model reload initiated",
        "timestamp": datetime.now().isoformat()
    }

@app.get("/model/info")
async def get_model_info():
    """Get detailed information about the loaded model"""
    return model_manager.get_model_info()

# Development server
if __name__ == "__main__":
    # Configuration from environment variables
    host = os.getenv("HOST", "0.0.0.0")
    port = int(os.getenv("PORT", "8000"))
    log_level = os.getenv("LOG_LEVEL", "info")
    
    logger.info(f"Starting inference service on {host}:{port}")
    
    uvicorn.run(
        "main:app",
        host=host,
        port=port,
        log_level=log_level,
        reload=False  # Disable reload in production
    )