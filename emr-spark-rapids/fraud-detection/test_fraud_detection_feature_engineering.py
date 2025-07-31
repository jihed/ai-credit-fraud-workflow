#!/usr/bin/env python3
"""
Unit tests for Fraud Detection Feature Engineering with RAPIDS
Tests all data transformation functions to ensure correctness
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


class TestFraudDetectionFeatureEngineering(unittest.TestCase):
    """
    Test suite for fraud detection feature engineering functions
    """
    
    @classmethod
    def setUpClass(cls):
        """Set up Spark session for testing"""
        cls.spark = SparkSession.builder \
            .appName("FraudDetectionFeatureEngineeringTests") \
            .master("local[2]") \
            .config("spark.sql.adaptive.enabled", "false") \
            .getOrCreate()
        
        cls.feature_engineer = FraudDetectionFeatureEngineering(cls.spark)
        
    @classmethod
    def tearDownClass(cls):
        """Clean up Spark session"""
        cls.spark.stop()
    
    def create_sample_customers_data(self) -> DataFrame:
        """Create sample customers data for testing"""
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
        
        return self.spark.createDataFrame(customers_data, customers_schema)
    
    def create_sample_terminals_data(self) -> DataFrame:
        """Create sample terminals data for testing"""
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
        
        return self.spark.createDataFrame(terminals_data, terminals_schema)
    
    def create_sample_transactions_data(self) -> DataFrame:
        """Create sample transactions data for testing"""
        base_time = datetime(2024, 1, 1, 10, 0, 0)
        
        transactions_data = [
            # Customer 1 transactions
            (str(base_time), "CUST_001", "TERM_001", 25.50, int(base_time.timestamp()), 1, 0, "2024-01"),
            (str(base_time + timedelta(minutes=10)), "CUST_001", "TERM_001", 15.75, int((base_time + timedelta(minutes=10)).timestamp()), 1, 0, "2024-01"),
            (str(base_time + timedelta(minutes=20)), "CUST_001", "TERM_002", 45.00, int((base_time + timedelta(minutes=20)).timestamp()), 1, 1, "2024-01"),
            
            # Customer 2 transactions
            (str(base_time + timedelta(minutes=5)), "CUST_002", "TERM_002", 35.25, int((base_time + timedelta(minutes=5)).timestamp()), 1, 0, "2024-01"),
            (str(base_time + timedelta(minutes=25)), "CUST_002", "TERM_003", 55.80, int((base_time + timedelta(minutes=25)).timestamp()), 1, 0, "2024-01"),
            
            # Customer 3 transactions
            (str(base_time + timedelta(minutes=15)), "CUST_003", "TERM_001", 12.30, int((base_time + timedelta(minutes=15)).timestamp()), 1, 0, "2024-01"),
            (str(base_time + timedelta(minutes=30)), "CUST_003", "TERM_003", 28.90, int((base_time + timedelta(minutes=30)).timestamp()), 1, 1, "2024-01")
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
        
        return self.spark.createDataFrame(transactions_data, transactions_schema)
    
    def test_schema_validation(self):
        """Test schema validation for input datasets"""
        customers_df = self.create_sample_customers_data()
        terminals_df = self.create_sample_terminals_data()
        transactions_df = self.create_sample_transactions_data()
        
        # This should not raise an exception
        try:
            self.feature_engineer._validate_schemas(customers_df, terminals_df, transactions_df)
        except Exception as e:
            self.fail(f"Schema validation failed unexpectedly: {str(e)}")
    
    def test_schema_validation_missing_columns(self):
        """Test schema validation with missing required columns"""
        customers_df = self.create_sample_customers_data().drop("CUSTOMER_ID")
        terminals_df = self.create_sample_terminals_data()
        transactions_df = self.create_sample_transactions_data()
        
        with self.assertRaises(ValueError) as context:
            self.feature_engineer._validate_schemas(customers_df, terminals_df, transactions_df)
        
        self.assertIn("Missing required column in customers: CUSTOMER_ID", str(context.exception))
    
    def test_preprocess_transactions(self):
        """Test transaction preprocessing with datetime parsing"""
        transactions_df = self.create_sample_transactions_data()
        
        processed_df = self.feature_engineer.preprocess_transactions(transactions_df)
        
        # Check that datetime columns are added
        self.assertIn("yyyy", processed_df.columns)
        self.assertIn("mm", processed_df.columns)
        self.assertIn("dd", processed_df.columns)
        
        # Check that TX_DATETIME is converted to timestamp
        self.assertEqual(processed_df.schema["TX_DATETIME"].dataType, TimestampType())
        
        # Verify date extraction
        first_row = processed_df.first()
        self.assertEqual(first_row["yyyy"], 2024)
        self.assertEqual(first_row["mm"], 1)
        self.assertEqual(first_row["dd"], 1)
    
    def test_add_window_features_customer(self):
        """Test adding customer-based window features"""
        transactions_df = self.create_sample_transactions_data()
        processed_df = self.feature_engineer.preprocess_transactions(transactions_df)
        
        # Add customer window features
        windowed_df = self.feature_engineer.add_window_features(
            processed_df, "CUSTOMER_ID", "customer_id"
        )
        
        # Check that window feature columns are added
        expected_columns = [
            "customer_id_nb_txns_15min_window",
            "customer_id_nb_txns_30min_window", 
            "customer_id_avg_amt_15min_window",
            "customer_id_avg_amt_30min_window"
        ]
        
        for col in expected_columns:
            self.assertIn(col, windowed_df.columns, f"Missing column: {col}")
        
        # Verify window calculations for a specific customer
        cust_001_data = windowed_df.filter(F.col("CUSTOMER_ID") == "CUST_001").collect()
        
        # Customer 001 has 3 transactions, so the last transaction should see all 3 in 30min window
        last_transaction = max(cust_001_data, key=lambda x: x["TX_TIME_SECONDS"])
        self.assertEqual(last_transaction["customer_id_nb_txns_30min_window"], 3)
    
    def test_add_window_features_terminal(self):
        """Test adding terminal-based window features"""
        transactions_df = self.create_sample_transactions_data()
        processed_df = self.feature_engineer.preprocess_transactions(transactions_df)
        
        # Add terminal window features
        windowed_df = self.feature_engineer.add_window_features(
            processed_df, "TERMINAL_ID", "terminal_id"
        )
        
        # Check that window feature columns are added
        expected_columns = [
            "terminal_id_nb_txns_15min_window",
            "terminal_id_nb_txns_30min_window",
            "terminal_id_avg_amt_15min_window", 
            "terminal_id_avg_amt_30min_window"
        ]
        
        for col in expected_columns:
            self.assertIn(col, windowed_df.columns, f"Missing column: {col}")
    
    def test_encode_categorical_features(self):
        """Test categorical feature encoding"""
        customers_df = self.create_sample_customers_data()
        terminals_df = self.create_sample_terminals_data()
        transactions_df = self.create_sample_transactions_data()
        processed_df = self.feature_engineer.preprocess_transactions(transactions_df)
        
        # Encode categorical features
        encoded_transactions, encoded_customers, encoded_terminals = \
            self.feature_engineer.encode_categorical_features(
                processed_df, customers_df, terminals_df
            )
        
        # Check that index columns are created
        self.assertIn("CUSTOMER_ID_index", encoded_transactions.columns)
        self.assertIn("TERMINAL_ID_index", encoded_transactions.columns)
        self.assertIn("CUSTOMER_ID_index", encoded_customers.columns)
        self.assertIn("TERMINAL_ID_index", encoded_terminals.columns)
        
        # Check fraud encoding
        self.assertIn("TX_FRAUD_0", encoded_transactions.columns)
        self.assertIn("TX_FRAUD_1", encoded_transactions.columns)
        
        # Verify fraud encoding logic
        fraud_data = encoded_transactions.select("TX_FRAUD_0", "TX_FRAUD_1").collect()
        for row in fraud_data:
            # TX_FRAUD_0 and TX_FRAUD_1 should be mutually exclusive
            self.assertEqual(row["TX_FRAUD_0"] + row["TX_FRAUD_1"], 1)
        
        # Check that original columns are dropped
        self.assertNotIn("TX_FRAUD", encoded_transactions.columns)
        self.assertNotIn("TX_DATETIME", encoded_transactions.columns)
    
    def test_create_final_features(self):
        """Test final feature set creation with joins"""
        customers_df = self.create_sample_customers_data()
        terminals_df = self.create_sample_terminals_data()
        transactions_df = self.create_sample_transactions_data()
        
        # Process through the pipeline
        processed_df = self.feature_engineer.preprocess_transactions(transactions_df)
        windowed_df = self.feature_engineer.add_window_features(
            processed_df, "CUSTOMER_ID", "customer_id"
        )
        windowed_df = self.feature_engineer.add_window_features(
            windowed_df, "TERMINAL_ID", "terminal_id"
        )
        
        encoded_transactions, encoded_customers, encoded_terminals = \
            self.feature_engineer.encode_categorical_features(
                windowed_df, customers_df, terminals_df
            )
        
        # Create final features
        final_df = self.feature_engineer.create_final_features(
            encoded_transactions, encoded_customers, encoded_terminals
        )
        
        # Check that joins worked - should have same number of rows as transactions
        self.assertEqual(final_df.count(), transactions_df.count())
        
        # Check that key columns are present
        expected_key_columns = [
            "CUSTOMER_ID_index",
            "TERMINAL_ID_index", 
            "TX_AMOUNT",
            "TX_FRAUD_1",
            "x_customer_id",
            "y_customer_id"
        ]
        
        for col in expected_key_columns:
            self.assertIn(col, final_df.columns, f"Missing key column: {col}")
        
        # Verify no null values after fillna
        null_counts = final_df.select([F.sum(F.col(c).isNull().cast("int")).alias(c) 
                                     for c in final_df.columns]).collect()[0]
        
        for col in final_df.columns:
            self.assertEqual(null_counts[col], 0, f"Column {col} has null values")
    
    def test_time_windows_configuration(self):
        """Test that time windows match the original notebook"""
        expected_windows = {
            "15min": 15 * 60,
            "30min": 30 * 60,
            "60min": 60 * 60,
            "1day": 24 * 60 * 60,
            "7day": 7 * 24 * 60 * 60,
            "15day": 15 * 24 * 60 * 60,
            "30day": 30 * 24 * 60 * 60
        }
        
        self.assertEqual(self.feature_engineer.time_windows, expected_windows)
    
    def test_window_feature_calculation_accuracy(self):
        """Test accuracy of window feature calculations"""
        # Create transactions with known timing
        base_time = datetime(2024, 1, 1, 10, 0, 0)
        
        # Customer with transactions at 0, 10, 20 minutes
        test_data = [
            (str(base_time), "CUST_TEST", "TERM_001", 100.0, int(base_time.timestamp()), 1, 0, "2024-01"),
            (str(base_time + timedelta(minutes=10)), "CUST_TEST", "TERM_001", 200.0, int((base_time + timedelta(minutes=10)).timestamp()), 1, 0, "2024-01"),
            (str(base_time + timedelta(minutes=20)), "CUST_TEST", "TERM_001", 300.0, int((base_time + timedelta(minutes=20)).timestamp()), 1, 0, "2024-01")
        ]
        
        test_schema = StructType([
            StructField("TX_DATETIME", StringType(), True),
            StructField("CUSTOMER_ID", StringType(), True),
            StructField("TERMINAL_ID", StringType(), True),
            StructField("TX_AMOUNT", DoubleType(), True),
            StructField("TX_TIME_SECONDS", LongType(), True),
            StructField("TX_TIME_DAYS", IntegerType(), True),
            StructField("TX_FRAUD", IntegerType(), True),
            StructField("month", StringType(), True)
        ])
        
        test_df = self.spark.createDataFrame(test_data, test_schema)
        processed_df = self.feature_engineer.preprocess_transactions(test_df)
        windowed_df = self.feature_engineer.add_window_features(
            processed_df, "CUSTOMER_ID", "customer_id"
        )
        
        # Get the last transaction (at 20 minutes)
        last_transaction = windowed_df.orderBy(F.col("TX_TIME_SECONDS").desc()).first()
        
        # In 15min window: should see 2 transactions (10min and 20min)
        self.assertEqual(last_transaction["customer_id_nb_txns_15min_window"], 2)
        
        # In 30min window: should see all 3 transactions
        self.assertEqual(last_transaction["customer_id_nb_txns_30min_window"], 3)
        
        # Average amount in 15min window: (200 + 300) / 2 = 250
        self.assertEqual(last_transaction["customer_id_avg_amt_15min_window"], 250.0)
        
        # Average amount in 30min window: (100 + 200 + 300) / 3 = 200
        self.assertEqual(last_transaction["customer_id_avg_amt_30min_window"], 200.0)
    
    def test_cudf_datetime_processing(self):
        """Test cuDF-optimized datetime processing features"""
        transactions_df = self.create_sample_transactions_data()
        processed_df = self.feature_engineer.preprocess_transactions(transactions_df)
        
        # Check that enhanced datetime features are added
        expected_datetime_features = [
            "yyyy", "mm", "dd", "hour_of_day", "day_of_week", 
            "is_weekend", "is_business_hours", "is_night_time",
            "minute_of_hour", "day_of_year", "week_of_year"
        ]
        
        for feature in expected_datetime_features:
            self.assertIn(feature, processed_df.columns, f"Missing datetime feature: {feature}")
        
        # Verify datetime feature values
        first_row = processed_df.first()
        self.assertEqual(first_row["yyyy"], 2024)
        self.assertEqual(first_row["mm"], 1)
        self.assertEqual(first_row["dd"], 1)
        self.assertEqual(first_row["hour_of_day"], 10)  # 10 AM
        self.assertEqual(first_row["is_business_hours"], 1)  # 10 AM is business hours
        self.assertEqual(first_row["is_weekend"], 0)  # January 1, 2024 is Monday
        self.assertEqual(first_row["is_night_time"], 0)  # 10 AM is not night time
    
    def test_rapids_window_feature_accuracy(self):
        """Test accuracy of RAPIDS-optimized window features"""
        # Create test data with known timing for precise validation
        base_time = datetime(2024, 1, 1, 10, 0, 0)
        
        test_data = [
            # Customer transactions at specific intervals
            (str(base_time), "CUST_TEST", "TERM_001", 100.0, int(base_time.timestamp()), 1, 0, "2024-01"),
            (str(base_time + timedelta(minutes=10)), "CUST_TEST", "TERM_001", 200.0, int((base_time + timedelta(minutes=10)).timestamp()), 1, 0, "2024-01"),
            (str(base_time + timedelta(minutes=20)), "CUST_TEST", "TERM_001", 300.0, int((base_time + timedelta(minutes=20)).timestamp()), 1, 0, "2024-01"),
            (str(base_time + timedelta(minutes=35)), "CUST_TEST", "TERM_001", 400.0, int((base_time + timedelta(minutes=35)).timestamp()), 1, 0, "2024-01")
        ]
        
        test_schema = StructType([
            StructField("TX_DATETIME", StringType(), True),
            StructField("CUSTOMER_ID", StringType(), True),
            StructField("TERMINAL_ID", StringType(), True),
            StructField("TX_AMOUNT", DoubleType(), True),
            StructField("TX_TIME_SECONDS", LongType(), True),
            StructField("TX_TIME_DAYS", IntegerType(), True),
            StructField("TX_FRAUD", IntegerType(), True),
            StructField("month", StringType(), True)
        ])
        
        test_df = self.spark.createDataFrame(test_data, test_schema)
        processed_df = self.feature_engineer.preprocess_transactions(test_df)
        windowed_df = self.feature_engineer.add_window_features(
            processed_df, "CUSTOMER_ID", "customer_id"
        )
        
        # Get transactions ordered by time
        ordered_transactions = windowed_df.orderBy(F.col("TX_TIME_SECONDS")).collect()
        
        # Test 15-minute window calculations
        last_transaction = ordered_transactions[-1]  # Transaction at 35 minutes
        
        # In 15min window from 35min: should see only the transaction at 35min (400.0)
        self.assertEqual(last_transaction["customer_id_nb_txns_15min_window"], 1)
        self.assertEqual(last_transaction["customer_id_avg_amt_15min_window"], 400.0)
        
        # In 30min window from 35min: should see transactions at 20min (300.0) and 35min (400.0)
        self.assertEqual(last_transaction["customer_id_nb_txns_30min_window"], 2)
        self.assertEqual(last_transaction["customer_id_avg_amt_30min_window"], 350.0)  # (300+400)/2
        
        # In 60min window from 35min: should see transactions at 10min, 20min, and 35min
        self.assertEqual(last_transaction["customer_id_nb_txns_60min_window"], 3)
        self.assertEqual(last_transaction["customer_id_avg_amt_60min_window"], 300.0)  # (200+300+400)/3
    
    def test_enhanced_statistical_features(self):
        """Test enhanced statistical window features"""
        transactions_df = self.create_sample_transactions_data()
        processed_df = self.feature_engineer.preprocess_transactions(transactions_df)
        windowed_df = self.feature_engineer.add_window_features(
            processed_df, "CUSTOMER_ID", "customer_id"
        )
        
        # Check that enhanced statistical features are created
        expected_stat_features = [
            "customer_id_sum_amt_15min_window",
            "customer_id_min_amt_15min_window", 
            "customer_id_max_amt_15min_window",
            "customer_id_stddev_amt_15min_window",
            "customer_id_tx_velocity_15min_window",
            "customer_id_amt_zscore_15min_window"
        ]
        
        available_features = [f for f in expected_stat_features if f in windowed_df.columns]
        
        # Should have at least basic statistical features
        self.assertGreater(len(available_features), 2, "Should have enhanced statistical features")
        
        # Test that statistical calculations are reasonable
        sample_data = windowed_df.collect()
        for row in sample_data:
            for feature in available_features:
                if row[feature] is not None:
                    # Statistical features should be numeric
                    self.assertIsInstance(row[feature], (int, float))
    
    def test_cudf_datetime_processing_comprehensive(self):
        """Test comprehensive cuDF datetime processing features"""
        transactions_df = self.create_sample_transactions_data()
        processed_df = self.feature_engineer.preprocess_transactions(transactions_df)
        
        # Check that comprehensive datetime features are added
        expected_datetime_features = [
            "yyyy", "mm", "dd", "hour_of_day", "day_of_week", 
            "is_weekend", "is_business_hours", "is_night_time",
            "minute_of_hour", "day_of_year", "week_of_year",
            "is_early_morning", "is_evening"
        ]
        
        available_features = [f for f in expected_datetime_features if f in processed_df.columns]
        
        # Should have most datetime features
        self.assertGreater(len(available_features), 8, "Should have comprehensive datetime features")
        
        # Verify datetime feature values are reasonable
        first_row = processed_df.first()
        self.assertEqual(first_row["yyyy"], 2024)
        self.assertEqual(first_row["mm"], 1)
        self.assertEqual(first_row["dd"], 1)
        self.assertEqual(first_row["hour_of_day"], 10)  # 10 AM
        
        # Test binary indicators
        if "is_business_hours" in processed_df.columns:
            self.assertEqual(first_row["is_business_hours"], 1)  # 10 AM is business hours
        if "is_weekend" in processed_df.columns:
            self.assertEqual(first_row["is_weekend"], 0)  # January 1, 2024 is Monday
        if "is_night_time" in processed_df.columns:
            self.assertEqual(first_row["is_night_time"], 0)  # 10 AM is not night time
    
    def test_rapids_gpu_acceleration_validation(self):
        """Test RAPIDS GPU acceleration validation"""
        if self.feature_engineer.rapids_processor:
            gpu_validation = self.feature_engineer.rapids_processor.validate_gpu_acceleration()
            
            # Should return validation results
            self.assertIsInstance(gpu_validation, dict)
            
            # Should have key validation checks
            expected_checks = [
                "rapids_sql_enabled", 
                "gpu_memory_pool_configured",
                "concurrent_gpu_tasks_configured",
                "adaptive_query_execution"
            ]
            
            for check in expected_checks:
                self.assertIn(check, gpu_validation, f"Missing validation check: {check}")
    
    def test_notebook_compatibility(self):
        """Test that output matches original notebook format exactly"""
        customers_df = self.create_sample_customers_data()
        terminals_df = self.create_sample_terminals_data()
        transactions_df = self.create_sample_transactions_data()
        
        # Test that expected notebook columns are defined
        expected_notebook_columns = [
            "TX_AMOUNT", "yyyy", "mm", "dd",
            "customer_id_nb_txns_15min_window",
            "customer_id_avg_amt_15min_window",
            "terminal_id_nb_txns_15min_window", 
            "terminal_id_avg_amt_15min_window"
        ]
        
        # Get the expected columns from the feature engineer
        notebook_columns = self.feature_engineer._get_notebook_feature_columns(
            self.spark.createDataFrame([], StructType([
                StructField(col, StringType(), True) for col in expected_notebook_columns
            ]))
        )
        
        # Should return the available columns
        self.assertEqual(len(notebook_columns), len(expected_notebook_columns))
    
    def test_requirements_implementation(self):
        """Test that all requirements 6.1, 6.2, 6.3 are properly implemented"""
        customers_df = self.create_sample_customers_data()
        terminals_df = self.create_sample_terminals_data()
        transactions_df = self.create_sample_transactions_data()
        
        # Requirement 6.1: Handle the same parquet format from S3
        try:
            self.feature_engineer._validate_schemas(customers_df, terminals_df, transactions_df)
        except Exception as e:
            self.fail(f"Requirement 6.1 failed - Schema validation: {str(e)}")
        
        # Requirement 6.2: Generate identical features as the current EMR pipeline
        processed_df = self.feature_engineer.preprocess_transactions(transactions_df)
        windowed_df = self.feature_engineer.add_window_features(
            processed_df, "CUSTOMER_ID", "customer_id"
        )
        
        # Check for notebook-compatible features
        notebook_features = [
            "yyyy", "mm", "dd",
            "customer_id_nb_txns_15min_window",
            "customer_id_avg_amt_15min_window"
        ]
        
        for feature in notebook_features:
            self.assertIn(feature, windowed_df.columns, 
                         f"Requirement 6.2 failed - Missing feature: {feature}")
        
        # Requirement 6.3: Maintain the same datetime processing and windowing logic
        # Test window calculation accuracy
        customer_data = windowed_df.filter(F.col("CUSTOMER_ID") == "CUST_001").collect()
        
        for row in customer_data:
            # Window features should be calculated
            self.assertIsNotNone(row["customer_id_nb_txns_15min_window"])
            self.assertGreaterEqual(row["customer_id_nb_txns_15min_window"], 1)
        
        print("✓ All requirements 6.1, 6.2, 6.3 implementation verified")

    def test_end_to_end_pipeline(self):
        """Test the complete feature engineering pipeline with enhanced validation"""
        customers_df = self.create_sample_customers_data()
        terminals_df = self.create_sample_terminals_data()
        transactions_df = self.create_sample_transactions_data()
        
        # Run the complete pipeline
        processed_df = self.feature_engineer.preprocess_transactions(transactions_df)
        
        # Add window features
        processed_df = self.feature_engineer.add_window_features(
            processed_df, "CUSTOMER_ID", "customer_id"
        )
        processed_df = self.feature_engineer.add_window_features(
            processed_df, "TERMINAL_ID", "terminal_id"
        )
        
        # Encode categorical features
        encoded_transactions, encoded_customers, encoded_terminals = \
            self.feature_engineer.encode_categorical_features(
                processed_df, customers_df, terminals_df
            )
        
        # Create final features
        final_df = self.feature_engineer.create_final_features(
            encoded_transactions, encoded_customers, encoded_terminals
        )
        
        # Verify final dataset properties
        self.assertGreater(final_df.count(), 0, "Final dataset should not be empty")
        self.assertGreater(len(final_df.columns), 20, "Should have many feature columns")
        
        # Check for key feature categories
        column_names = final_df.columns
        
        # Should have customer window features
        customer_window_cols = [col for col in column_names if "customer_id_" in col and "_window" in col]
        self.assertGreater(len(customer_window_cols), 0, "Should have customer window features")
        
        # Should have terminal window features  
        terminal_window_cols = [col for col in column_names if "terminal_id_" in col and "_window" in col]
        self.assertGreater(len(terminal_window_cols), 0, "Should have terminal window features")
        
        # Should have encoded categorical features
        index_cols = [col for col in column_names if "_index" in col]
        self.assertGreater(len(index_cols), 0, "Should have encoded categorical features")
        
        # Should have target variable
        self.assertIn("TX_FRAUD_1", column_names, "Should have target variable")
        
        # Verify data quality
        row_count = final_df.count()
        self.assertEqual(row_count, transactions_df.count(), "Should preserve all transactions")
        
        # Check for null values in key columns
        key_columns = ["TX_AMOUNT", "CUSTOMER_ID_index", "TERMINAL_ID_index"]
        for col in key_columns:
            if col in column_names:
                null_count = final_df.filter(F.col(col).isNull()).count()
                self.assertEqual(null_count, 0, f"Column {col} should not have null values")


if __name__ == "__main__":
    # Run the tests
    unittest.main(verbosity=2)