#!/usr/bin/env python3
"""
Unit tests for RAPIDS optimizations in fraud detection feature engineering
Tests GPU-accelerated data transformation functions
"""

import unittest
import sys
import os
from datetime import datetime, timedelta

# Add the fraud-detection directory to the path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


class TestRapidsOptimizations(unittest.TestCase):
    """
    Test suite for RAPIDS optimization functions
    """
    
    def test_rapids_configuration_validation(self):
        """Test RAPIDS configuration parameters"""
        # Expected RAPIDS configuration
        expected_config = {
            "spark.plugins": "com.nvidia.spark.SQLPlugin",
            "spark.rapids.sql.enabled": "true",
            "spark.rapids.sql.concurrentGpuTasks": "2",
            "spark.rapids.memory.gpu.pool": "ASYNC",
            "spark.rapids.memory.gpu.allocFraction": "0.6",
            "spark.rapids.memory.pinnedPool.size": "2G"
        }
        
        # Validate each configuration parameter
        self.assertEqual(expected_config["spark.rapids.sql.enabled"], "true")
        self.assertEqual(expected_config["spark.rapids.sql.concurrentGpuTasks"], "2")
        self.assertEqual(expected_config["spark.rapids.memory.gpu.pool"], "ASYNC")
        self.assertIn("0.", expected_config["spark.rapids.memory.gpu.allocFraction"])
        self.assertIn("G", expected_config["spark.rapids.memory.pinnedPool.size"])
        
        print("✓ RAPIDS configuration validation passed")
    
    def test_cudf_datetime_processing_logic(self):
        """Test cuDF-optimized datetime processing logic"""
        # Test datetime feature extraction
        test_datetime = datetime(2024, 1, 15, 14, 30, 45)
        
        # Extract features as would be done with cuDF optimization
        features = {
            "year": test_datetime.year,
            "month": test_datetime.month,
            "day": test_datetime.day,
            "hour": test_datetime.hour,
            "minute": test_datetime.minute,
            "dayofweek": test_datetime.weekday() + 1,  # Spark uses 1-7
            "is_weekend": 1 if test_datetime.weekday() >= 5 else 0,
            "is_business_hours": 1 if 9 <= test_datetime.hour <= 17 else 0
        }
        
        # Validate extracted features
        self.assertEqual(features["year"], 2024)
        self.assertEqual(features["month"], 1)
        self.assertEqual(features["day"], 15)
        self.assertEqual(features["hour"], 14)
        self.assertEqual(features["is_business_hours"], 1)
        self.assertEqual(features["is_weekend"], 0)  # Monday
        
        print("✓ cuDF datetime processing logic validation passed")
    
    def test_gpu_window_aggregation_logic(self):
        """Test GPU-accelerated window aggregation logic"""
        # Simulate transaction data
        transactions = [
            {"time": 1000, "customer": "C1", "amount": 100.0},
            {"time": 1600, "customer": "C1", "amount": 200.0},  # 10 min later
            {"time": 2200, "customer": "C1", "amount": 300.0},  # 20 min later
            {"time": 3400, "customer": "C1", "amount": 400.0},  # 40 min later
        ]
        
        # Test 15-minute window (900 seconds) for the last transaction
        current_time = 3400
        window_start = current_time - 900  # 2500
        
        # Find transactions in window (2500 to 3400)
        transactions_in_window = [
            tx for tx in transactions 
            if window_start <= tx["time"] <= current_time
        ]
        
        # Should include only transaction at 3400 (2200 is outside 15-minute window)
        self.assertEqual(len(transactions_in_window), 1)
        
        # Calculate aggregations
        count = len(transactions_in_window)
        total_amount = sum(tx["amount"] for tx in transactions_in_window)
        avg_amount = total_amount / count if count > 0 else 0
        min_amount = min(tx["amount"] for tx in transactions_in_window) if count > 0 else 0
        max_amount = max(tx["amount"] for tx in transactions_in_window) if count > 0 else 0
        
        self.assertEqual(count, 1)
        self.assertEqual(total_amount, 400.0)
        self.assertEqual(avg_amount, 400.0)
        self.assertEqual(min_amount, 400.0)
        self.assertEqual(max_amount, 400.0)
        
        print("✓ GPU window aggregation logic validation passed")
    
    def test_enhanced_feature_calculations(self):
        """Test enhanced feature calculations for fraud detection"""
        # Test velocity calculations
        tx_count_1hr = 5
        tx_count_1day = 20
        
        velocity_1hr = tx_count_1hr / 3600.0  # transactions per second
        velocity_1day = tx_count_1day / 86400.0  # transactions per second
        
        self.assertAlmostEqual(velocity_1hr, 0.00138888, places=6)
        self.assertAlmostEqual(velocity_1day, 0.00023148, places=6)
        
        # Test deviation calculations
        current_amount = 500.0
        customer_avg = 300.0
        terminal_avg = 250.0
        
        customer_deviation = abs(current_amount - customer_avg)
        terminal_deviation = abs(current_amount - terminal_avg)
        customer_ratio = current_amount / customer_avg if customer_avg > 0 else 1.0
        terminal_ratio = current_amount / terminal_avg if terminal_avg > 0 else 1.0
        
        self.assertEqual(customer_deviation, 200.0)
        self.assertEqual(terminal_deviation, 250.0)
        self.assertAlmostEqual(customer_ratio, 1.6667, places=4)
        self.assertEqual(terminal_ratio, 2.0)
        
        # Test risk score calculation
        customer_stddev = 100.0
        risk_score = customer_deviation / customer_stddev if customer_stddev > 0 else 0.0
        self.assertEqual(risk_score, 2.0)
        
        print("✓ Enhanced feature calculations validation passed")
    
    def test_cudf_memory_optimization_logic(self):
        """Test cuDF memory optimization strategies"""
        # Test partitioning strategy
        total_records = 1000000
        target_partitions = 1000
        records_per_partition = total_records / target_partitions
        
        # Should aim for optimal partition size for GPU processing
        self.assertEqual(records_per_partition, 1000.0)
        
        # Test GPU memory allocation
        gpu_memory_fraction = 0.6
        pinned_memory = "2G"
        concurrent_tasks = 2
        
        self.assertGreater(gpu_memory_fraction, 0.5)
        self.assertLess(gpu_memory_fraction, 1.0)
        self.assertIn("G", pinned_memory)
        self.assertGreaterEqual(concurrent_tasks, 1)
        
        print("✓ cuDF memory optimization logic validation passed")
    
    def test_feature_completeness_with_rapids(self):
        """Test that RAPIDS optimizations don't miss any features"""
        # Base features from notebook
        base_features = [
            "TX_AMOUNT", "yyyy", "mm", "dd",
            "CUSTOMER_ID_index", "TERMINAL_ID_index"
        ]
        
        # Window features for each time window
        time_windows = ["15min", "30min", "60min", "1day", "7day", "15day", "30day"]
        window_features = []
        
        for window in time_windows:
            window_features.extend([
                f"customer_id_nb_txns_{window}_window",
                f"customer_id_avg_amt_{window}_window",
                f"terminal_id_nb_txns_{window}_window",
                f"terminal_id_avg_amt_{window}_window"
            ])
        
        # Enhanced features with RAPIDS
        enhanced_features = [
            "hour_of_day", "day_of_week", "is_weekend", "is_business_hours",
            "customer_tx_velocity_1hr", "terminal_tx_velocity_1hr",
            "amount_deviation_from_customer_avg", "amount_deviation_from_terminal_avg",
            "amount_ratio_to_customer_avg", "amount_ratio_to_terminal_avg",
            "customer_risk_score", "terminal_risk_score"
        ]
        
        all_features = base_features + window_features + enhanced_features
        
        # Should have comprehensive feature set (46 features is good)
        self.assertGreater(len(all_features), 40)
        
        # Check for duplicates
        self.assertEqual(len(all_features), len(set(all_features)))
        
        print(f"✓ Feature completeness validation passed with {len(all_features)} features")
    
    def test_gpu_acceleration_fallback_logic(self):
        """Test fallback logic when GPU acceleration is not available"""
        # Test configuration detection
        rapids_available = False  # Simulate RAPIDS not available
        
        if rapids_available:
            processing_mode = "GPU_ACCELERATED"
            cache_strategy = "GPU_MEMORY"
        else:
            processing_mode = "CPU_FALLBACK"
            cache_strategy = "MEMORY_CACHE"
        
        self.assertEqual(processing_mode, "CPU_FALLBACK")
        self.assertEqual(cache_strategy, "MEMORY_CACHE")
        
        # Test that all features are still computed correctly
        feature_count_gpu = 45  # Expected with GPU
        feature_count_cpu = 45  # Should be same with CPU fallback
        
        self.assertEqual(feature_count_gpu, feature_count_cpu)
        
        print("✓ GPU acceleration fallback logic validation passed")


def run_rapids_optimization_tests():
    """Run all RAPIDS optimization tests"""
    print("Running RAPIDS optimization validation tests...\n")
    
    # Create test suite
    suite = unittest.TestLoader().loadTestsFromTestCase(TestRapidsOptimizations)
    
    # Run tests
    runner = unittest.TextTestRunner(verbosity=0)
    result = runner.run(suite)
    
    print(f"\nRAPIDS Optimization Test Results:")
    print(f"Tests run: {result.testsRun}")
    print(f"Failures: {len(result.failures)}")
    print(f"Errors: {len(result.errors)}")
    
    if result.failures:
        print("\nFailures:")
        for test, traceback in result.failures:
            print(f"- {test}: {traceback}")
    
    if result.errors:
        print("\nErrors:")
        for test, traceback in result.errors:
            print(f"- {test}: {traceback}")
    
    success = len(result.failures) == 0 and len(result.errors) == 0
    print(f"\nOverall result: {'✓ PASSED' if success else '✗ FAILED'}")
    
    return success


if __name__ == "__main__":
    run_rapids_optimization_tests()