#!/usr/bin/env python3
"""
Batch Inference Script for EMR on EKS

This script performs batch inference using a trained XGBoost model
on new transaction data for fraud detection.

Requirements addressed: 4.1, 4.2
"""

import sys
import os
from pyspark.sql import SparkSession
from pyspark.sql import functions as F
from pyspark.ml.classification import GBTClassificationModel
from pyspark.ml.feature import VectorAssembler
import argparse
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def create_spark_session():
    """Create Spark session with EMR on EKS configuration"""
    
    spark = SparkSession.builder \
        .appName("Fraud Detection Batch Inference - EMR on EKS") \
        .config("spark.serializer", "org.apache.spark.serializer.KryoSerializer") \
        .config("spark.sql.adaptive.enabled", "true") \
        .config("spark.sql.adaptive.coalescePartitions.enabled", "true") \
        .config("spark.rapids.sql.enabled", "true") \
        .config("spark.plugins", "com.nvidia.spark.SQLPlugin") \
        .getOrCreate()
    
    logger.info(f"Spark session created - Version: {spark.version}")
    logger.info(f"RAPIDS SQL Enabled: {spark.conf.get('spark.rapids.sql.enabled')}")
    
    return spark


def load_model(spark, model_path):
    """Load trained XGBoost model from S3"""
    
    logger.info(f"Loading trained model from: {model_path}")
    
    try:
        model = GBTClassificationModel.load(model_path)
        logger.info("Model loaded successfully")
        return model
    except Exception as e:
        logger.error(f"Failed to load model: {str(e)}")
        raise


def load_inference_data(spark, input_data_path):
    """Load data for inference"""
    
    logger.info(f"Loading inference data from: {input_data_path}")
    
    # Load the data (assuming it's in the same format as training data)
    inference_df = spark.read.parquet(input_data_path)
    
    logger.info(f"Inference data loaded - Rows: {inference_df.count()}")
    logger.info(f"Inference data loaded - Columns: {len(inference_df.columns)}")
    
    return inference_df


def prepare_inference_data(inference_df):
    """Prepare data for inference"""
    
    logger.info("Preparing inference data...")
    
    # Define feature columns (same as training, exclude target and ID columns)
    feature_columns = [col for col in inference_df.columns 
                      if col not in ['TX_FRAUD_0', 'TX_FRAUD_1', 'CUSTOMER_ID_index', 'TERMINAL_ID_index']]
    
    logger.info(f"Using {len(feature_columns)} features for inference")
    
    # Create feature vector
    assembler = VectorAssembler(
        inputCols=feature_columns,
        outputCol="features",
        handleInvalid="skip"
    )
    
    # Assemble features
    prepared_df = assembler.transform(inference_df)
    
    logger.info("Data preparation completed")
    
    return prepared_df, feature_columns


def perform_inference(model, prepared_df):
    """Perform batch inference"""
    
    logger.info("Performing batch inference...")
    
    # Make predictions
    predictions_df = model.transform(prepared_df)
    
    # Extract prediction results
    results_df = predictions_df.select(
        "CUSTOMER_ID_index",
        "TERMINAL_ID_index", 
        "TX_AMOUNT",
        "yyyy", "mm", "dd",
        F.col("prediction").alias("fraud_prediction"),
        F.col("probability").getItem(1).alias("fraud_probability")
    )
    
    # Add additional derived columns
    results_df = results_df.withColumn(
        "fraud_risk_level",
        F.when(F.col("fraud_probability") >= 0.8, "HIGH")
         .when(F.col("fraud_probability") >= 0.5, "MEDIUM")
         .otherwise("LOW")
    )
    
    # Add processing timestamp
    results_df = results_df.withColumn(
        "prediction_timestamp",
        F.current_timestamp()
    )
    
    logger.info("Batch inference completed")
    
    # Show prediction statistics
    total_predictions = results_df.count()
    fraud_predictions = results_df.filter(F.col("fraud_prediction") == 1.0).count()
    high_risk_predictions = results_df.filter(F.col("fraud_risk_level") == "HIGH").count()
    
    logger.info(f"Prediction statistics:")
    logger.info(f"  Total predictions: {total_predictions}")
    logger.info(f"  Predicted fraudulent: {fraud_predictions}")
    logger.info(f"  High risk transactions: {high_risk_predictions}")
    logger.info(f"  Fraud prediction rate: {fraud_predictions/total_predictions*100:.2f}%")
    
    return results_df


def save_predictions(results_df, predictions_output_path):
    """Save prediction results to S3"""
    
    logger.info(f"Saving predictions to: {predictions_output_path}")
    
    # Repartition for optimal output
    results_df = results_df.repartition(100)
    
    # Save as Parquet
    results_df.write.mode("overwrite").parquet(predictions_output_path)
    
    logger.info("Predictions saved successfully")
    
    # Also save a summary
    summary_path = predictions_output_path.replace("/batch-results/", "/batch-summary/")
    
    summary_df = results_df.groupBy("fraud_risk_level") \
        .agg(
            F.count("*").alias("transaction_count"),
            F.avg("fraud_probability").alias("avg_fraud_probability"),
            F.avg("TX_AMOUNT").alias("avg_transaction_amount")
        )
    
    summary_df.write.mode("overwrite").parquet(summary_path)
    
    logger.info(f"Summary saved to: {summary_path}")
    
    return predictions_output_path


def main():
    """Main execution function"""
    
    parser = argparse.ArgumentParser(description='Batch Inference on EMR on EKS')
    parser.add_argument('--model-path',
                        required=True,
                        help='S3 path to trained model')
    parser.add_argument('--input-data-path',
                        required=True,
                        help='S3 path to data for inference')
    parser.add_argument('--predictions-output-path',
                        required=True,
                        help='S3 path for predictions output')
    parser.add_argument('--fraud-threshold',
                        type=float,
                        default=0.5,
                        help='Fraud probability threshold')
    
    args = parser.parse_args()
    
    logger.info("=== Batch Inference Job Started ===")
    logger.info(f"Model path: {args.model_path}")
    logger.info(f"Input data path: {args.input_data_path}")
    logger.info(f"Predictions output path: {args.predictions_output_path}")
    logger.info(f"Fraud threshold: {args.fraud_threshold}")
    
    try:
        # Create Spark session
        spark = create_spark_session()
        
        # Load model
        model = load_model(spark, args.model_path)
        
        # Load inference data
        inference_df = load_inference_data(spark, args.input_data_path)
        
        # Prepare data
        prepared_df, feature_columns = prepare_inference_data(inference_df)
        
        # Perform inference
        results_df = perform_inference(model, prepared_df)
        
        # Save predictions
        output_path = save_predictions(results_df, args.predictions_output_path)
        
        logger.info("=== Batch Inference Job Completed Successfully ===")
        logger.info(f"Predictions saved to: {output_path}")
        
    except Exception as e:
        logger.error(f"Batch inference job failed: {str(e)}")
        raise
    
    finally:
        # Clean up
        if 'spark' in locals():
            spark.stop()
            logger.info("Spark session stopped")


if __name__ == "__main__":
    main()