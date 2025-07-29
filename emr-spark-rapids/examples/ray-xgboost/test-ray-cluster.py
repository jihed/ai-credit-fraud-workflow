#!/usr/bin/env python3
"""
Test script to validate Ray cluster deployment and GPU availability
"""

import ray
import time
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def test_ray_cluster():
    """Test Ray cluster connectivity and resources"""
    try:
        # Initialize Ray cluster connection
        ray.init(address="ray://fraud-training-cluster-head-svc.ray-ml.svc.cluster.local:10001")
        
        logger.info("✅ Successfully connected to Ray cluster")
        
        # Get cluster resources
        resources = ray.cluster_resources()
        logger.info(f"📊 Cluster resources: {resources}")
        
        # Check for GPU availability
        gpu_count = resources.get('GPU', 0)
        cpu_count = resources.get('CPU', 0)
        memory_gb = resources.get('memory', 0) / (1024**3)
        
        logger.info(f"🖥️  Available CPUs: {cpu_count}")
        logger.info(f"🎮 Available GPUs: {gpu_count}")
        logger.info(f"💾 Available Memory: {memory_gb:.2f} GB")
        
        if gpu_count > 0:
            logger.info("✅ GPU resources detected - ready for GPU-accelerated training")
        else:
            logger.warning("⚠️  No GPU resources detected")
        
        # Test remote function execution
        @ray.remote
        def test_function():
            import platform
            import socket
            return {
                'hostname': socket.gethostname(),
                'platform': platform.platform(),
                'python_version': platform.python_version()
            }
        
        # Execute test function on cluster
        future = test_function.remote()
        result = ray.get(future)
        logger.info(f"🧪 Test function executed on: {result}")
        
        # Test GPU function if GPUs are available
        if gpu_count > 0:
            @ray.remote(num_gpus=1)
            def test_gpu_function():
                try:
                    import torch
                    if torch.cuda.is_available():
                        device_count = torch.cuda.device_count()
                        device_name = torch.cuda.get_device_name(0) if device_count > 0 else "Unknown"
                        return {
                            'cuda_available': True,
                            'device_count': device_count,
                            'device_name': device_name
                        }
                    else:
                        return {'cuda_available': False}
                except ImportError:
                    return {'error': 'PyTorch not available'}
            
            try:
                gpu_future = test_gpu_function.remote()
                gpu_result = ray.get(gpu_future, timeout=30)
                logger.info(f"🎮 GPU test result: {gpu_result}")
            except Exception as e:
                logger.warning(f"⚠️  GPU test failed: {str(e)}")
        
        logger.info("✅ Ray cluster test completed successfully")
        return True
        
    except Exception as e:
        logger.error(f"❌ Ray cluster test failed: {str(e)}")
        return False
    finally:
        try:
            ray.shutdown()
        except:
            pass

def test_xgboost_gpu():
    """Test XGBoost GPU functionality"""
    try:
        import xgboost as xgb
        import numpy as np
        
        logger.info("🧪 Testing XGBoost GPU functionality...")
        
        # Create sample data
        X = np.random.random((1000, 10)).astype(np.float32)
        y = np.random.randint(0, 2, 1000)
        
        # Create DMatrix
        dtrain = xgb.DMatrix(X, label=y)
        
        # Test GPU training parameters
        params = {
            'objective': 'binary:logistic',
            'tree_method': 'gpu_hist',
            'gpu_id': 0,
            'max_depth': 3,
            'learning_rate': 0.1
        }
        
        # Train a small model to test GPU functionality
        model = xgb.train(params, dtrain, num_boost_round=10)
        
        # Make predictions
        predictions = model.predict(dtrain)
        
        logger.info(f"✅ XGBoost GPU test successful - predictions shape: {predictions.shape}")
        return True
        
    except Exception as e:
        logger.error(f"❌ XGBoost GPU test failed: {str(e)}")
        return False

if __name__ == "__main__":
    logger.info("🚀 Starting Ray cluster validation tests...")
    
    # Test Ray cluster
    ray_success = test_ray_cluster()
    
    # Test XGBoost GPU (if running on GPU node)
    xgb_success = test_xgboost_gpu()
    
    if ray_success and xgb_success:
        logger.info("🎉 All tests passed! Ray cluster is ready for distributed XGBoost training.")
        exit(0)
    else:
        logger.error("❌ Some tests failed. Please check the cluster configuration.")
        exit(1)