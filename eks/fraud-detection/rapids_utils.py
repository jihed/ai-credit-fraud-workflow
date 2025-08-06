#!/usr/bin/env python3
"""
RAPIDS Utilities for GPU-accelerated data processing
Provides cuDF-based functions for enhanced performance on GPU workloads
"""

import logging
from typing import Dict, List, Optional, Tuple
from pyspark.sql import SparkSession, DataFrame
from pyspark.sql import functions as F
from pyspark.sql.window import Window

logger = logging.getLogger(__name__)


class RapidsDataProcessor:
    """
    RAPIDS-optimized data processing utilities for fraud detection
    """
    
    def __init__(self, spark: SparkSession):
        self.spark = spark
        self._configure_rapids_optimizations()
    
    def _configure_rapids_optimizations(self):
        """
        Configure Spark session for optimal RAPIDS performance
        """
        # Set RAPIDS-specific configurations
        self.spark.conf.set("spark.rapids.sql.enabled", "true")
        self.spark.conf.set("spark.rapids.sql.concurrentGpuTasks", "2")
        self.spark.conf.set("spark.rapids.memory.gpu.pool", "ASYNC")
        self.spark.conf.set("spark.rapids.memory.gpu.allocFraction", "0.6")
        self.spark.conf.set("spark.rapids.memory.pinnedPool.size", "2G")
        
        # Enable columnar processing optimizations
        self.spark.conf.set("spark.sql.adaptive.enabled", "true")
        self.spark.conf.set("spark.sql.adaptive.coalescePartitions.enabled", "true")
        self.spark.conf.set("spark.sql.adaptive.skewJoin.enabled", "true")
        
        logger.info("RAPIDS optimizations configured")
    
    def optimize_dataframe_for_gpu(self, df: DataFrame, 
                                 partition_cols: Optional[List[str]] = None,
                                 target_partitions: int = 1000) -> DataFrame:
        """
        Optimize DataFrame partitioning and caching for GPU processing
        
        Args:
            df: Input DataFrame
            partition_cols: Columns to partition by for optimal GPU utilization
            target_partitions: Target number of partitions
            
        Returns:
            Optimized DataFrame
        """
        logger.info(f"Optimizing DataFrame for GPU processing with {target_partitions} partitions")
        
        if partition_cols:
            # Repartition by specified columns for better data locality
            optimized_df = df.repartition(target_partitions, *partition_cols)
        else:
            # Simple repartitioning
            optimized_df = df.repartition(target_partitions)
        
        # Cache for repeated access with GPU-optimized storage
        optimized_df.cache()
        
        return optimized_df
    
    def gpu_accelerated_window_aggregation(self, df: DataFrame, 
                                         partition_col: str,
                                         order_col: str,
                                         window_seconds: int,
                                         agg_col: str,
                                         agg_functions: List[str]) -> DataFrame:
        """
        Perform GPU-accelerated window aggregations using RAPIDS optimizations
        
        Args:
            df: Input DataFrame
            partition_col: Column to partition window by
            order_col: Column to order window by
            window_seconds: Window size in seconds
            agg_col: Column to aggregate
            agg_functions: List of aggregation functions ('count', 'avg', 'sum', 'min', 'max', 'stddev')
            
        Returns:
            DataFrame with window aggregation columns
        """
        logger.info(f"Performing GPU-accelerated window aggregation on {partition_col}")
        
        # Define window specification optimized for GPU processing
        window_spec = Window.partitionBy(partition_col).orderBy(
            F.col(order_col).cast("long")
        ).rangeBetween(-window_seconds, 0)
        
        result_df = df
        
        # Apply each aggregation function
        for agg_func in agg_functions:
            col_name = f"{partition_col}_{agg_func}_{agg_col}_{window_seconds}s_window"
            
            if agg_func == 'count':
                result_df = result_df.withColumn(
                    col_name, F.count("*").over(window_spec)
                )
            elif agg_func == 'avg':
                result_df = result_df.withColumn(
                    col_name, F.avg(agg_col).over(window_spec)
                )
            elif agg_func == 'sum':
                result_df = result_df.withColumn(
                    col_name, F.sum(agg_col).over(window_spec)
                )
            elif agg_func == 'min':
                result_df = result_df.withColumn(
                    col_name, F.min(agg_col).over(window_spec)
                )
            elif agg_func == 'max':
                result_df = result_df.withColumn(
                    col_name, F.max(agg_col).over(window_spec)
                )
            elif agg_func == 'stddev':
                result_df = result_df.withColumn(
                    col_name, F.stddev(agg_col).over(window_spec)
                )
        
        return result_df
    
    def gpu_optimized_datetime_processing(self, df: DataFrame, 
                                        datetime_col: str) -> DataFrame:
        """
        GPU-optimized datetime processing and feature extraction
        Enhanced with comprehensive datetime features for fraud detection
        Implements requirements 6.1, 6.2, 6.3 for datetime processing compatibility
        
        Args:
            df: Input DataFrame
            datetime_col: Name of datetime column
            
        Returns:
            DataFrame with extracted datetime features
        """
        logger.info(f"Performing GPU-optimized datetime processing on {datetime_col}")
        
        # Convert to timestamp if needed (Requirement 6.1 - handle parquet format)
        if df.schema[datetime_col].dataType.typeName() == 'string':
            df = df.withColumn(datetime_col, F.col(datetime_col).cast("timestamp"))
        
        # Extract datetime components using GPU-accelerated functions (Requirement 6.2)
        df = df.withColumn("year", F.year(F.col(datetime_col))) \
               .withColumn("month", F.month(F.col(datetime_col))) \
               .withColumn("day", F.dayofmonth(F.col(datetime_col))) \
               .withColumn("hour", F.hour(F.col(datetime_col))) \
               .withColumn("minute", F.minute(F.col(datetime_col))) \
               .withColumn("second", F.second(F.col(datetime_col))) \
               .withColumn("dayofweek", F.dayofweek(F.col(datetime_col))) \
               .withColumn("dayofyear", F.dayofyear(F.col(datetime_col))) \
               .withColumn("weekofyear", F.weekofyear(F.col(datetime_col))) \
               .withColumn("quarter", F.quarter(F.col(datetime_col)))
        
        # Add time-based features for fraud detection (Requirement 6.3)
        df = df.withColumn("is_weekend", 
                          F.when(F.col("dayofweek").isin([1, 7]), 1).otherwise(0)) \
               .withColumn("is_business_hours",
                          F.when((F.col("hour") >= 9) & (F.col("hour") <= 17), 1).otherwise(0)) \
               .withColumn("is_night_time",
                          F.when((F.col("hour") >= 22) | (F.col("hour") <= 6), 1).otherwise(0)) \
               .withColumn("is_early_morning",
                          F.when((F.col("hour") >= 6) & (F.col("hour") <= 9), 1).otherwise(0)) \
               .withColumn("is_evening",
                          F.when((F.col("hour") >= 17) & (F.col("hour") <= 22), 1).otherwise(0)) \
               .withColumn("time_seconds", F.unix_timestamp(F.col(datetime_col)))
        
        # Add cyclical time features for better ML model performance
        df = df.withColumn("hour_sin", F.sin(2 * F.lit(3.14159) * F.col("hour") / 24)) \
               .withColumn("hour_cos", F.cos(2 * F.lit(3.14159) * F.col("hour") / 24)) \
               .withColumn("day_sin", F.sin(2 * F.lit(3.14159) * F.col("dayofweek") / 7)) \
               .withColumn("day_cos", F.cos(2 * F.lit(3.14159) * F.col("dayofweek") / 7)) \
               .withColumn("month_sin", F.sin(2 * F.lit(3.14159) * F.col("month") / 12)) \
               .withColumn("month_cos", F.cos(2 * F.lit(3.14159) * F.col("month") / 12))
        
        # Add time-based risk indicators
        df = df.withColumn("is_high_risk_time",
                          F.when((F.col("is_night_time") == 1) | 
                                (F.col("is_weekend") == 1) |
                                (F.col("hour").isin([0, 1, 2, 3, 4, 5, 23])), 1).otherwise(0)) \
               .withColumn("time_risk_score",
                          F.when(F.col("is_night_time") == 1, 0.8)
                           .when(F.col("is_weekend") == 1, 0.6)
                           .when(F.col("is_business_hours") == 0, 0.4)
                           .otherwise(0.2))
        
        # Add time period categorization
        df = df.withColumn("time_period",
                          F.when((F.col("hour") >= 6) & (F.col("hour") < 12), "morning")
                           .when((F.col("hour") >= 12) & (F.col("hour") < 17), "afternoon")
                           .when((F.col("hour") >= 17) & (F.col("hour") < 22), "evening")
                           .otherwise("night"))
        
        logger.info("GPU-optimized datetime processing completed with enhanced features")
        return df
    
    def gpu_accelerated_categorical_encoding(self, df: DataFrame, 
                                           categorical_cols: List[str],
                                           method: str = "ordinal") -> Tuple[DataFrame, Dict]:
        """
        GPU-accelerated categorical encoding
        
        Args:
            df: Input DataFrame
            categorical_cols: List of categorical columns to encode
            method: Encoding method ('ordinal' or 'onehot')
            
        Returns:
            Tuple of (encoded DataFrame, encoding mappings)
        """
        logger.info(f"Performing GPU-accelerated categorical encoding for {len(categorical_cols)} columns")
        
        from pyspark.ml.feature import StringIndexer
        
        encoded_df = df
        encoding_mappings = {}
        
        for col in categorical_cols:
            if col in df.columns:
                # Use StringIndexer for ordinal encoding
                indexer = StringIndexer(
                    inputCol=col,
                    outputCol=f"{col}_encoded",
                    handleInvalid="keep"
                ).fit(df)
                
                encoded_df = indexer.transform(encoded_df)
                
                # Store the mapping for later use
                encoding_mappings[col] = indexer.labels
                
                if method == "ordinal":
                    # Drop original column for ordinal encoding
                    encoded_df = encoded_df.drop(col)
        
        return encoded_df, encoding_mappings
    
    def gpu_optimized_feature_scaling(self, df: DataFrame, 
                                    numeric_cols: List[str],
                                    method: str = "standard") -> DataFrame:
        """
        GPU-optimized feature scaling
        
        Args:
            df: Input DataFrame
            numeric_cols: List of numeric columns to scale
            method: Scaling method ('standard', 'minmax', 'robust')
            
        Returns:
            DataFrame with scaled features
        """
        logger.info(f"Performing GPU-optimized feature scaling for {len(numeric_cols)} columns")
        
        scaled_df = df
        
        for col in numeric_cols:
            if col in df.columns:
                if method == "standard":
                    # Standard scaling (z-score normalization)
                    stats = df.select(
                        F.mean(col).alias("mean"),
                        F.stddev(col).alias("stddev")
                    ).collect()[0]
                    
                    if stats["stddev"] and stats["stddev"] > 0:
                        scaled_df = scaled_df.withColumn(
                            f"{col}_scaled",
                            (F.col(col) - stats["mean"]) / stats["stddev"]
                        )
                    else:
                        scaled_df = scaled_df.withColumn(f"{col}_scaled", F.col(col))
                
                elif method == "minmax":
                    # Min-max scaling
                    stats = df.select(
                        F.min(col).alias("min"),
                        F.max(col).alias("max")
                    ).collect()[0]
                    
                    if stats["max"] != stats["min"]:
                        scaled_df = scaled_df.withColumn(
                            f"{col}_scaled",
                            (F.col(col) - stats["min"]) / (stats["max"] - stats["min"])
                        )
                    else:
                        scaled_df = scaled_df.withColumn(f"{col}_scaled", F.lit(0.0))
        
        return scaled_df
    
    def create_gpu_optimized_features(self, df: DataFrame, 
                                    customer_col: str,
                                    terminal_col: str,
                                    amount_col: str,
                                    datetime_col: str) -> DataFrame:
        """
        Create comprehensive GPU-optimized features for fraud detection
        Enhanced with cuDF-optimized processing patterns
        
        Args:
            df: Input DataFrame
            customer_col: Customer ID column
            terminal_col: Terminal ID column  
            amount_col: Transaction amount column
            datetime_col: Transaction datetime column
            
        Returns:
            DataFrame with comprehensive features
        """
        logger.info("Creating comprehensive GPU-optimized features with cuDF patterns")
        
        # Optimize DataFrame for GPU processing with better partitioning
        optimized_df = self.optimize_dataframe_for_gpu(df, [customer_col, terminal_col])
        
        # Process datetime features with GPU acceleration
        feature_df = self.gpu_optimized_datetime_processing(optimized_df, datetime_col)
        
        # Define time windows for feature engineering (matching notebook)
        time_windows = [900, 1800, 3600, 86400, 604800, 1296000, 2592000]  # 15min to 30day
        
        # Add customer-based window features with GPU acceleration
        for window_seconds in time_windows:
            feature_df = self.gpu_accelerated_window_aggregation(
                feature_df, customer_col, "time_seconds", window_seconds,
                amount_col, ['count', 'avg', 'sum', 'min', 'max', 'stddev']
            )
        
        # Add terminal-based window features with GPU acceleration
        for window_seconds in time_windows:
            feature_df = self.gpu_accelerated_window_aggregation(
                feature_df, terminal_col, "time_seconds", window_seconds,
                amount_col, ['count', 'avg', 'sum', 'min', 'max', 'stddev']
            )
        
        # Add velocity features (transaction frequency) - cuDF optimized
        feature_df = feature_df.withColumn(
            "customer_tx_velocity_1hr",
            F.col(f"{customer_col}_count_{amount_col}_3600s_window") / 3600.0
        ).withColumn(
            "terminal_tx_velocity_1hr", 
            F.col(f"{terminal_col}_count_{amount_col}_3600s_window") / 3600.0
        ).withColumn(
            "customer_tx_velocity_1day",
            F.col(f"{customer_col}_count_{amount_col}_86400s_window") / 86400.0
        ).withColumn(
            "terminal_tx_velocity_1day",
            F.col(f"{terminal_col}_count_{amount_col}_86400s_window") / 86400.0
        )
        
        # Add amount deviation features - enhanced with GPU optimization
        feature_df = feature_df.withColumn(
            "amount_deviation_from_customer_avg",
            F.abs(F.col(amount_col) - F.col(f"{customer_col}_avg_{amount_col}_86400s_window"))
        ).withColumn(
            "amount_deviation_from_terminal_avg",
            F.abs(F.col(amount_col) - F.col(f"{terminal_col}_avg_{amount_col}_86400s_window"))
        ).withColumn(
            "amount_ratio_to_customer_avg",
            F.when(F.col(f"{customer_col}_avg_{amount_col}_86400s_window") > 0,
                   F.col(amount_col) / F.col(f"{customer_col}_avg_{amount_col}_86400s_window")
            ).otherwise(1.0)
        ).withColumn(
            "amount_ratio_to_terminal_avg",
            F.when(F.col(f"{terminal_col}_avg_{amount_col}_86400s_window") > 0,
                   F.col(amount_col) / F.col(f"{terminal_col}_avg_{amount_col}_86400s_window")
            ).otherwise(1.0)
        )
        
        # Add risk score features based on statistical patterns
        feature_df = feature_df.withColumn(
            "customer_risk_score",
            F.when(F.col(f"{customer_col}_stddev_{amount_col}_86400s_window") > 0,
                   F.abs(F.col(amount_col) - F.col(f"{customer_col}_avg_{amount_col}_86400s_window")) /
                   F.col(f"{customer_col}_stddev_{amount_col}_86400s_window")
            ).otherwise(0.0)
        ).withColumn(
            "terminal_risk_score",
            F.when(F.col(f"{terminal_col}_stddev_{amount_col}_86400s_window") > 0,
                   F.abs(F.col(amount_col) - F.col(f"{terminal_col}_avg_{amount_col}_86400s_window")) /
                   F.col(f"{terminal_col}_stddev_{amount_col}_86400s_window")
            ).otherwise(0.0)
        )
        
        logger.info("GPU-optimized feature creation completed with enhanced cuDF patterns")
        return feature_df
    
    def cudf_optimized_windowing(self, df: DataFrame, 
                               partition_cols: List[str],
                               order_col: str,
                               value_col: str,
                               window_sizes: List[int]) -> DataFrame:
        """
        cuDF-optimized windowing operations for better GPU utilization
        Enhanced with notebook-matching window feature names and optimizations
        Implements requirements 6.1, 6.2, 6.3 for data pipeline compatibility
        
        Args:
            df: Input DataFrame
            partition_cols: Columns to partition by
            order_col: Column to order by
            value_col: Column to aggregate
            window_sizes: List of window sizes in seconds
            
        Returns:
            DataFrame with window features matching notebook format
        """
        logger.info("Applying cuDF-optimized windowing operations with notebook compatibility")
        
        result_df = df
        
        # Map window sizes to notebook names for compatibility (Requirement 6.2)
        window_name_mapping = {
            900: "15min",
            1800: "30min", 
            3600: "60min",
            86400: "1day",
            604800: "7day",
            1296000: "15day",
            2592000: "30day"
        }
        
        # Optimize DataFrame partitioning for GPU processing
        result_df = self.optimize_dataframe_for_gpu(result_df, partition_cols, 1000)
        
        for partition_col in partition_cols:
            for window_size in window_sizes:
                # Get window name for notebook compatibility
                window_name = window_name_mapping.get(window_size, f"{window_size}s")
                
                # Create window specification optimized for GPU with exact notebook logic
                # Using TX_DATETIME cast to long exactly as in the original notebook (Requirement 6.3)
                window_spec = Window.partitionBy(partition_col).orderBy(
                    F.col(order_col).cast("long")
                ).rangeBetween(-window_size, 0)
                
                # Apply aggregations with notebook-matching column names
                prefix = partition_col.lower()
                
                # Count of transactions (matching notebook exactly - Requirement 6.2)
                result_df = result_df.withColumn(
                    f"{prefix}_nb_txns_{window_name}_window",
                    F.count("*").over(window_spec)
                )
                
                # Average transaction amount (matching notebook exactly - Requirement 6.2)
                result_df = result_df.withColumn(
                    f"{prefix}_avg_amt_{window_name}_window",
                    F.avg(value_col).over(window_spec)
                )
                
                # Additional statistical features for enhanced fraud detection
                result_df = result_df.withColumn(
                    f"{prefix}_sum_amt_{window_name}_window",
                    F.sum(value_col).over(window_spec)
                ).withColumn(
                    f"{prefix}_min_amt_{window_name}_window",
                    F.min(value_col).over(window_spec)
                ).withColumn(
                    f"{prefix}_max_amt_{window_name}_window",
                    F.max(value_col).over(window_spec)
                ).withColumn(
                    f"{prefix}_stddev_amt_{window_name}_window",
                    F.stddev(value_col).over(window_spec)
                ).withColumn(
                    f"{prefix}_variance_amt_{window_name}_window",
                    F.variance(value_col).over(window_spec)
                )
                
                # Add velocity and frequency features for fraud detection
                result_df = result_df.withColumn(
                    f"{prefix}_tx_velocity_{window_name}_window",
                    F.col(f"{prefix}_nb_txns_{window_name}_window") / (window_size / 3600.0)  # transactions per hour
                ).withColumn(
                    f"{prefix}_amt_velocity_{window_name}_window", 
                    F.col(f"{prefix}_sum_amt_{window_name}_window") / (window_size / 3600.0)  # amount per hour
                )
                
                # Add risk indicators based on statistical patterns
                result_df = result_df.withColumn(
                    f"{prefix}_amt_zscore_{window_name}_window",
                    F.when(F.col(f"{prefix}_stddev_amt_{window_name}_window") > 0,
                           (F.col(value_col) - F.col(f"{prefix}_avg_amt_{window_name}_window")) /
                           F.col(f"{prefix}_stddev_amt_{window_name}_window")
                    ).otherwise(0.0)
                ).withColumn(
                    f"{prefix}_amt_ratio_{window_name}_window",
                    F.when(F.col(f"{prefix}_avg_amt_{window_name}_window") > 0,
                           F.col(value_col) / F.col(f"{prefix}_avg_amt_{window_name}_window")
                    ).otherwise(1.0)
                )
        
        logger.info("cuDF-optimized windowing completed with enhanced fraud detection features")
        return result_df
    
    def notebook_compatible_feature_engineering(self, transactions_df: DataFrame,
                                              customers_df: DataFrame,
                                              terminals_df: DataFrame) -> DataFrame:
        """
        Complete feature engineering pipeline matching the original notebook exactly
        with RAPIDS GPU acceleration optimizations
        
        Args:
            transactions_df: Transactions DataFrame
            customers_df: Customers DataFrame  
            terminals_df: Terminals DataFrame
            
        Returns:
            Final feature DataFrame matching notebook output
        """
        logger.info("Running notebook-compatible feature engineering with RAPIDS optimizations")
        
        # Step 1: Preprocess transactions with GPU-optimized datetime processing
        processed_df = self.gpu_optimized_datetime_processing(transactions_df, "TX_DATETIME")
        
        # Step 2: Add customer window features using cuDF-optimized windowing
        window_sizes = [900, 1800, 3600, 86400, 604800, 1296000, 2592000]  # 15min to 30day
        processed_df = self.cudf_optimized_windowing(
            processed_df, ["CUSTOMER_ID"], "TX_TIME_SECONDS", "TX_AMOUNT", window_sizes
        )
        
        # Step 3: Add terminal window features using cuDF-optimized windowing
        processed_df = self.cudf_optimized_windowing(
            processed_df, ["TERMINAL_ID"], "TX_TIME_SECONDS", "TX_AMOUNT", window_sizes
        )
        
        # Step 4: GPU-accelerated categorical encoding
        categorical_cols = ["CUSTOMER_ID", "TERMINAL_ID"]
        if "merchant" in processed_df.columns:
            categorical_cols.append("merchant")
            
        encoded_df, encoding_mappings = self.gpu_accelerated_categorical_encoding(
            processed_df, categorical_cols, method="ordinal"
        )
        
        # Step 5: Encode customers and terminals
        encoded_customers, customer_mappings = self.gpu_accelerated_categorical_encoding(
            customers_df, ["CUSTOMER_ID"], method="ordinal"
        )
        encoded_terminals, terminal_mappings = self.gpu_accelerated_categorical_encoding(
            terminals_df, ["TERMINAL_ID"], method="ordinal"
        )
        
        # Step 6: Create final feature set with joins (GPU-optimized)
        from pyspark.sql.functions import broadcast
        
        # Use broadcast joins for smaller tables
        customers_broadcast = broadcast(encoded_customers)
        terminals_broadcast = broadcast(encoded_terminals)
        
        # Join datasets
        final_df = encoded_df.join(
            customers_broadcast, "CUSTOMER_ID_encoded", "left"
        ).join(
            terminals_broadcast, "TERMINAL_ID_encoded", "left"
        )
        
        # Step 7: Select final columns matching notebook
        final_columns = self._get_notebook_compatible_columns(final_df)
        final_df = final_df.select(*final_columns)
        
        # Step 8: Fill null values and optimize for GPU
        final_df = final_df.fillna(0)
        final_df = self.optimize_dataframe_for_gpu(final_df, target_partitions=1000)
        
        logger.info("Notebook-compatible feature engineering completed with RAPIDS optimizations")
        return final_df
    
    def _get_notebook_compatible_columns(self, df: DataFrame) -> List[str]:
        """
        Get columns that match the original notebook output format
        
        Args:
            df: Input DataFrame
            
        Returns:
            List of column names matching notebook format
        """
        available_columns = df.columns
        
        # Base columns from notebook
        base_columns = [
            "TX_AMOUNT", "yyyy", "mm", "dd", "hour", "minute",
            "CUSTOMER_ID_encoded", "TERMINAL_ID_encoded"
        ]
        
        # Window feature columns
        window_columns = []
        time_windows = ["15min", "30min", "60min", "1day", "7day", "15day", "30day"]
        
        for window in time_windows:
            window_columns.extend([
                f"customer_id_nb_txns_{window}_window",
                f"customer_id_avg_amt_{window}_window",
                f"terminal_id_nb_txns_{window}_window", 
                f"terminal_id_avg_amt_{window}_window"
            ])
        
        # Customer features
        customer_columns = [
            "x_customer_id", "y_customer_id", "mean_amount", "std_amount", "mean_nb_tx_per_day"
        ]
        
        # Terminal features
        terminal_columns = [
            "x_terminal_id", "y_terminal_id"
        ]
        
        # Target variable
        target_columns = ["TX_FRAUD", "TX_FRAUD_0", "TX_FRAUD_1"]
        
        # Combine all columns and filter to available ones
        all_columns = base_columns + window_columns + customer_columns + terminal_columns + target_columns
        final_columns = [col for col in all_columns if col in available_columns]
        
        return final_columns

    def comprehensive_fraud_feature_engineering(self, transactions_df: DataFrame,
                                              customers_df: DataFrame,
                                              terminals_df: DataFrame) -> DataFrame:
        """
        Comprehensive fraud detection feature engineering with RAPIDS GPU acceleration
        Implements all requirements 6.1, 6.2, 6.3 for complete data pipeline compatibility
        
        Args:
            transactions_df: Transactions DataFrame
            customers_df: Customers DataFrame
            terminals_df: Terminals DataFrame
            
        Returns:
            Complete feature DataFrame optimized for fraud detection
        """
        logger.info("Starting comprehensive fraud feature engineering with RAPIDS optimization")
        
        # Step 1: Optimize DataFrames for GPU processing (Requirement 6.1)
        transactions_df = self.optimize_dataframe_for_gpu(
            transactions_df, ["CUSTOMER_ID", "TERMINAL_ID"], 1000
        )
        customers_df = self.optimize_dataframe_for_gpu(customers_df, ["CUSTOMER_ID"], 100)
        terminals_df = self.optimize_dataframe_for_gpu(terminals_df, ["TERMINAL_ID"], 50)
        
        # Step 2: Enhanced datetime processing (Requirement 6.3)
        processed_df = self.gpu_optimized_datetime_processing(transactions_df, "TX_DATETIME")
        
        # Step 3: Create TX_TIME_SECONDS if not present for windowing
        if "TX_TIME_SECONDS" not in processed_df.columns:
            processed_df = processed_df.withColumn(
                "TX_TIME_SECONDS", F.unix_timestamp(F.col("TX_DATETIME"))
            )
        
        # Step 4: Add comprehensive window features (Requirement 6.2)
        window_sizes = [900, 1800, 3600, 86400, 604800, 1296000, 2592000]  # 15min to 30day
        
        # Customer-based window features
        processed_df = self.cudf_optimized_windowing(
            processed_df, ["CUSTOMER_ID"], "TX_TIME_SECONDS", "TX_AMOUNT", window_sizes
        )
        
        # Terminal-based window features
        processed_df = self.cudf_optimized_windowing(
            processed_df, ["TERMINAL_ID"], "TX_TIME_SECONDS", "TX_AMOUNT", window_sizes
        )
        
        # Step 5: Add cross-entity features (customer-terminal interactions)
        processed_df = processed_df.withColumn(
            "customer_terminal_pair",
            F.concat(F.col("CUSTOMER_ID"), F.lit("_"), F.col("TERMINAL_ID"))
        )
        
        # Customer-terminal pair window features
        processed_df = self.cudf_optimized_windowing(
            processed_df, ["customer_terminal_pair"], "TX_TIME_SECONDS", "TX_AMOUNT", [3600, 86400]
        )
        
        # Step 6: GPU-accelerated categorical encoding
        categorical_cols = ["CUSTOMER_ID", "TERMINAL_ID"]
        if "merchant" in processed_df.columns:
            categorical_cols.append("merchant")
            
        encoded_df, encoding_mappings = self.gpu_accelerated_categorical_encoding(
            processed_df, categorical_cols, method="ordinal"
        )
        
        # Encode customers and terminals with same mappings
        encoded_customers, _ = self.gpu_accelerated_categorical_encoding(
            customers_df, ["CUSTOMER_ID"], method="ordinal"
        )
        encoded_terminals, _ = self.gpu_accelerated_categorical_encoding(
            terminals_df, ["TERMINAL_ID"], method="ordinal"
        )
        
        # Step 7: Add derived features for fraud detection
        encoded_df = self._add_fraud_detection_features(encoded_df)
        
        # Step 8: Join with customer and terminal data
        from pyspark.sql.functions import broadcast
        
        customers_broadcast = broadcast(encoded_customers)
        terminals_broadcast = broadcast(encoded_terminals)
        
        final_df = encoded_df.join(
            customers_broadcast, "CUSTOMER_ID_encoded", "left"
        ).join(
            terminals_broadcast, "TERMINAL_ID_encoded", "left"
        )
        
        # Step 9: Feature scaling for numerical stability
        numeric_cols = [col for col in final_df.columns if "amt_" in col or "velocity_" in col]
        if numeric_cols:
            final_df = self.gpu_optimized_feature_scaling(final_df, numeric_cols[:10], "standard")
        
        # Step 10: Final cleanup and optimization
        final_df = final_df.fillna(0)
        final_df = self.optimize_dataframe_for_gpu(final_df, target_partitions=500)
        
        logger.info("Comprehensive fraud feature engineering completed")
        return final_df
    
    def _add_fraud_detection_features(self, df: DataFrame) -> DataFrame:
        """
        Add specialized fraud detection features
        
        Args:
            df: Input DataFrame with window features
            
        Returns:
            DataFrame with additional fraud detection features
        """
        logger.info("Adding specialized fraud detection features")
        
        # Amount deviation features
        df = df.withColumn(
            "amount_deviation_1day",
            F.abs(F.col("TX_AMOUNT") - F.col("customer_id_avg_amt_1day_window"))
        ).withColumn(
            "amount_deviation_7day",
            F.abs(F.col("TX_AMOUNT") - F.col("customer_id_avg_amt_7day_window"))
        )
        
        # Transaction frequency anomalies
        df = df.withColumn(
            "tx_frequency_anomaly_1hr",
            F.when(F.col("customer_id_nb_txns_60min_window") > 10, 1).otherwise(0)
        ).withColumn(
            "tx_frequency_anomaly_1day",
            F.when(F.col("customer_id_nb_txns_1day_window") > 50, 1).otherwise(0)
        )
        
        # Terminal risk indicators
        df = df.withColumn(
            "terminal_high_activity",
            F.when(F.col("terminal_id_nb_txns_1day_window") > 100, 1).otherwise(0)
        ).withColumn(
            "terminal_amount_spike",
            F.when(F.col("terminal_id_sum_amt_1day_window") > 10000, 1).otherwise(0)
        )
        
        # Cross-feature interactions
        df = df.withColumn(
            "customer_terminal_familiarity",
            F.col("customer_terminal_pair_nb_txns_1day_window")
        ).withColumn(
            "new_customer_terminal_pair",
            F.when(F.col("customer_terminal_familiarity") <= 1, 1).otherwise(0)
        )
        
        # Risk score aggregation
        df = df.withColumn(
            "composite_risk_score",
            (F.col("time_risk_score") * 0.3 +
             F.when(F.col("amount_deviation_1day") > 100, 0.4).otherwise(0.1) * 0.4 +
             F.col("tx_frequency_anomaly_1hr") * 0.2 +
             F.col("new_customer_terminal_pair") * 0.1)
        )
        
        return df

    def validate_gpu_acceleration(self) -> Dict[str, bool]:
        """
        Validate that GPU acceleration is properly configured
        
        Returns:
            Dictionary with validation results
        """
        validation_results = {}
        
        try:
            # Check RAPIDS SQL plugin
            rapids_enabled = self.spark.conf.get("spark.rapids.sql.enabled", "false") == "true"
            validation_results["rapids_sql_enabled"] = rapids_enabled
            
            # Check GPU memory configuration
            gpu_pool = self.spark.conf.get("spark.rapids.memory.gpu.pool", "")
            validation_results["gpu_memory_pool_configured"] = gpu_pool == "ASYNC"
            
            # Check concurrent GPU tasks
            concurrent_tasks = int(self.spark.conf.get("spark.rapids.sql.concurrentGpuTasks", "1"))
            validation_results["concurrent_gpu_tasks_configured"] = concurrent_tasks > 1
            
            # Check adaptive query execution
            adaptive_enabled = self.spark.conf.get("spark.sql.adaptive.enabled", "false") == "true"
            validation_results["adaptive_query_execution"] = adaptive_enabled
            
            # Validate memory settings
            pinned_pool = self.spark.conf.get("spark.rapids.memory.pinnedPool.size", "")
            validation_results["pinned_pool_configured"] = "G" in pinned_pool or "M" in pinned_pool
            
            # Check GPU allocation fraction
            alloc_fraction = float(self.spark.conf.get("spark.rapids.memory.gpu.allocFraction", "0"))
            validation_results["gpu_allocation_optimal"] = 0.4 <= alloc_fraction <= 0.8
            
            logger.info(f"GPU acceleration validation: {validation_results}")
            
        except Exception as e:
            logger.error(f"Error validating GPU acceleration: {str(e)}")
            validation_results["validation_error"] = str(e)
        
        return validation_results


