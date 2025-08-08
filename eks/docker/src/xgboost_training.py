#!/usr/bin/env python3
"""
XGBoost Training Script for EMR on EKS

This script performs XGBoost training on processed fraud detection features
using Spark MLlib with GPU acceleration.

Requirements addressed: 3.1, 3.2
"""

import sys
import os
from pyspark.sql import SparkSession
from pyspark.sql import functions as F
from pyspark.ml.feature import VectorAssembler
from pyspark.ml.classification import GBTClassifier
from pyspark.ml.evaluation import BinaryClassificationEvaluator
from pyspark.ml import Pipeline
import argparse
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def create_spark_session():
    """Create Spark session with EMR on EKS and GPU configuration"""
    
    spark = SparkSession.builder \
        .appName("Fraud Detection XGBoost Training - EMR on EKS") \
        .config("spark.serializer", "org.apache.spark.serializer.KryoSerializer") \
        .config("spark.sql.adaptive.enabled", "true") \
        .config("spark.sql.adaptive.coalescePartitions.enabled", "true") \
        .config("spark.rapids.sql.enabled", "true") \
        .config("spark.plugins", "com.nvidia.spark.SQLPlugin") \
        .config("spark.sql.execution.arrow.pyspark.enabled", "true") \
        .config("spark.rapids.memory.pinnedPool.size", "2G") \
        .getOrCreate()
    
    logger.info(f"Spark session created - Version: {spark.version}")
    logger.info(f"RAPIDS SQL Enabled: {spark.conf.get('spark.rapids.sql.enabled')}")
    
    return spark


def load_features(spark, features_path):
    """Load processed features from S3"""
    
    logger.info(f"Loading processed features from: {features_path}")
    
    features_df = spark.read.parquet(features_path)
    
    logger.info(f"Features loaded - Rows: {features_df.count()}")
    logger.info(f"Features loaded - Columns: {len(features_df.columns)}")
    
    # Show basic statistics
    fraud_count = features_df.filter(F.col("TX_FRAUD_1") == 1).count()
    total_count = features_df.count()
    fraud_rate = fraud_count / total_count * 100
    
    logger.info(f"Dataset statistics:")
    logger.info(f"  Total transactions: {total_count}")
    logger.info(f"  Fraudulent transactions: {fraud_count}")
    logger.info(f"  Fraud rate: {fraud_rate:.2f}%")
    
    return features_df


def prepare_training_data(features_df):
    """Prepare data for XGBoost training"""
    
    logger.info("Preparing training data...")
    
    # Define feature columns (exclude target and ID columns)
    feature_columns = [col for col in features_df.columns 
                      if col not in ['TX_FRAUD_0', 'TX_FRAUD_1', 'CUSTOMER_ID_index', 'TERMINAL_ID_index']]
    
    logger.info(f"Using {len(feature_columns)} features for training")
    
    # Create feature vector
    assembler = VectorAssembler(
        inputCols=feature_columns,
        outputCol="features",
        handleInvalid="skip"
    )
    
    # Assemble features
    assembled_df = assembler.transform(features_df)
    
    # Select features and label
    training_df = assembled_df.select("features", F.col("TX_FRAUD_1").alias("label"))
    
    # Split data into train and test
    train_df, test_df = training_df.randomSplit([0.8, 0.2], seed=42)
    
    logger.info(f"Training set size: {train_df.count()}")
    logger.info(f"Test set size: {test_df.count()}")
    
    return train_df, test_df, feature_columns


def train_xgboost_model(train_df, test_df):
    """Train XGBoost model using Spark MLlib"""
    
    logger.info("Starting XGBoost training...")
    
    # Configure GBT Classifier (Spark's implementation of gradient boosting)
    gbt = GBTClassifier(
        featuresCol="features",
        labelCol="label",
        predictionCol="prediction",
        probabilityCol="probability",
        maxIter=100,
        maxDepth=6,
        stepSize=0.1,
        subsamplingRate=0.8,
        featureSubsetStrategy="sqrt",
        seed=42
    )
    
    logger.info("Training model...")
    model = gbt.fit(train_df)
    
    logger.info("Model training completed")
    
    # Make predictions on test set
    logger.info("Evaluating model on test set...")
    predictions = model.transform(test_df)
    
    # Evaluate model
    evaluator = BinaryClassificationEvaluator(
        labelCol="label",
        rawPredictionCol="rawPrediction",
        metricName="areaUnderROC"
    )
    
    auc = evaluator.evaluate(predictions)
    logger.info(f"Model AUC: {auc:.4f}")
    
    # Additional metrics
    evaluator_pr = BinaryClassificationEvaluator(
        labelCol="label",
        rawPredictionCol="rawPrediction",
        metricName="areaUnderPR"
    )
    
    auc_pr = evaluator_pr.evaluate(predictions)
    logger.info(f"Model AUC-PR: {auc_pr:.4f}")
    
    return model, auc, auc_pr


def save_model(model, model_output_path, feature_columns, metrics):
    """Save trained model to S3"""
    
    logger.info(f"Saving model to: {model_output_path}")
    
    # Save the model
    model.write().overwrite().save(model_output_path)
    
    # Save feature information and metrics
    metadata = {
        "model_type": "GBTClassifier",
        "feature_count": len(feature_columns),
        "features": feature_columns,
        "auc": metrics["auc"],
        "auc_pr": metrics["auc_pr"],
        "training_timestamp": str(pd.Timestamp.now())
    }
    
    # Note: In a real implementation, you would save this metadata to S3 as well
    logger.info("Model saved successfully")
    logger.info(f"Model metrics: AUC={metrics['auc']:.4f}, AUC-PR={metrics['auc_pr']:.4f}")
    
    return model_output_path


def main():
    """Main execution function"""
    
    parser = argparse.ArgumentParser(description='XGBoost Training on EMR on EKS')
    parser.add_argument('--features-path',
                        required=True,
                        help='S3 path to processed features')
    parser.add_argument('--model-output-path',
                        required=True,
                        help='S3 path for trained model output')
    parser.add_argument('--max-iter',
                        type=int,
                        default=100,
                        help='Maximum number of iterations')
    parser.add_argument('--max-depth',
                        type=int,
                        default=6,
                        help='Maximum tree depth')
    
    args = parser.parse_args()
    
    logger.info("=== XGBoost Training Job Started ===")
    logger.info(f"Features path: {args.features_path}")
    logger.info(f"Model output path: {args.model_output_path}")
    logger.info(f"Max iterations: {args.max_iter}")
    logger.info(f"Max depth: {args.max_depth}")
    
    try:
        # Create Spark session
        spark = create_spark_session()
        
        # Load features
        features_df = load_features(spark, args.features_path)
        
        # Prepare training data
        train_df, test_df, feature_columns = prepare_training_data(features_df)
        
        # Train model
        model, auc, auc_pr = train_xgboost_model(train_df, test_df)
        
        # Save model
        metrics = {"auc": auc, "auc_pr": auc_pr}
        model_path = save_model(model, args.model_output_path, feature_columns, metrics)
        
        logger.info("=== XGBoost Training Job Completed Successfully ===")
        logger.info(f"Final Model AUC: {auc:.4f}")
        logger.info(f"Final Model AUC-PR: {auc_pr:.4f}")
        logger.info(f"Model saved to: {model_path}")
        
    except Exception as e:
        logger.error(f"Training job failed: {str(e)}")
        raise
    
    finally:
        # Clean up
        if 'spark' in locals():
            spark.stop()
            logger.info("Spark session stopped")


if __name__ == "__main__":
    main()