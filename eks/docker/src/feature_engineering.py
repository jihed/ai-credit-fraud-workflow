#!/usr/bin/env python3
"""
Feature Engineering Script for EMR on EKS

This script performs the same feature engineering as the original notebook
but is designed to run as a standalone EMR on EKS job.

Requirements addressed: 2.1, 2.2
"""

import sys
import os
from pyspark.sql import SparkSession
from pyspark.sql import functions as F
from pyspark.sql.window import Window
from pyspark.ml.feature import StringIndexer
from pyspark.sql.functions import year, month, dayofmonth, broadcast
import argparse
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def create_spark_session():
    """Create Spark session with EMR on EKS and RAPIDS configuration"""
    
    spark = SparkSession.builder \
        .appName("Fraud Detection Feature Engineering - EMR on EKS Job") \
        .config("spark.serializer", "org.apache.spark.serializer.KryoSerializer") \
        .config("spark.kryoserializer.buffer.max", "2047m") \
        .config("spark.shuffle.compress", "true") \
        .config("spark.shuffle.spill.compress", "true") \
        .config("spark.sql.adaptive.enabled", "true") \
        .config("spark.sql.adaptive.coalescePartitions.enabled", "true") \
        .config("spark.rapids.sql.enabled", "true") \
        .config("spark.plugins", "com.nvidia.spark.SQLPlugin") \
        .config("spark.rapids.memory.pinnedPool.size", "2G") \
        .config("spark.rapids.sql.concurrentGpuTasks", "2") \
        .getOrCreate()
    
    logger.info(f"Spark session created - Version: {spark.version}")
    logger.info(f"RAPIDS SQL Enabled: {spark.conf.get('spark.rapids.sql.enabled')}")
    
    return spark


def load_data(spark, customers_path, terminals_path, transactions_path):
    """Load datasets from S3"""
    
    logger.info("Loading datasets from S3...")
    logger.info(f"Customers: {customers_path}")
    logger.info(f"Terminals: {terminals_path}")
    logger.info(f"Transactions: {transactions_path}")
    
    customers_df = spark.read.parquet(customers_path).repartition(300)
    terminals_df = spark.read.parquet(terminals_path)
    transactions_df = spark.read.parquet(transactions_path).repartition(1000)
    
    # Broadcast smaller tables for efficient joins
    terminals_df = broadcast(terminals_df)
    
    logger.info("Data loading completed")
    logger.info(f"Customers partitions: {customers_df.rdd.getNumPartitions()}")
    logger.info(f"Transactions partitions: {transactions_df.rdd.getNumPartitions()}")
    
    return customers_df, terminals_df, transactions_df


def add_window_features(transactions_df, time_windows, entity_id_col, prefix):
    """Add time-window based features for customer and terminal analysis"""
    
    logger.info(f"Adding window features for {prefix}...")
    
    for window_name, window_duration in time_windows.items():
        logger.info(f"  Processing {window_name} window...")
        
        window_spec = Window.partitionBy(entity_id_col).orderBy(
            F.col("TX_DATETIME").cast("long")).rangeBetween(
                -window_duration, 0)

        # Number of transactions in the time window
        transactions_df = transactions_df.withColumn(
            f"{prefix}_nb_txns_{window_name}_window",
            F.count("*").over(window_spec))

        # Average transaction amount in the time window
        transactions_df = transactions_df.withColumn(
            f"{prefix}_avg_amt_{window_name}_window",
            F.avg("TX_AMOUNT").over(window_spec))

    logger.info(f"Window features completed for {prefix}")
    return transactions_df