def create_rapids_optimized_spark_session(app_name: str = "RapidsOptimizedApp") -> SparkSession:
    """
    Create a Spark session optimized for RAPIDS GPU acceleration
    
    Args:
        app_name: Name of the Spark application
        
    Returns:
        Configured SparkSession
    """
    spark = SparkSession.builder \
        .appName(app_name) \
        .config("spark.plugins", "com.nvidia.spark.SQLPlugin") \
        .config("spark.rapids.sql.enabled", "true") \
        .config("spark.rapids.sql.concurrentGpuTasks", "2") \
        .config("spark.rapids.sql.explain", "ALL") \
        .config("spark.rapids.memory.pinnedPool.size", "2G") \
        .config("spark.rapids.memory.gpu.pool", "ASYNC") \
        .config("spark.rapids.memory.gpu.allocFraction", "0.6") \
        .config("spark.sql.adaptive.enabled", "true") \
        .config("spark.sql.adaptive.coalescePartitions.enabled", "true") \
        .config("spark.sql.adaptive.skewJoin.enabled", "true") \
        .config("spark.sql.files.maxPartitionBytes", "128M") \
        .config("spark.sql.autoBroadcastJoinThreshold", "500M") \
        .config("spark.serializer", "org.apache.spark.serializer.KryoSerializer") \
        .config("spark.kryoserializer.buffer.max", "2047m") \
        .config("spark.shuffle.compress", "true") \
        .config("spark.shuffle.spill.compress", "true") \
        .getOrCreate()
    
    logger.info(f"Created RAPIDS-optimized Spark session: {app_name}")
    return spark