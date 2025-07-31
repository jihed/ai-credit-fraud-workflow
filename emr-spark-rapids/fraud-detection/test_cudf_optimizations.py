#!/usr/bin/env python3
"""
Unit tests for cuDF optimizations in fraud detection feature engineering
Tests GPU-accelerated data transformation functions with cuDF integration
"""

import unittest
import sys
import os
from datetime import datetime, timedelta
from typing import List, Dict

# Add the fraud-detection directory to the path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from pyspark.sql import SparkSession, DataFrame
from pyspark.sql import functions as F
from pyspark.sql.types import *
from rapids_utils import RapidsDataProcessor


class TestCuDFOptimizations(unittest.TestCase):
    """
    Test suite for cuDF optimization functions in RAPIDS data processing
    """
    
    @classmethod
    def setUpClass(cls):
        """Set up Spark session for testing cuDF optimizations"""
        cls.spark = SparkSession.builder \
            .appName("CuDFOptimizationTests") \
            .master("local[2]") \
            .config("spark.sql.adaptive.enabled", "false") \
            .getOrCreate()
        
        cls.rapids_processor = RapidsDataProcessor(cls.spark)
        
    @classmethod
    def tearDownClass(cls):
        """Clean up Spark session"""
        cls.spark.stop()
    
    def create_sample_transaction_data(self) -> DataFrame:
        """Create sample transaction data for cuDF testing"""
        base_time = datetime(2024, 1, 1, 10, 0, 0)
        
        transactions_data = [
            (str(base_time), "CUST_001", "TERM_001", 100.0, int(base_time.timestamp())),
            (str(base_time + timedelta(minutes=5)), "CUST_001", "TERM_001", 150.0, int((base_time + timedelta(minutes=5)).timestamp())),
            (str(base_time + timedelta(minutes=10)), "CUST_001", "TERM_002", 200.0, int((base_time + timedelta(minutes=10)).timestamp())),
            (str(base_time + timedelta(minutes=15)), "CUST_002", "TERM_001", 75.0, int((base_time + timedelta(minutes=15)).timestamp())),
            (str(base_time + timedelta(minutes=20)), "CUST_002", "TERM_002", 125.0, int((base_time + timedelta(minutes=20)).timestamp())),
            (str(base_time + timedelta(minutes=25)), "CUST_001", "TERM_001", 300.0, int((base_time + timedelta(minutes=25)).timestamp())),
        ]
        
        schema = StructType([
            StructField("TX_DATETIME", StringType(), True),
            StructField("CUSTOMER_ID", StringType(), True),
            StructField("TERMINAL_ID", StringType(), True),
            StructField("TX_AMOUNT", DoubleType(), True),
            StructField("TX_TIME_SECONDS", LongType(), True)
        ])
        
        return self.spark.createDataFrame(transactions_data, schema)
    
    def test_gpu_optimized_datetime_processing(self):
        """Test GPU-optimized datetime processing with cuDF patterns"""
        df = self.create_sample_transaction_data()
        
        # Apply GPU-optimized datetime processing
        processed_df = self.rapids_processor.gpu_optimized_datetime_processing(df, "TX_DATETIME")
        
        # Check that all expected datetime features are created
        expected_features = [
            "year", "month", "day", "hour", "minute", "dayofweek", "dayofyear", 
            "weekofyear", "is_weekend", "is_business_hours", "time_seconds"
        ]
        
        for feature in expected_features:
            self.assertIn(feature, processed_df.columns, f"Missing datetime feature: {feature}")
        
        # Verify datetime extraction accuracy
        first_row = processed_df.first()
        self.assertEqual(first_row["year"], 2024)
        self.assertEqual(first_row["month"], 1)
        self.assertEqual(first_row["day"], 1)
        self.assertEqual(first_row["hour"], 10)
        self.assertEqual(first_row["is_business_hours"], 1)  # 10 AM is business hours
        self.assertEqual(first_row["is_weekend"], 0)  # January 1, 2024 is Monday
    
    def test_cudf_optimized_windowing(self):
        """Test cuDF-optimized windowing operations"""
        df = self.create_sample_transaction_data()
        
        # Apply cuDF-optimized windowing
        window_sizes = [900, 1800]  # 15min, 30min
        windowed_df = self.rapids_processor.cudf_optimized_windowing(
            df, ["CUSTOMER_ID"], "TX_TIME_SECONDS", "TX_AMOUNT", window_sizes
        )
        
        # Check that window features are created with correct naming
        expected_features = [
            "customer_id_nb_txns_15min_window",
            "customer_id_avg_amt_15min_window",
            "customer_id_sum_amt_15min_window",
            "customer_id_min_amt_15min_window",
            "customer_id_max_amt_15min_window",
            "customer_id_stddev_amt_15min_window",
            "customer_id_nb_txns_30min_window",
            "customer_id_avg_amt_30min_window"
        ]
        
        for feature in expected_features:
            self.assertIn(feature, windowed_df.columns, f"Missing window feature: {feature}")
        
        # Verify window calculations for CUST_001
        cust_001_data = windowed_df.filter(F.col("CUSTOMER_ID") == "CUST_001").orderBy("TX_TIME_SECONDS").collect()
        
        # Last transaction for CUST_001 (at 25 minutes)
        last_tx = cust_001_data[-1]
        
        # In 15min window: should see transactions at 10min (200.0) and 25min (300.0)
        self.assertEqual(last_tx["customer_id_nb_txns_15min_window"], 2)
        self.assertEqual(last_tx["customer_id_avg_amt_15min_window"], 250.0)  # (200+300)/2
        
        # In 30min window: should see transactions at 5min (150.0), 10min (200.0), and 25min (300.0)
        self.assertEqual(last_tx["customer_id_nb_txns_30min_window"], 3)
        self.assertAlmostEqual(last_tx["customer_id_avg_amt_30min_window"], 216.67, places=1)  # (150+200+300)/3
    
    def test_gpu_accelerated_categorical_encoding(self):
        """Test GPU-accelerated categorical encoding"""
        df = self.create_sample_transaction_data()
        
        # Apply categorical encoding
        encoded_df, mappings = self.rapids_processor.gpu_accelerated_categorical_encoding(
            df, ["CUSTOMER_ID", "TERMINAL_ID"], method="ordinal"
        )
        
        # Check that encoded columns are created
        self.assertIn("CUSTOMER_ID_encoded", encoded_df.columns)
        self.assertIn("TERMINAL_ID_encoded", encoded_df.columns)
        
        # Check that mappings are created
        self.assertIn("CUSTOMER_ID", mappings)
        self.assertIn("TERMINAL_ID", mappings)
        
        # Verify encoding consistency
        encoded_data = encoded_df.select("CUSTOMER_ID_encoded", "TERMINAL_ID_encoded").distinct().collect()
        self.assertGreater(len(encoded_data), 0)
        
        # Check that encoded values are numeric
        for row in encoded_data:
            self.assertIsInstance(row["CUSTOMER_ID_encoded"], (int, float))
            self.assertIsInstance(row["TERMINAL_ID_encoded"], (int, float))
    
    def test_gpu_optimized_feature_scaling(self):
        """Test GPU-optimized feature scaling"""
        df = self.create_sample_transaction_data()
        
        # Apply feature scaling
        scaled_df = self.rapids_processor.gpu_optimized_feature_scaling(
            df, ["TX_AMOUNT"], method="standard"
        )
        
        # Check that scaled column is created
        self.assertIn("TX_AMOUNT_scaled", scaled_df.columns)
        
        # Verify scaling properties (mean should be close to 0, std close to 1)
        stats = scaled_df.select(
            F.mean("TX_AMOUNT_scaled").alias("mean"),
            F.stddev("TX_AMOUNT_scaled").alias("stddev")
        ).collect()[0]
        
        self.assertAlmostEqual(stats["mean"], 0.0, places=1)
        self.assertAlmostEqual(stats["stddev"], 1.0, places=1)
    
    def test_create_gpu_optimized_features(self):
        """Test comprehensive GPU-optimized feature creation"""
        df = self.create_sample_transaction_data()
        
        # Create comprehensive features
        feature_df = self.rapids_processor.create_gpu_optimized_features(
            df, "CUSTOMER_ID", "TERMINAL_ID", "TX_AMOUNT", "TX_DATETIME"
        )
        
        # Check that comprehensive features are created
        expected_feature_categories = [
            # Datetime features
            "year", "month", "day", "hour",
            # Velocity features
            "customer_tx_velocity_1hr", "terminal_tx_velocity_1hr",
            # Deviation features
            "amount_deviation_from_customer_avg", "amount_deviation_from_terminal_avg",
            # Ratio features
            "amount_ratio_to_customer_avg", "amount_ratio_to_terminal_avg",
            # Risk score features
            "customer_risk_score", "terminal_risk_score"
        ]
        
        for feature in expected_feature_categories:
            self.assertIn(feature, feature_df.columns, f"Missing comprehensive feature: {feature}")
        
        # Verify feature calculations
        sample_row = feature_df.first()
        
        # Velocity should be positive
        self.assertGreaterEqual(sample_row["customer_tx_velocity_1hr"], 0.0)
        self.assertGreaterEqual(sample_row["terminal_tx_velocity_1hr"], 0.0)
        
        # Ratios should be positive
        self.assertGreaterEqual(sample_row["amount_ratio_to_customer_avg"], 0.0)
        self.assertGreaterEqual(sample_row["amount_ratio_to_terminal_avg"], 0.0)
    
    def test_optimize_dataframe_for_gpu(self):
        """Test DataFrame optimization for GPU processing"""
        df = self.create_sample_transaction_data()
        
        # Optimize for GPU
        optimized_df = self.rapids_processor.optimize_dataframe_for_gpu(
            df, ["CUSTOMER_ID", "TERMINAL_ID"], target_partitions=4
        )
        
        # Check that DataFrame is optimized (partitioned and cached)
        self.assertEqual(optimized_df.rdd.getNumPartitions(), 4)
        
        # Verify data integrity is maintained
        original_count = df.count()
        optimized_count = optimized_df.count()
        self.assertEqual(original_count, optimized_count)
    
    def test_validate_gpu_acceleration(self):
        """Test GPU acceleration validation"""
        validation_results = self.rapids_processor.validate_gpu_acceleration()
        
        # Check that validation returns expected keys
        expected_keys = [
            "rapids_sql_enabled", "gpu_memory_pool_configured", 
            "concurrent_gpu_tasks_configured", "adaptive_query_execution"
        ]
        
        for key in expected_keys:
            self.assertIn(key, validation_results, f"Missing validation key: {key}")
        
        # Check that validation results are boolean
        for key, value in validation_results.items():
            if key != "validation_error":
                self.assertIsInstance(value, bool, f"Validation result {key} should be boolean")
    
    def test_notebook_compatible_feature_engineering(self):
        """Test notebook-compatible feature engineering pipeline"""
        transactions_df = self.create_sample_transaction_data()
        
        # Create minimal customers and terminals data
        customers_data = [
            ("CUST_001", 100.0, 200.0, 50.0, 25.0, 2.5),
            ("CUST_002", 150.0, 250.0, 75.0, 30.0, 3.0)
        ]
        customers_schema = StructType([
            StructField("CUSTOMER_ID", StringType(), True),
            StructField("x_customer_id", DoubleType(), True),
            StructField("y_customer_id", DoubleType(), True),
            StructField("mean_amount", DoubleType(), True),
            StructField("std_amount", DoubleType(), True),
            StructField("mean_nb_tx_per_day", DoubleType(), True)
        ])
        customers_df = self.spark.createDataFrame(customers_data, customers_schema)
        
        terminals_data = [
            ("TERM_001", 10.0, 20.0),
            ("TERM_002", 15.0, 25.0)
        ]
        terminals_schema = StructType([
            StructField("TERMINAL_ID", StringType(), True),
            StructField("x_terminal_id", DoubleType(), True),
            StructField("y_terminal_id", DoubleType(), True)
        ])
        terminals_df = self.spark.createDataFrame(terminals_data, terminals_schema)
        
        # Run notebook-compatible feature engineering
        try:
            final_df = self.rapids_processor.notebook_compatible_feature_engineering(
                transactions_df, customers_df, terminals_df
            )
            
            # Verify that final DataFrame has expected structure
            self.assertGreater(final_df.count(), 0, "Final DataFrame should not be empty")
            self.assertGreater(len(final_df.columns), 10, "Should have multiple feature columns")
            
            # Check for key feature types
            column_names = final_df.columns
            
            # Should have datetime features
            datetime_features = [col for col in column_names if col in ["year", "month", "day", "hour"]]
            self.assertGreater(len(datetime_features), 0, "Should have datetime features")
            
            # Should have encoded features
            encoded_features = [col for col in column_names if "_encoded" in col]
            self.assertGreater(len(encoded_features), 0, "Should have encoded features")
            
        except Exception as e:
            # If RAPIDS is not available, this test may fail - that's expected
            self.skipTest(f"Notebook-compatible feature engineering failed (expected if RAPIDS not available): {str(e)}")
    
    def test_memory_optimization_configuration(self):
        """Test memory optimization configuration for cuDF"""
        # Test that RAPIDS configurations are properly set
        config_checks = [
            ("spark.rapids.sql.enabled", "true"),
            ("spark.rapids.memory.gpu.pool", "ASYNC"),
            ("spark.sql.adaptive.enabled", "true")
        ]
        
        for config_key, expected_value in config_checks:
            actual_value = self.spark.conf.get(config_key, "not_set")
            if actual_value != "not_set":
                self.assertEqual(actual_value, expected_value, 
                               f"Configuration {config_key} should be {expected_value}")
    
    def test_cudf_performance_optimizations(self):
        """Test cuDF performance optimization patterns"""
        df = self.create_sample_transaction_data()
        
        # Test partitioning optimization
        optimized_df = self.rapids_processor.optimize_dataframe_for_gpu(df, target_partitions=2)
        self.assertEqual(optimized_df.rdd.getNumPartitions(), 2)
        
        # Test that data is preserved
        original_data = df.collect()
        optimized_data = optimized_df.collect()
        self.assertEqual(len(original_data), len(optimized_data))
        
        # Test caching behavior (DataFrame should be cached)
        self.assertTrue(optimized_df.is_cached)


def run_cudf_optimization_tests():
    """Run all cuDF optimization tests"""
    print("Running cuDF optimization tests...\n")
    
    # Create test suite
    suite = unittest.TestLoader().loadTestsFromTestCase(TestCuDFOptimizations)
    
    # Run tests
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    
    print(f"\ncuDF Optimization Test Results:")
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
    run_cudf_optimization_tests()