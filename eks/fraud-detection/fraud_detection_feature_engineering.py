#!/usr/bin/env python3
"""
Fraud Detection Feature Engineering with RAPIDS GPU Acceleration
EMR on EKS implementation based on existing Jupyter notebook logic

This script processes fraud detection data using Spark with RAPIDS GPU acceleration
for high-performance feature engineering on customer transactions.

Enhanced with cuDF-optimized functions for GPU acceleration and comprehensive
datetime processing and windowing logic matching the original notebook.
"""

import sys
import time
import logging
from typing import Dict, List, Tuple
from datetime import datetime

from pyspark.sql import SparkSession, DataFrame
from pyspark.sql import functions as F
from pyspark.sql.window import Window
from pyspark.sql.types import *
from pyspark.ml.feature import StringIndexer
from pyspark.sql.functions import broadcast

# Import RAPIDS utilities
try:
    from rapids_utils import RapidsDataProcessor, create_rapids_optimized_spark_session
    RAPIDS_AVAILABLE = True
except ImportError:
    RAPIDS_AVAILABLE = False
    logging.warning("RAPIDS utilities not available, falling back to standard Spark")

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class FraudDetectionFeatureEngineering:
    """
    Fraud Detection Feature Engineering with RAPIDS GPU acceleration
    """
    
    def __init__(self, spark: SparkSession):
        self.spark = spark
        # Time windows matching the original notebook
        self.time_windows = {
            "15min": 15 * 60,
            "30min": 30 * 60,
            "60min": 60 * 60,
            "1day": 24 * 60 * 60,
            "7day": 7 * 24 * 60 * 60,
            "15day": 15 * 24 * 60 * 60,
            "30day": 30 * 24 * 60 * 60
        }
        
        # Initialize RAPIDS processor if available
        if RAPIDS_AVAILABLE:
            self.rapids_processor = RapidsDataProcessor(spark)
            logger.info("RAPIDS GPU acceleration enabled")
        else:
            self.rapids_processor = None
            logger.info("Using standard Spark processing")
        
    def load_datasets(self, customers_path: str, terminals_path: str, 
                     transactions_path: str) -> Tuple[DataFrame, DataFrame, DataFrame]:
        """
        Load and validate input datasets from S3
        """
        logger.info("Loading datasets from S3...")
        
        try:
            # Load datasets with optimized partitioning
            customers_df = self.spark.read.parquet(customers_path).repartition(300)
            terminals_df = self.spark.read.parquet(terminals_path)
            transactions_df = self.spark.read.parquet(transactions_path).repartition(1000)
            
            logger.info(f"Loaded customers: {customers_df.count()} rows")
            logger.info(f"Loaded terminals: {terminals_df.count()} rows")
            logger.info(f"Loaded transactions: {transactions_df.count()} rows")
            
            # Validate schemas
            self._validate_schemas(customers_df, terminals_df, transactions_df)
            
            return customers_df, terminals_df, transactions_df
            
        except Exception as e:
            logger.error(f"Error loading datasets: {str(e)}")
            raise
    
    def _validate_schemas(self, customers_df: DataFrame, terminals_df: DataFrame, 
                         transactions_df: DataFrame):
        """
        Validate that required columns exist in datasets
        """
        required_customer_cols = ["CUSTOMER_ID", "x_customer_id", "y_customer_id", 
                                "mean_amount", "std_amount", "mean_nb_tx_per_day"]
        required_terminal_cols = ["TERMINAL_ID", "x_terminal_id", "y_terminal_id"]
        required_transaction_cols = ["TX_DATETIME", "CUSTOMER_ID", "TERMINAL_ID", 
                                   "TX_AMOUNT", "TX_FRAUD", "TX_TIME_SECONDS", "TX_TIME_DAYS"]
        
        for col in required_customer_cols:
            if col not in customers_df.columns:
                raise ValueError(f"Missing required column in customers: {col}")
                
        for col in required_terminal_cols:
            if col not in terminals_df.columns:
                raise ValueError(f"Missing required column in terminals: {col}")
                
        for col in required_transaction_cols:
            if col not in transactions_df.columns:
                raise ValueError(f"Missing required column in transactions: {col}")
    
    def preprocess_transactions(self, transactions_df: DataFrame) -> DataFrame:
        """
        Preprocess transactions data with datetime parsing and partitioning
        Enhanced with cuDF-optimized datetime processing matching notebook logic exactly
        Implements requirements 6.1, 6.2, 6.3 for data pipeline compatibility
        """
        logger.info("Preprocessing transactions data with enhanced cuDF optimizations...")
        
        # Requirement 6.1: Handle the same parquet format from S3
        # Convert TX_DATETIME to timestamp if it's a string (matching notebook)
        if transactions_df.schema["TX_DATETIME"].dataType == StringType():
            transactions_df = transactions_df.withColumn(
                "TX_DATETIME", F.col("TX_DATETIME").cast("timestamp")
            )
        
        # Apply cuDF optimizations if available for GPU acceleration
        if self.rapids_processor:
            # Optimize DataFrame partitioning for GPU processing first
            transactions_df = self.rapids_processor.optimize_dataframe_for_gpu(
                transactions_df, ["CUSTOMER_ID", "TERMINAL_ID"], 1000
            )
            
            # Apply comprehensive cuDF-optimized datetime processing (Requirements 6.2, 6.3)
            transactions_df = self.rapids_processor.gpu_optimized_datetime_processing(
                transactions_df, "TX_DATETIME"
            )
            
            # Validate GPU acceleration is working
            gpu_validation = self.rapids_processor.validate_gpu_acceleration()
            logger.info(f"cuDF GPU acceleration validation: {gpu_validation}")
            
            # Add notebook-compatible column aliases for backward compatibility
            transactions_df = transactions_df.withColumn("yyyy", F.col("year")) \
                                           .withColumn("mm", F.col("month")) \
                                           .withColumn("dd", F.col("day")) \
                                           .withColumn("hour_of_day", F.col("hour")) \
                                           .withColumn("day_of_week", F.col("dayofweek")) \
                                           .withColumn("minute_of_hour", F.col("minute")) \
                                           .withColumn("day_of_year", F.col("dayofyear")) \
                                           .withColumn("week_of_year", F.col("weekofyear"))
            
            # Create TX_TIME_SECONDS for window operations if not present
            if "TX_TIME_SECONDS" not in transactions_df.columns:
                transactions_df = transactions_df.withColumn(
                    "TX_TIME_SECONDS", F.col("time_seconds")
                )
            
            logger.info("Applied comprehensive cuDF GPU optimizations with enhanced features")
        else:
            # Fallback to standard Spark processing (Requirement 6.2)
            # Extract date components matching notebook exactly
            transactions_df = transactions_df.withColumn(
                "yyyy", F.year(F.col("TX_DATETIME"))
            ).withColumn(
                "mm", F.month(F.col("TX_DATETIME"))
            ).withColumn(
                "dd", F.dayofmonth(F.col("TX_DATETIME"))
            )
            
            # Create TX_TIME_SECONDS for window operations
            if "TX_TIME_SECONDS" not in transactions_df.columns:
                transactions_df = transactions_df.withColumn(
                    "TX_TIME_SECONDS", F.unix_timestamp(F.col("TX_DATETIME"))
                )
            
            # Enhanced datetime processing with time-based features (Requirement 6.3)
            transactions_df = transactions_df.withColumn(
                "hour_of_day", F.hour(F.col("TX_DATETIME"))
            ).withColumn(
                "day_of_week", F.dayofweek(F.col("TX_DATETIME"))
            ).withColumn(
                "is_weekend", F.when(F.dayofweek(F.col("TX_DATETIME")).isin([1, 7]), 1).otherwise(0)
            ).withColumn(
                "is_business_hours", F.when((F.hour(F.col("TX_DATETIME")) >= 9) & 
                                           (F.hour(F.col("TX_DATETIME")) <= 17), 1).otherwise(0)
            ).withColumn(
                "is_night_time", F.when((F.hour(F.col("TX_DATETIME")) >= 22) | 
                                       (F.hour(F.col("TX_DATETIME")) <= 6), 1).otherwise(0)
            ).withColumn(
                "minute_of_hour", F.minute(F.col("TX_DATETIME"))
            ).withColumn(
                "day_of_year", F.dayofyear(F.col("TX_DATETIME"))
            ).withColumn(
                "week_of_year", F.weekofyear(F.col("TX_DATETIME"))
            ).withColumn(
                "is_early_morning", F.when((F.hour(F.col("TX_DATETIME")) >= 6) & 
                                          (F.hour(F.col("TX_DATETIME")) <= 9), 1).otherwise(0)
            ).withColumn(
                "is_evening", F.when((F.hour(F.col("TX_DATETIME")) >= 17) & 
                                    (F.hour(F.col("TX_DATETIME")) <= 22), 1).otherwise(0)
            )
            
            # Cache the preprocessed data for better performance in CPU mode
            transactions_df.cache()
            logger.info("Applied CPU processing with enhanced datetime features")
        
        logger.info("Transactions preprocessing completed with enhanced cuDF optimizations")
        return transactions_df
    
    def add_window_features(self, transactions_df: DataFrame, entity_id_col: str, 
                          prefix: str) -> DataFrame:
        """
        Add time-based window features for customer or terminal analysis
        Uses cuDF-optimized window functions for GPU acceleration
        Matches the original notebook logic exactly with enhanced RAPIDS features
        Implements requirements 6.1, 6.2, 6.3 for windowing logic compatibility
        """
        logger.info(f"Adding enhanced cuDF-optimized window features for {prefix}...")
        
        # Use RAPIDS-optimized window aggregation if available
        if self.rapids_processor:
            # Convert time windows to list of seconds for cuDF optimization (Requirement 6.3)
            window_sizes = list(self.time_windows.values())
            
            # Use cuDF-optimized windowing with notebook-compatible naming (Requirement 6.2)
            transactions_df = self.rapids_processor.cudf_optimized_windowing(
                transactions_df, [entity_id_col], "TX_TIME_SECONDS", "TX_AMOUNT", window_sizes
            )
            
            logger.info(f"cuDF-optimized window features for {prefix} completed with enhanced features")
        else:
            # Standard Spark window functions (matching notebook exactly - Requirement 6.2)
            for window_name, window_duration in self.time_windows.items():
                # Define window specification using TX_DATETIME cast to long for exact notebook match
                # This matches the original notebook approach exactly: F.col("TX_DATETIME").cast("long")
                window_spec = Window.partitionBy(entity_id_col).orderBy(
                    F.col("TX_DATETIME").cast("long")
                ).rangeBetween(-window_duration, 0)
                
                # Number of transactions in the time window (exact notebook match)
                transactions_df = transactions_df.withColumn(
                    f"{prefix}_nb_txns_{window_name}_window",
                    F.count("*").over(window_spec)
                )
                
                # Average transaction amount in the time window (exact notebook match)
                transactions_df = transactions_df.withColumn(
                    f"{prefix}_avg_amt_{window_name}_window",
                    F.avg("TX_AMOUNT").over(window_spec)
                )
                
                # Additional statistical features for enhanced fraud detection
                transactions_df = transactions_df.withColumn(
                    f"{prefix}_sum_amt_{window_name}_window",
                    F.sum("TX_AMOUNT").over(window_spec)
                ).withColumn(
                    f"{prefix}_min_amt_{window_name}_window",
                    F.min("TX_AMOUNT").over(window_spec)
                ).withColumn(
                    f"{prefix}_max_amt_{window_name}_window",
                    F.max("TX_AMOUNT").over(window_spec)
                ).withColumn(
                    f"{prefix}_stddev_amt_{window_name}_window",
                    F.stddev("TX_AMOUNT").over(window_spec)
                ).withColumn(
                    f"{prefix}_variance_amt_{window_name}_window",
                    F.variance("TX_AMOUNT").over(window_spec)
                )
                
                # Add velocity and risk features for fraud detection
                transactions_df = transactions_df.withColumn(
                    f"{prefix}_tx_velocity_{window_name}_window",
                    F.col(f"{prefix}_nb_txns_{window_name}_window") / (window_duration / 3600.0)
                ).withColumn(
                    f"{prefix}_amt_velocity_{window_name}_window",
                    F.col(f"{prefix}_sum_amt_{window_name}_window") / (window_duration / 3600.0)
                ).withColumn(
                    f"{prefix}_amt_zscore_{window_name}_window",
                    F.when(F.col(f"{prefix}_stddev_amt_{window_name}_window") > 0,
                           (F.col("TX_AMOUNT") - F.col(f"{prefix}_avg_amt_{window_name}_window")) /
                           F.col(f"{prefix}_stddev_amt_{window_name}_window")
                    ).otherwise(0.0)
                ).withColumn(
                    f"{prefix}_amt_ratio_{window_name}_window",
                    F.when(F.col(f"{prefix}_avg_amt_{window_name}_window") > 0,
                           F.col("TX_AMOUNT") / F.col(f"{prefix}_avg_amt_{window_name}_window")
                    ).otherwise(1.0)
                )
            
            logger.info(f"Standard Spark window features for {prefix} completed with enhanced features")
        
        return transactions_df
    
    def encode_categorical_features(self, transactions_df: DataFrame, 
                                  customers_df: DataFrame, 
                                  terminals_df: DataFrame) -> Tuple[DataFrame, DataFrame, DataFrame]:
        """
        Apply ordinal encoding to categorical features using StringIndexer
        Enhanced to match the original notebook logic exactly
        """
        logger.info("Encoding categorical features with RAPIDS optimizations...")
        
        # Ordinal Encoding for CUSTOMER_ID - fit on transactions, apply to both
        customer_indexer = StringIndexer(
            inputCol="CUSTOMER_ID",
            outputCol="CUSTOMER_ID_index",
            handleInvalid="keep"
        ).fit(transactions_df)
        
        transactions_df = customer_indexer.transform(transactions_df)
        customers_df = customer_indexer.transform(customers_df)
        
        # Ordinal Encoding for TERMINAL_ID - fit on transactions, apply to both
        terminal_indexer = StringIndexer(
            inputCol="TERMINAL_ID",
            outputCol="TERMINAL_ID_index",
            handleInvalid="keep"
        ).fit(transactions_df)
        
        transactions_df = terminal_indexer.transform(transactions_df)
        terminals_df = terminal_indexer.transform(terminals_df)
        
        # Encode customer categorical columns (matching notebook)
        customer_categorical_cols = ['customer_name', 'customer_email', 'phone']
        
        for column in customer_categorical_cols:
            if column in customers_df.columns:
                indexer = StringIndexer(
                    inputCol=column,
                    outputCol=f"{column}_index",
                    handleInvalid="keep"
                ).fit(customers_df)
                customers_df = indexer.transform(customers_df)
        
        # Handle billing_city and billing_state separately (as in notebook)
        if 'billing_city' in customers_df.columns:
            billing_city_indexer = StringIndexer(
                inputCol="billing_city",
                outputCol="billing_city_index",
                handleInvalid="keep"
            ).fit(customers_df)
            customers_df = billing_city_indexer.transform(customers_df)
            customers_df = customers_df.drop("billing_city")
            
        if 'billing_state' in customers_df.columns:
            billing_state_indexer = StringIndexer(
                inputCol="billing_state",
                outputCol="billing_state_index",
                handleInvalid="keep"
            ).fit(customers_df)
            customers_df = billing_state_indexer.transform(customers_df)
            customers_df = customers_df.drop("billing_state")
        
        # Handle merchant encoding (matching notebook logic)
        if 'merchant' in transactions_df.columns:
            merchant_indexer = StringIndexer(
                inputCol='merchant',
                outputCol='merchant_index',
                handleInvalid="keep"
            ).fit(transactions_df)
            transactions_df = merchant_indexer.transform(transactions_df)
            transactions_df = transactions_df.drop('merchant')
            
        if 'merchant' in terminals_df.columns:
            merchant_indexer_terminals = StringIndexer(
                inputCol='merchant',
                outputCol='merchant_index',
                handleInvalid="keep"
            ).fit(terminals_df)
            terminals_df = merchant_indexer_terminals.transform(terminals_df)
        
        # One-hot encoding for fraud labels
        transactions_df = transactions_df.withColumn(
            "TX_FRAUD_0", (F.col("TX_FRAUD") == 0).cast("int")
        ).withColumn(
            "TX_FRAUD_1", (F.col("TX_FRAUD") == 1).cast("int")
        )
        
        # Drop original TX_FRAUD and TX_DATETIME columns (as in notebook)
        transactions_df = transactions_df.drop("TX_FRAUD", "TX_DATETIME")
        
        logger.info("Categorical encoding completed with RAPIDS optimizations")
        return transactions_df, customers_df, terminals_df
    
    def create_final_features(self, transactions_df: DataFrame, 
                            customers_df: DataFrame, 
                            terminals_df: DataFrame) -> DataFrame:
        """
        Create final feature set by joining all datasets and selecting relevant columns
        Matches the original notebook logic exactly with RAPIDS optimizations
        """
        logger.info("Creating final feature set with RAPIDS optimizations...")
        
        # Broadcast smaller tables for efficient joins (as in notebook)
        customers_broadcast = broadcast(customers_df)
        terminals_broadcast = broadcast(terminals_df)
        
        # Join on indexed columns (as in notebook)
        final_df = transactions_df.join(
            customers_broadcast,
            "CUSTOMER_ID_index",
            "left"
        ).join(
            terminals_broadcast,
            "TERMINAL_ID_index", 
            "left"
        )
        
        # Select final columns matching the notebook exactly
        final_columns = self._get_notebook_feature_columns(final_df)
        final_df = final_df.select(*final_columns)
        
        # Repartition for optimal performance (as in notebook)
        final_df = final_df.repartition(10000)
        
        # Fill null values with 0 for numerical stability
        final_df = final_df.fillna(0)
        
        logger.info(f"Final feature set created with {len(final_columns)} columns")
        return final_df
    
    def _get_notebook_feature_columns(self, df: DataFrame) -> List[str]:
        """
        Get list of feature columns matching the original notebook exactly
        """
        # Final columns as defined in the original notebook
        final_columns = [
            "CUSTOMER_ID_index",
            "customer_name_index",
            "customer_email_index", 
            "phone_index",
            "billing_zip",
            "billing_city_index",
            "billing_state_index",
            "x_customer_id",
            "y_customer_id",
            "TX_AMOUNT",
            "TX_FRAUD_0",
            "TX_FRAUD_1",
            "TERMINAL_ID_index",
            "merchant_index",
            "yyyy",
            "mm", 
            "dd",
            # Customer-related features
            "customer_id_nb_txns_15min_window",
            "customer_id_nb_txns_30min_window",
            "customer_id_nb_txns_60min_window",
            "customer_id_nb_txns_1day_window",
            "customer_id_nb_txns_7day_window",
            "customer_id_nb_txns_15day_window",
            "customer_id_nb_txns_30day_window",
            "customer_id_avg_amt_15min_window",
            "customer_id_avg_amt_30min_window",
            "customer_id_avg_amt_60min_window",
            "customer_id_avg_amt_1day_window",
            "customer_id_avg_amt_7day_window",
            "customer_id_avg_amt_15day_window",
            "customer_id_avg_amt_30day_window",
            # Terminal-related features
            "terminal_id_nb_txns_15min_window",
            "terminal_id_nb_txns_30min_window",
            "terminal_id_nb_txns_60min_window",
            "terminal_id_nb_txns_1day_window",
            "terminal_id_nb_txns_7day_window",
            "terminal_id_nb_txns_15day_window",
            "terminal_id_nb_txns_30day_window",
            "terminal_id_avg_amt_15min_window",
            "terminal_id_avg_amt_30min_window",
            "terminal_id_avg_amt_60min_window",
            "terminal_id_avg_amt_1day_window",
            "terminal_id_avg_amt_7day_window",
            "terminal_id_avg_amt_15day_window",
            "terminal_id_avg_amt_30day_window"
        ]
        
        # Filter to only include columns that exist in the dataframe
        available_features = [col for col in final_columns if col in df.columns]
        
        return available_features
    
    def run_feature_engineering(self, customers_path: str, terminals_path: str, 
                              transactions_path: str, output_path: str) -> DataFrame:
        """
        Main feature engineering pipeline
        """
        start_time = time.time()
        logger.info("Starting fraud detection feature engineering pipeline...")
        
        try:
            # Load datasets
            customers_df, terminals_df, transactions_df = self.load_datasets(
                customers_path, terminals_path, transactions_path
            )
            
            # Preprocess transactions
            transactions_df = self.preprocess_transactions(transactions_df)
            
            # Add customer-based window features
            transactions_df = self.add_window_features(
                transactions_df, "CUSTOMER_ID", "customer_id"
            )
            
            # Add terminal-based window features
            transactions_df = self.add_window_features(
                transactions_df, "TERMINAL_ID", "terminal_id"
            )
            
            # Encode categorical features
            transactions_df, customers_df, terminals_df = self.encode_categorical_features(
                transactions_df, customers_df, terminals_df
            )
            
            # Create final feature set
            final_df = self.create_final_features(
                transactions_df, customers_df, terminals_df
            )
            
            # Save results
            logger.info(f"Saving results to {output_path}")
            final_df.write.mode("overwrite").parquet(output_path)
            
            end_time = time.time()
            logger.info(f"Feature engineering completed in {end_time - start_time:.2f} seconds")
            
            return final_df
            
        except Exception as e:
            logger.error(f"Feature engineering failed: {str(e)}")
            raise


