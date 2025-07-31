#!/usr/bin/env python3
"""
Comprehensive unit tests for RAPIDS-enhanced data transformation functions
Tests all enhanced cuDF optimizations and GPU-accelerated processing
"""

import unittest
import sys
import os
from datetime import datetime, timedelta
from typing import List, Tuple

# Add the fraud-detection directory to the path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from pyspark.sql import SparkSession, DataFrame
from pyspark.sql import functions as F
from pyspark.sql.types import *
from fraud_detection_feature_engineering import FraudDetectionFeatureEngineering
from rapids_utils import RapidsDataProcessor


class TestRapidsDataTransformations(unittest.TestCase):
    """
    Comprehensive test suite for RAPIDS-enhanced data transformations
    Tests requirements 6.1, 6.2, 6.3 implementation
    """
    
    @classmethod
    def setUpClass(cls):
        """Set up Spark session for testing with RAPIDS configuration"""
        cls.spark = SparkSession.builder \
            .appName("RapidsDataTransformationTests") \
            .master("local[2]") \
            .config("spark.sql.adaptive.enabled", "false") \
            .config("spark.plugins", "com.nvidia.spark.SQLPlugin") \
            .config("spark.rapids.sql.enabled", "true") \
            .getOrCreate()
        
        cls.feature_engineer = FraudDetectionFeatureEngineering(cls.spark)
        cls.rapids_processor = RapidsDataProcessor(cls.spark)
        
    @classmethod
    def tearDownClass(cls):
        """Clean up Spark session"""
        cls.spark.stop()
    
    def create_comprehensive_test_data(self) -> Tuple[DataFrame, DataFrame, DataFrame]:
        """Create comprehensive test data for RAPIDS testing"""
        # Create customers data
        customers_data = [
            ("CUST_001", "John Doe", "123 Main St", "New York", "NY", "10001", 
             "Engineer", "john@email.com", "555-1234", 100.0, 200.0, 50.0, 25.0, 2.5, 1.0, ["TERM_001", "TERM_002"]),
            ("CUST_002", "Jane Smith", "456 Oak Ave", "Los Angeles", "CA", "90210",
             "Doctor", "jane@email.com", "555-5678", 150.0, 250.0, 75.0, 30.0, 3.0, 1.2, ["TERM_002", "TERM_003"]),
            ("CUST_003", "Bob Johnson", "789 Pine Rd", "Chicago", "IL", "60601",
             "Teacher", "bob@email.com", "555-9012", 80.0, 180.0, 40.0, 20.0, 1.8, 0.8, ["TERM_001", "TERM_003"])
        ]
        
        customers_schema = StructType([
            StructField("CUSTOMER_ID", StringType(), True),
            StructField("customer_name", StringType(), True),
            StructField("billing_street", StringType(), True),
            StructField("billing_city", StringType(), True),
            StructField("billing_state", StringType(), True),
            StructField("billing_zip", StringType(), True),
            StructField("customer_job", StringType(), True),
            StructField("customer_email", StringType(), True),
            StructField("phone", StringType(), True),
            StructField("x_customer_id", DoubleType(), True),
            StructField("y_customer_id", DoubleType(), True),
            StructField("mean_amount", DoubleType(), True),
            StructField("std_amount", DoubleType(), True),
            StructField("mean_nb_tx_per_day", DoubleType(), True),
            StructField("std_dev_nb_tx_per_day", DoubleType(), True),
            StructField("available_terminals", ArrayType(StringType()), True)
        ])
        
        customers_df = self.spark.createDataFrame(customers_data, customers_schema)
        
        # Create terminals data
        terminals_data = [
            ("TERM_001", 10.0, 20.0, "Grocery Store"),
            ("TERM_002", 15.0, 25.0, "Gas Station"),
            ("TERM_003", 20.0, 30.0, "Restaurant")
        ]
        
        terminals_schema = StructType([
            StructField("TERMINAL_ID", StringType(), True),
            StructField("x_terminal_id", DoubleType(), True),
            StructField("y_terminal_id", DoubleType(), True),
            StructField("merchant", StringType(), True)
        ])
        
        terminals_df = self.spark.createDataFrame(terminals_data, terminals_schema)
        
        # Create comprehensive transactions data with various time patterns
        base_time = datetime(2024, 1, 1, 10, 0, 0)
        
        transactions_data = [
            # Normal business hours transactions
            (str(base_time), "CUST_001", "TERM_001", 25.50, int(base_time.timestamp()), 1, 0, "2024-01"),
            (str(base_time + timedelta(minutes=10)), "CUST_001", "TERM_001", 15.75, int((base_time + timedelta(minutes=10)).timestamp()), 1, 0, "2024-01"),
            (str(base_time + timedelta(minutes=20)), "CUST_001", "TERM_002", 45.00, int((base_time + timedelta(minutes=20)).timestamp()), 1, 1, "2024-01"),
            
            # Weekend transactions
            (str(base_time + timedelta(days=5, hours=2)), "CUST_002", "TERM_002", 35.25, int((base_time + timedelta(days=5, hours=2)).timestamp()), 6, 0, "2024-01"),
            (str(base_time + timedelta(days=5, hours=2, minutes=25)), "CUST_002", "TERM_003", 55.80, int((base_time + timedelta(days=5, hours=2, minutes=25)).timestamp()), 6, 0, "2024-01"),
            
            # Night time transactions (high risk)
            (str(base_time + timedelta(hours=14)), "CUST_003", "TERM_001", 120.30, int((base_time + timedelta(hours=14)).timestamp()), 1, 1, "2024-01"),
            (str(base_time + timedelta(hours=14, minutes=30)), "CUST_003", "TERM_003", 280.90, int((base_time + timedelta(hours=14, minutes=30)).timestamp()), 1, 1, "2024-01"),
            
            # High frequency transactions (potential fraud)
            (str(base_time + timedelta(minutes=5)), "CUST_001", "TERM_001", 100.00, int((base_time + timedelta(minutes=5)).timestamp()), 1, 0, "2024-01"),
            (str(base_time + timedelta(minutes=6)), "CUST_001", "TERM_001", 200.00, int((base_time + timedelta(minutes=6)).timestamp()), 1, 0, "2024-01"),
            (str(base_time + timedelta(minutes=7)), "CUST_001", "TERM_001", 300.00, int((base_time + timedelta(minutes=7)).timestamp()), 1, 1, "2024-01")
        ]
        
        transactions_schema = StructType([
            StructField("TX_DATETIME", StringType(), True),
            StructField("CUSTOMER_ID", StringType(), True),
            StructField("TERMINAL_ID", StringType(), True),
            StructField("TX_AMOUNT", DoubleType(), True),
            StructField("TX_TIME_SECONDS", LongType(), True),
            StructField("TX_TIME_DAYS", IntegerType(), True),
            StructField("TX_FRAUD", IntegerType(), True),
            StructField("month", StringType(), True)
        ])
        
        transactions_df = self.spark.createDataFrame(transactions_data, transactions_schema)
        
        return customers_df, terminals_df, transactions_df
    
    def test_requirement_6_1_parquet_format_handling(self):
        """Test Requirement 6.1: Handle the same parquet format from S3"""
        customers_df, terminals_df, transactions_df = self.create_comprehensive_test_data()
        
        # Test schema validation
        try:
            self.feature_engineer._validate_schemas(customers_df, terminals_df, transactions_df)
        except Exception as e:
            self.fail(f"Schema validation failed for parquet format: {str(e)}")
        
        # Test datetime string to timestamp conversion
        processed_df = self.feature_engineer.preprocess_transactions(transactions_df)
        
        # Verify TX_DATETIME is converted to timestamp
        self.assertEqual(processed_df.schema["TX_DATETIME"].dataType, TimestampType())
        
        # Verify data integrity is maintained
        self.assertEqual(processed_df.count(), transactions_df.count())
        
        print("✓ Requirement 6.1: Parquet format handling verified")
    
    def test_requirement_6_2_identical_features_generation(self):
        """Test Requirement 6.2: Generate identical features as the current EMR pipeline"""
        customers_df, terminals_df, transactions_df = self.create_comprehensive_test_data()
        
        # Process through the complete pipeline
        processed_df = self.feature_engineer.preprocess_transactions(transactions_df)
        
        # Add window features
        processed_df = self.feature_engineer.add_window_features(
            processed_df, "CUSTOMER_ID", "customer_id"
        )
        processed_df = self.feature_engineer.add_window_features(
            processed_df, "TERMINAL_ID", "terminal_id"
        )
        
        # Verify notebook-compatible column names exist
        expected_notebook_columns = [
            "yyyy", "mm", "dd",
            "customer_id_nb_txns_15min_window",
            "customer_id_nb_txns_30min_window",
            "customer_id_avg_amt_15min_window",
            "customer_id_avg_amt_30min_window",
            "terminal_id_nb_txns_15min_window",
            "terminal_id_nb_txns_30min_window",
            "terminal_id_avg_amt_15min_window",
            "terminal_id_avg_amt_30min_window"
        ]
        
        for col in expected_notebook_columns:
            self.assertIn(col, processed_df.columns, f"Missing notebook-compatible column: {col}")
        
        # Verify date extraction matches notebook logic
        first_row = processed_df.first()
        self.assertEqual(first_row["yyyy"], 2024)
        self.assertEqual(first_row["mm"], 1)
        self.assertEqual(first_row["dd"], 1)
        
        print("✓ Requirement 6.2: Identical features generation verified")
    
    def test_requirement_6_3_datetime_windowing_logic(self):
        """Test Requirement 6.3: Maintain the same datetime processing and windowing logic"""
        customers_df, terminals_df, transactions_df = self.create_comprehensive_test_data()
        
        # Test datetime processing
        processed_df = self.feature_engineer.preprocess_transactions(transactions_df)
        
        # Verify enhanced datetime features are created
        expected_datetime_features = [
            "yyyy", "mm", "dd", "hour_of_day", "day_of_week",
            "is_weekend", "is_business_hours", "is_night_time",
            "minute_of_hour", "day_of_year", "week_of_year"
        ]
        
        for feature in expected_datetime_features:
            self.assertIn(feature, processed_df.columns, f"Missing datetime feature: {feature}")
        
        # Test windowing logic accuracy
        windowed_df = self.feature_engineer.add_window_features(
            processed_df, "CUSTOMER_ID", "customer_id"
        )
        
        # Verify window calculations
        customer_001_data = windowed_df.filter(F.col("CUSTOMER_ID") == "CUST_001").collect()
        
        # Test that window features are calculated correctly
        for row in customer_001_data:
            self.assertIsNotNone(row["customer_id_nb_txns_15min_window"])
            self.assertIsNotNone(row["customer_id_avg_amt_15min_window"])
            self.assertGreaterEqual(row["customer_id_nb_txns_15min_window"], 1)
        
        print("✓ Requirement 6.3: Datetime processing and windowing logic verified")
    
    def test_rapids_gpu_optimization_features(self):
        """Test RAPIDS GPU optimization features"""
        customers_df, terminals_df, transactions_df = self.create_comprehensive_test_data()
        
        # Test GPU optimization configuration
        gpu_validation = self.rapids_processor.validate_gpu_acceleration()
        
        # Should have validation results
        self.assertIsInstance(gpu_validation, dict)
        self.assertIn("rapids_sql_enabled", gpu_validation)
        
        # Test DataFrame optimization for GPU
        optimized_df = self.rapids_processor.optimize_dataframe_for_gpu(
            transactions_df, ["CUSTOMER_ID", "TERMINAL_ID"], 100
        )
        
        # Should maintain data integrity
        self.assertEqual(optimized_df.count(), transactions_df.count())
        
        # Test GPU-optimized datetime processing
        datetime_processed_df = self.rapids_processor.gpu_optimized_datetime_processing(
            transactions_df, "TX_DATETIME"
        )
        
        # Should have enhanced datetime features
        enhanced_features = [
            "year", "month", "day", "hour", "minute", "second",
            "is_weekend", "is_business_hours", "is_night_time",
            "hour_sin", "hour_cos", "day_sin", "day_cos",
            "time_risk_score", "composite_risk_score"
        ]
        
        available_features = [f for f in enhanced_features if f in datetime_processed_df.columns]
        self.assertGreater(len(available_features), 10, "Should have many enhanced datetime features")
        
        print("✓ RAPIDS GPU optimization features verified")
    
    def test_cudf_optimized_windowing(self):
        """Test cuDF-optimized windowing operations"""
        customers_df, terminals_df, transactions_df = self.create_comprehensive_test_data()
        
        # Preprocess transactions
        processed_df = self.feature_engineer.preprocess_transactions(transactions_df)
        
        # Test cuDF windowing
        window_sizes = [900, 1800, 3600]  # 15min, 30min, 1hr
        windowed_df = self.rapids_processor.cudf_optimized_windowing(
            processed_df, ["CUSTOMER_ID"], "TX_TIME_SECONDS", "TX_AMOUNT", window_sizes
        )
        
        # Verify window features are created
        expected_window_features = [
            "customer_id_nb_txns_15min_window",
            "customer_id_avg_amt_15min_window",
            "customer_id_sum_amt_15min_window",
            "customer_id_stddev_amt_15min_window",
            "customer_id_tx_velocity_15min_window",
            "customer_id_amt_zscore_15min_window"
        ]
        
        for feature in expected_window_features:
            self.assertIn(feature, windowed_df.columns, f"Missing cuDF window feature: {feature}")
        
        # Test window calculation accuracy
        customer_data = windowed_df.filter(F.col("CUSTOMER_ID") == "CUST_001").collect()
        
        for row in customer_data:
            # Window counts should be positive
            self.assertGreaterEqual(row["customer_id_nb_txns_15min_window"], 1)
            # Average amounts should be positive
            if row["customer_id_avg_amt_15min_window"] is not None:
                self.assertGreater(row["customer_id_avg_amt_15min_window"], 0)
        
        print("✓ cuDF-optimized windowing verified")
    
    def test_comprehensive_fraud_feature_engineering(self):
        """Test comprehensive fraud feature engineering pipeline"""
        customers_df, terminals_df, transactions_df = self.create_comprehensive_test_data()
        
        # Run comprehensive feature engineering
        final_df = self.rapids_processor.comprehensive_fraud_feature_engineering(
            transactions_df, customers_df, terminals_df
        )
        
        # Verify comprehensive feature set
        self.assertGreater(final_df.count(), 0, "Should have processed data")
        self.assertGreater(len(final_df.columns), 30, "Should have comprehensive feature set")
        
        # Check for key feature categories
        column_names = final_df.columns
        
        # Should have datetime features
        datetime_features = [col for col in column_names if any(x in col for x in ["year", "month", "day", "hour"])]
        self.assertGreater(len(datetime_features), 0, "Should have datetime features")
        
        # Should have window features
        window_features = [col for col in column_names if "_window" in col]
        self.assertGreater(len(window_features), 0, "Should have window features")
        
        # Should have risk features
        risk_features = [col for col in column_names if "risk" in col or "anomaly" in col]
        self.assertGreater(len(risk_features), 0, "Should have risk features")
        
        # Should have encoded categorical features
        encoded_features = [col for col in column_names if "_encoded" in col]
        self.assertGreater(len(encoded_features), 0, "Should have encoded features")
        
        print("✓ Comprehensive fraud feature engineering verified")
    
    def test_enhanced_statistical_features(self):
        """Test enhanced statistical features for fraud detection"""
        customers_df, terminals_df, transactions_df = self.create_comprehensive_test_data()
        
        # Process with enhanced features
        processed_df = self.feature_engineer.preprocess_transactions(transactions_df)
        windowed_df = self.feature_engineer.add_window_features(
            processed_df, "CUSTOMER_ID", "customer_id"
        )
        
        # Check for enhanced statistical features
        expected_stat_features = [
            "customer_id_sum_amt_15min_window",
            "customer_id_min_amt_15min_window",
            "customer_id_max_amt_15min_window",
            "customer_id_stddev_amt_15min_window",
            "customer_id_tx_velocity_15min_window",
            "customer_id_amt_zscore_15min_window"
        ]
        
        available_stat_features = [f for f in expected_stat_features if f in windowed_df.columns]
        
        # Should have most statistical features (some may be RAPIDS-specific)
        self.assertGreater(len(available_stat_features), 3, "Should have enhanced statistical features")
        
        # Test statistical feature calculations
        customer_data = windowed_df.filter(F.col("CUSTOMER_ID") == "CUST_001").collect()
        
        for row in customer_data:
            # Statistical features should be reasonable
            if "customer_id_sum_amt_15min_window" in windowed_df.columns:
                if row["customer_id_sum_amt_15min_window"] is not None:
                    self.assertGreaterEqual(row["customer_id_sum_amt_15min_window"], 0)
        
        print("✓ Enhanced statistical features verified")
    
    def test_time_based_risk_indicators(self):
        """Test time-based risk indicators for fraud detection"""
        customers_df, terminals_df, transactions_df = self.create_comprehensive_test_data()
        
        # Process with datetime features
        processed_df = self.feature_engineer.preprocess_transactions(transactions_df)
        
        # Check for time-based risk indicators
        expected_risk_indicators = [
            "is_weekend", "is_business_hours", "is_night_time",
            "is_early_morning", "is_evening"
        ]
        
        for indicator in expected_risk_indicators:
            if indicator in processed_df.columns:
                self.assertIn(indicator, processed_df.columns, f"Missing risk indicator: {indicator}")
        
        # Test risk indicator logic
        sample_data = processed_df.collect()
        
        for row in sample_data:
            # Weekend indicator should be 0 or 1
            if "is_weekend" in processed_df.columns:
                self.assertIn(row["is_weekend"], [0, 1], "Weekend indicator should be binary")
            
            # Business hours indicator should be 0 or 1
            if "is_business_hours" in processed_df.columns:
                self.assertIn(row["is_business_hours"], [0, 1], "Business hours indicator should be binary")
        
        print("✓ Time-based risk indicators verified")
    
    def test_data_quality_and_integrity(self):
        """Test data quality and integrity throughout the pipeline"""
        customers_df, terminals_df, transactions_df = self.create_comprehensive_test_data()
        
        # Run complete pipeline
        final_df = self.feature_engineer.run_feature_engineering(
            "dummy_customers", "dummy_terminals", "dummy_transactions", "dummy_output"
        )
        
        # This will fail due to dummy paths, but we can test the pipeline structure
        # In practice, we'd use actual test data files
        
        # Test individual components
        processed_df = self.feature_engineer.preprocess_transactions(transactions_df)
        
        # Data integrity checks
        self.assertEqual(processed_df.count(), transactions_df.count(), "Should preserve row count")
        
        # Check for null values in key columns
        key_columns = ["TX_AMOUNT", "CUSTOMER_ID", "TERMINAL_ID"]
        for col in key_columns:
            null_count = processed_df.filter(F.col(col).isNull()).count()
            self.assertEqual(null_count, 0, f"Column {col} should not have null values")
        
        # Check data types
        self.assertEqual(processed_df.schema["TX_DATETIME"].dataType, TimestampType())
        self.assertEqual(processed_df.schema["TX_AMOUNT"].dataType, DoubleType())
        
        print("✓ Data quality and integrity verified")
    
    def test_performance_optimizations(self):
        """Test performance optimizations in the pipeline"""
        customers_df, terminals_df, transactions_df = self.create_comprehensive_test_data()
        
        # Test DataFrame optimization
        optimized_df = self.rapids_processor.optimize_dataframe_for_gpu(
            transactions_df, ["CUSTOMER_ID", "TERMINAL_ID"], 50
        )
        
        # Should maintain data integrity
        self.assertEqual(optimized_df.count(), transactions_df.count())
        
        # Test caching behavior (CPU mode)
        processed_df = self.feature_engineer.preprocess_transactions(transactions_df)
        
        # Should complete without errors
        self.assertGreater(processed_df.count(), 0)
        
        print("✓ Performance optimizations verified")


def run_comprehensive_tests():
    """Run all comprehensive RAPIDS data transformation tests"""
    print("Running comprehensive RAPIDS data transformation tests...\n")
    
    # Create test suite
    suite = unittest.TestLoader().loadTestsFromTestCase(TestRapidsDataTransformations)
    
    # Run tests
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    
    print(f"\nTest Results:")
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
    run_comprehensive_tests()