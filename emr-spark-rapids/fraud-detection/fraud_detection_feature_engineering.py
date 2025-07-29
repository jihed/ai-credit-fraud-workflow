#!/usr/bin/env python3
"""
Fraud Detection Feature Engineering with RAPIDS GPU Acceleration
EMR on EKS implementation based on existing Jupyter notebook logic

This script processes fraud detection data using Spark with RAPIDS GPU acceleration
for high-performance feature engineering on customer transactions.
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
        self.time_windows = {
            "1min": 1 * 60,
            "5min": 5 * 60,
            "15min": 15 * 60,
            "30min": 30 * 60,
            "1hour": 60 * 60,
            "6hour": 6 * 60 * 60,
            "12hour": 12 * 60 * 60,
            "1day": 24 * 60 * 60,
            "3day": 3 * 24 * 60 * 60,
            "7day": 7 * 24 * 60 * 60
        }
        
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
                                   "TX_AMOUNT", "TX_FRAUD"]
        
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
        """
        logger.info("Preprocessing transactions data...")
        
        # Convert TX_DATETIME to timestamp and extract date components
        transactions_df = transactions_df.withColumn(
            "TX_DATETIME", F.to_timestamp(F.col("TX_DATETIME"))
        ).withColumn(
            "yyyy", F.year(F.col("TX_DATETIME"))
        ).withColumn(
            "mm", F.month(F.col("TX_DATETIME"))
        ).withColumn(
            "dd", F.dayofmonth(F.col("TX_DATETIME"))
        )
        
        # Add TX_TIME_SECONDS for window calculations
        transactions_df = transactions_df.withColumn(
            "TX_TIME_SECONDS", F.unix_timestamp(F.col("TX_DATETIME"))
        )
        
        logger.info("Transactions preprocessing completed")
        return transactions_df
    
    def add_window_features(self, transactions_df: DataFrame, entity_id_col: str, 
                          prefix: str) -> DataFrame:
        """
        Add time-based window features for customer or terminal analysis
        Uses RAPIDS-optimized window functions for GPU acceleration
        """
        logger.info(f"Adding window features for {prefix}...")
        
        for window_name, window_duration in self.time_windows.items():
            # Define window specification for time-based analysis
            window_spec = Window.partitionBy(entity_id_col).orderBy(
                F.col("TX_TIME_SECONDS")
            ).rangeBetween(-window_duration, 0)
            
            # Number of transactions in the time window
            transactions_df = transactions_df.withColumn(
                f"{prefix}_nb_txns_{window_name}_window",
                F.count("*").over(window_spec)
            )
            
            # Average transaction amount in the time window
            transactions_df = transactions_df.withColumn(
                f"{prefix}_avg_amt_{window_name}_window",
                F.avg("TX_AMOUNT").over(window_spec)
            )
            
            # Standard deviation of transaction amounts
            transactions_df = transactions_df.withColumn(
                f"{prefix}_std_amt_{window_name}_window",
                F.stddev("TX_AMOUNT").over(window_spec)
            )
            
            # Maximum transaction amount in window
            transactions_df = transactions_df.withColumn(
                f"{prefix}_max_amt_{window_name}_window",
                F.max("TX_AMOUNT").over(window_spec)
            )
            
            # Minimum transaction amount in window
            transactions_df = transactions_df.withColumn(
                f"{prefix}_min_amt_{window_name}_window",
                F.min("TX_AMOUNT").over(window_spec)
            )
        
        logger.info(f"Window features for {prefix} completed")
        return transactions_df
    
    def encode_categorical_features(self, transactions_df: DataFrame, 
                                  customers_df: DataFrame, 
                                  terminals_df: DataFrame) -> Tuple[DataFrame, DataFrame, DataFrame]:
        """
        Apply ordinal encoding to categorical features using StringIndexer
        """
        logger.info("Encoding categorical features...")
        
        # Ordinal Encoding for CUSTOMER_ID
        customer_indexer = StringIndexer(
            inputCol="CUSTOMER_ID",
            outputCol="CUSTOMER_ID_index",
            handleInvalid="keep"
        ).fit(transactions_df)
        
        transactions_df = customer_indexer.transform(transactions_df)
        customers_df = customer_indexer.transform(customers_df)
        
        # Ordinal Encoding for TERMINAL_ID
        terminal_indexer = StringIndexer(
            inputCol="TERMINAL_ID",
            outputCol="TERMINAL_ID_index",
            handleInvalid="keep"
        ).fit(transactions_df)
        
        transactions_df = terminal_indexer.transform(transactions_df)
        terminals_df = terminal_indexer.transform(terminals_df)
        
        # Encode additional categorical columns in customers
        customer_categorical_cols = ['customer_name', 'customer_email', 'phone', 
                                   'billing_city', 'billing_state']
        
        for column in customer_categorical_cols:
            if column in customers_df.columns:
                indexer = StringIndexer(
                    inputCol=column,
                    outputCol=f"{column}_index",
                    handleInvalid="keep"
                ).fit(customers_df)
                customers_df = indexer.transform(customers_df)
        
        # Encode merchant column if present
        if 'merchant' in transactions_df.columns:
            merchant_indexer = StringIndexer(
                inputCol='merchant',
                outputCol='merchant_index',
                handleInvalid="keep"
            ).fit(transactions_df)
            transactions_df = merchant_indexer.transform(transactions_df)
            
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
        
        logger.info("Categorical encoding completed")
        return transactions_df, customers_df, terminals_df
    
    def create_final_features(self, transactions_df: DataFrame, 
                            customers_df: DataFrame, 
                            terminals_df: DataFrame) -> DataFrame:
        """
        Create final feature set by joining all datasets and selecting relevant columns
        """
        logger.info("Creating final feature set...")
        
        # Broadcast smaller tables for efficient joins
        customers_broadcast = broadcast(customers_df)
        terminals_broadcast = broadcast(terminals_df)
        
        # Join transactions with customers
        final_df = transactions_df.join(
            customers_broadcast,
            "CUSTOMER_ID",
            "left"
        )
        
        # Join with terminals
        final_df = final_df.join(
            terminals_broadcast,
            "TERMINAL_ID",
            "left"
        )
        
        # Select relevant feature columns
        feature_columns = self._get_feature_columns(final_df)
        final_df = final_df.select(*feature_columns)
        
        # Fill null values
        final_df = final_df.fillna(0)
        
        logger.info(f"Final feature set created with {len(feature_columns)} columns")
        return final_df
    
    def _get_feature_columns(self, df: DataFrame) -> List[str]:
        """
        Get list of feature columns for final dataset
        """
        # Base transaction features
        base_features = ["TX_AMOUNT", "yyyy", "mm", "dd"]
        
        # Window features (all columns containing '_window')
        window_features = [col for col in df.columns if '_window' in col]
        
        # Encoded categorical features
        encoded_features = [col for col in df.columns if '_index' in col]
        
        # Customer features
        customer_features = ["x_customer_id", "y_customer_id", "mean_amount", 
                           "std_amount", "mean_nb_tx_per_day"]
        
        # Terminal features
        terminal_features = ["x_terminal_id", "y_terminal_id"]
        
        # Target variable
        target_features = ["TX_FRAUD_1"]
        
        # Combine all features
        all_features = (base_features + window_features + encoded_features + 
                       customer_features + terminal_features + target_features)
        
        # Filter to only include columns that exist in the dataframe
        available_features = [col for col in all_features if col in df.columns]
        
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
    
    # Create Spark session with RAPIDS configuration
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