def perform_feature_engineering(spark, customers_df, terminals_df, transactions_df):
    """Perform the complete feature engineering pipeline"""
    
    logger.info("Starting feature engineering pipeline...")
    
    # Convert TX_DATETIME and extract date components
    logger.info("Processing datetime features...")
    transactions_df = transactions_df.withColumn(
        "TX_DATETIME",
        F.col("TX_DATETIME").cast("timestamp"))

    transactions_df = transactions_df.withColumn("yyyy", year(F.col("TX_DATETIME"))) \
                                     .withColumn("mm", month(F.col("TX_DATETIME"))) \
                                     .withColumn("dd", dayofmonth(F.col("TX_DATETIME")))

    # Define time windows
    time_windows = {
        "15min": 15 * 60,
        "30min": 30 * 60,
        "60min": 60 * 60,
        "1day": 24 * 60 * 60,
        "7day": 7 * 24 * 60 * 60,
        "15day": 15 * 24 * 60 * 60,
        "30day": 30 * 24 * 60 * 60
    }
    
    # Add customer and terminal window features
    transactions_df = add_window_features(transactions_df, time_windows, "CUSTOMER_ID", "customer_id")
    transactions_df = add_window_features(transactions_df, time_windows, "TERMINAL_ID", "terminal_id")
    
    # Ordinal encoding
    logger.info("Performing ordinal encoding...")
    
    # Customer ID encoding
    customer_indexer = StringIndexer(inputCol="CUSTOMER_ID",
                                     outputCol="CUSTOMER_ID_index",
                                     handleInvalid="keep").fit(transactions_df)
    transactions_df = customer_indexer.transform(transactions_df)
    customers_df = customer_indexer.transform(customers_df)

    # Customer attributes encoding
    columns_to_encode_customers = ['customer_name', 'customer_email', 'phone']
    for column in columns_to_encode_customers:
        if column in customers_df.columns:
            logger.info(f"  Encoding {column}...")
            indexer = StringIndexer(inputCol=column,
                                    outputCol=f"{column}_index",
                                    handleInvalid="keep").fit(customers_df)
            customers_df = indexer.transform(customers_df)

    # Terminal ID encoding
    terminal_indexer = StringIndexer(inputCol="TERMINAL_ID",
                                     outputCol="TERMINAL_ID_index",
                                     handleInvalid="keep").fit(transactions_df)
    transactions_df = terminal_indexer.transform(transactions_df)
    terminals_df = terminal_indexer.transform(terminals_df)

    # Merchant encoding
    if 'merchant' in transactions_df.columns:
        logger.info("Encoding merchant in transactions...")
        merchant_indexer = StringIndexer(inputCol='merchant',
                                         outputCol='merchant_index',
                                         handleInvalid="keep").fit(transactions_df)
        transactions_df = merchant_indexer.transform(transactions_df)

    if 'merchant' in terminals_df.columns:
        logger.info("Encoding merchant in terminals...")
        merchant_indexer_terminals = StringIndexer(
            inputCol='merchant', outputCol='merchant_index',
            handleInvalid="keep").fit(terminals_df)
        terminals_df = merchant_indexer_terminals.transform(terminals_df)

    # One-hot encoding for fraud labels
    logger.info("Processing fraud labels...")
    transactions_df = transactions_df.withColumn(
        "TX_FRAUD_0", (F.col("TX_FRAUD") == 0).cast("int"))
    transactions_df = transactions_df.withColumn(
        "TX_FRAUD_1", (F.col("TX_FRAUD") == 1).cast("int"))

    # Drop original columns
    transactions_df = transactions_df.drop("TX_FRAUD", "TX_DATETIME")

    # Billing information encoding
    logger.info("Encoding billing information...")
    billing_city_indexer = StringIndexer(inputCol="billing_city", 
                                          outputCol="billing_city_index").fit(customers_df)
    customers_df = billing_city_indexer.transform(customers_df)

    billing_state_indexer = StringIndexer(inputCol="billing_state", 
                                           outputCol="billing_state_index").fit(customers_df)
    customers_df = billing_state_indexer.transform(customers_df)

    customers_df = customers_df.drop("billing_city", "billing_state")
    
    logger.info("Feature engineering pipeline completed")
    return customers_df, terminals_df, transactions_df


def join_and_select_features(customers_df, terminals_df, transactions_df):
    """Join datasets and select final features"""
    
    logger.info("Performing data joins...")
    
    final_df = transactions_df.join(customers_df,
                                    on="CUSTOMER_ID_index",
                                    how="left").join(terminals_df,
                                                     on="TERMINAL_ID_index",
                                                     how="left")
    
    # Select final feature columns
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
        # Customer window features
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
        # Terminal window features
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
    
    final_df = final_df.select(final_columns).repartition(5000)
    
    logger.info(f"Final dataset prepared with {len(final_columns)} features")
    logger.info(f"Final partitions: {final_df.rdd.getNumPartitions()}")
    
    return final_df


def save_results(spark, final_df, output_path):
    """Save processed features to S3"""
    
    logger.info("Configuring output settings...")
    
    # Optimize Spark settings for S3 output
    spark.conf.set("spark.sql.files.maxPartitionBytes", "128M")
    spark.conf.set("spark.sql.autoBroadcastJoinThreshold", "500M")
    spark.conf.set("spark.sql.adaptive.advisoryPartitionSizeInBytes", "128M")
    
    logger.info(f"Writing processed features to: {output_path}")
    logger.info("This may take several minutes...")
    
    final_df.write.mode("overwrite").parquet(output_path)
    
    logger.info(f"✅ Data successfully written to {output_path}")
    logger.info(f"✅ Feature engineering job completed successfully")


def main():
    """Main execution function"""
    
    parser = argparse.ArgumentParser(description='Fraud Detection Feature Engineering on EMR on EKS')
    parser.add_argument('--customers-path', 
                        default='s3://nvidia-aws-fraud-detection-demo-training-data/customers_parquet/',
                        help='S3 path to customers data')
    parser.add_argument('--terminals-path',
                        default='s3://nvidia-aws-fraud-detection-demo-training-data/terminals_parquet/',
                        help='S3 path to terminals data')
    parser.add_argument('--transactions-path',
                        default='s3://nvidia-aws-fraud-detection-demo-training-data/transactions_parquet/',
                        help='S3 path to transactions data')
    parser.add_argument('--output-path',
                        required=True,
                        help='S3 path for output processed features')
    
    args = parser.parse_args()
    
    logger.info("=== Fraud Detection Feature Engineering Job Started ===")
    logger.info(f"Customers path: {args.customers_path}")
    logger.info(f"Terminals path: {args.terminals_path}")
    logger.info(f"Transactions path: {args.transactions_path}")
    logger.info(f"Output path: {args.output_path}")
    
    try:
        # Create Spark session
        spark = create_spark_session()
        
        # Load data
        customers_df, terminals_df, transactions_df = load_data(
            spark, args.customers_path, args.terminals_path, args.transactions_path
        )
        
        # Perform feature engineering
        customers_df, terminals_df, transactions_df = perform_feature_engineering(
            spark, customers_df, terminals_df, transactions_df
        )
        
        # Join and select final features
        final_df = join_and_select_features(customers_df, terminals_df, transactions_df)
        
        # Save results
        save_results(spark, final_df, args.output_path)
        
        logger.info("=== Feature Engineering Job Completed Successfully ===")
        
    except Exception as e:
        logger.error(f"Feature engineering job failed: {str(e)}")
        raise
    
    finally:
        # Clean up
        if 'spark' in locals():
            spark.stop()
            logger.info("Spark session stopped")


if __name__ == "__main__":
    main()