def main():
    """
    Main entry point for the fraud detection feature engineering job
    """
    if len(sys.argv) != 5:
        print("Usage: fraud_detection_feature_engineering.py <customers_path> <terminals_path> <transactions_path> <output_path>")
        sys.exit(1)
    
    customers_path = sys.argv[1]
    terminals_path = sys.argv[2]
    transactions_path = sys.argv[3]
    output_path = sys.argv[4]
    
    # Create Spark session with enhanced RAPIDS configuration
    spark = SparkSession.builder \
        .appName("FraudDetectionFeatureEngineering") \
        .config("spark.plugins", "com.nvidia.spark.SQLPlugin") \
        .config("spark.rapids.sql.enabled", "true") \
        .config("spark.rapids.sql.concurrentGpuTasks", "2") \
        .config("spark.rapids.sql.explain", "ALL") \
        .config("spark.rapids.memory.pinnedPool.size", "2G") \
        .config("spark.rapids.memory.gpu.pool", "ASYNC") \
        .config("spark.rapids.memory.gpu.allocFraction", "0.6") \
        .config("spark.sql.adaptive.enabled", "true") \
        .config("spark.sql.adaptive.coalescePartitions.enabled", "true") \
        .config("spark.sql.files.maxPartitionBytes", "128M") \
        .config("spark.sql.autoBroadcastJoinThreshold", "500M") \
        .config("spark.serializer", "org.apache.spark.serializer.KryoSerializer") \
        .config("spark.kryoserializer.buffer.max", "2047m") \
        .config("spark.shuffle.compress", "true") \
        .config("spark.shuffle.spill.compress", "true") \
        .getOrCreate()
    
    try:
        # Initialize feature engineering pipeline
        feature_engineer = FraudDetectionFeatureEngineering(spark)
        
        # Run feature engineering
        result_df = feature_engineer.run_feature_engineering(
            customers_path, terminals_path, transactions_path, output_path
        )
        
        # Show sample results
        logger.info("Sample of processed data:")
        result_df.show(10, truncate=False)
        
        logger.info("Feature engineering job completed successfully")
        
    except Exception as e:
        logger.error(f"Job failed: {str(e)}")
        sys.exit(1)
    finally:
        spark.stop()


if __name__ == "__main__":
    main()