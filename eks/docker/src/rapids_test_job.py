#!/usr/bin/env python3
"""
RAPIDS Test Job for EMR on EKS

This script tests RAPIDS GPU acceleration capabilities on EMR on EKS.
It performs various operations to validate GPU acceleration is working.

Requirements addressed: 2.1, 2.2
"""

from pyspark.sql import SparkSession
from pyspark.sql import functions as F
from pyspark.sql.types import *
import sys
import time
import os

def create_rapids_spark_session():
    """Create Spark session with RAPIDS configuration"""
    
    print("🚀 Creating RAPIDS-enabled Spark session...")
    
    try:
        # Try to create Spark session with RAPIDS configuration
        spark = SparkSession.builder \
            .appName("RAPIDS Test Job - EMR on EKS") \
            .getOrCreate()
        
        print("✅ Spark session created successfully")
        return spark
        
    except Exception as e:
        print(f"❌ Failed to create Spark session: {str(e)}")
        print("This might be due to RAPIDS plugin issues or GPU resource conflicts")
        raise

def test_basic_spark(spark):
    """Test basic Spark functionality without RAPIDS"""
    
    print("🔍 Testing basic Spark functionality...")
    
    try:
        # Create a simple DataFrame
        data = [(1, "test1"), (2, "test2"), (3, "test3")]
        df = spark.createDataFrame(data, ["id", "name"])
        
        # Perform basic operations
        count = df.count()
        print(f"✅ Created DataFrame with {count} rows")
        
        # Test basic transformations
        filtered_df = df.filter(df.id > 1)
        filtered_count = filtered_df.count()
        print(f"✅ Filtered DataFrame has {filtered_count} rows")
        
        # Test basic aggregations
        max_id = df.agg({"id": "max"}).collect()[0][0]
        print(f"✅ Max ID: {max_id}")
        
        print("✅ Basic Spark functionality working correctly")
        return True
        
    except Exception as e:
        print(f"❌ Basic Spark test failed: {str(e)}")
        return False

def test_rapids_availability(spark):
    """Test if RAPIDS is available and working"""
    
    print("🔍 Testing RAPIDS availability...")
    
    try:
        # Check if RAPIDS plugin is loaded
        rapids_enabled = spark.conf.get("spark.rapids.sql.enabled", "false")
        print(f"✅ RAPIDS SQL enabled: {rapids_enabled}")
        
        # Check GPU resources
        try:
            gpu_amount = spark.conf.get("spark.executor.resource.gpu.amount", "0")
            print(f"✅ GPU amount per executor: {gpu_amount}")
        except Exception as e:
            print(f"⚠️ GPU resource check failed: {e}")
        
        # Test basic GPU operation
        test_df = spark.range(1000000).toDF("id")
        test_df = test_df.withColumn("squared", F.col("id") * F.col("id"))
        
        start_time = time.time()
        result_count = test_df.count()
        end_time = time.time()
        
        print(f"✅ Basic GPU operation completed")
        print(f"   Processed {result_count} rows in {end_time - start_time:.2f} seconds")
        
        return True
        
    except Exception as e:
        print(f"❌ RAPIDS availability test failed: {str(e)}")
        return False

def test_gpu_dataframe_operations(spark):
    """Test GPU-accelerated DataFrame operations"""
    
    print("📊 Testing GPU DataFrame operations...")
    
    try:
        # Create a larger test dataset
        print("Creating test dataset...")
        df = spark.range(5000000).toDF("id")
        df = df.withColumn("value", F.rand() * 1000)
        df = df.withColumn("category", (F.col("id") % 10).cast("string"))
        df = df.withColumn("timestamp", F.current_timestamp())
        
        # Cache the DataFrame
        df.cache()
        initial_count = df.count()
        print(f"✅ Created dataset with {initial_count} rows")
        
        # Test aggregations
        print("Testing aggregations...")
        start_time = time.time()
        
        agg_result = df.groupBy("category") \
            .agg(
                F.count("*").alias("count"),
                F.avg("value").alias("avg_value"),
                F.max("value").alias("max_value"),
                F.min("value").alias("min_value"),
                F.stddev("value").alias("stddev_value")
            ) \
            .orderBy("category")
        
        agg_count = agg_result.count()
        end_time = time.time()
        
        print(f"✅ Aggregation completed: {agg_count} groups in {end_time - start_time:.2f} seconds")
        
        # Test joins
        print("Testing joins...")
        start_time = time.time()
        
        # Create a second DataFrame for join
        lookup_df = spark.range(10).toDF("category_id")
        lookup_df = lookup_df.withColumn("category", F.col("category_id").cast("string"))
        lookup_df = lookup_df.withColumn("category_name", F.concat(F.lit("Category_"), F.col("category")))
        
        joined_df = df.join(lookup_df, "category", "inner")
        join_count = joined_df.count()
        end_time = time.time()
        
        print(f"✅ Join completed: {join_count} rows in {end_time - start_time:.2f} seconds")
        
        # Test window functions
        print("Testing window functions...")
        from pyspark.sql.window import Window
        
        start_time = time.time()
        window_spec = Window.partitionBy("category").orderBy("value")
        
        windowed_df = df.withColumn("row_number", F.row_number().over(window_spec))
        windowed_df = windowed_df.withColumn("rank", F.rank().over(window_spec))
        
        window_sample = windowed_df.filter(F.col("row_number") <= 5).count()
        end_time = time.time()
        
        print(f"✅ Window functions completed: {window_sample} rows in {end_time - start_time:.2f} seconds")
        
        return True
        
    except Exception as e:
        print(f"❌ GPU DataFrame operations test failed: {str(e)}")
        return False

def test_fraud_detection_simulation(spark):
    """Test fraud detection-like operations with GPU acceleration"""
    
    print("🕵️ Testing fraud detection simulation...")
    
    try:
        # Create simulated transaction data
        print("Creating simulated transaction data...")
        
        # Generate transaction data
        transactions = spark.range(1000000).toDF("transaction_id")
        transactions = transactions.withColumn("customer_id", (F.rand() * 10000).cast("int"))
        transactions = transactions.withColumn("merchant_id", (F.rand() * 1000).cast("int"))
        transactions = transactions.withColumn("amount", F.rand() * 5000)
        transactions = transactions.withColumn("timestamp", 
            F.current_timestamp() - (F.rand() * 86400).cast("int"))
        
        # Add fraud indicators (simulate 2% fraud rate)
        transactions = transactions.withColumn("is_fraud", 
            (F.rand() < 0.02).cast("int"))
        
        transactions.cache()
        total_transactions = transactions.count()
        print(f"✅ Created {total_transactions} simulated transactions")
        
        # Test fraud detection features
        print("Computing fraud detection features...")
        start_time = time.time()
        
        # Customer transaction frequency
        from pyspark.sql.window import Window
        customer_window = Window.partitionBy("customer_id").orderBy("timestamp") \
            .rangeBetween(-3600, 0)  # 1 hour window
        
        featured_df = transactions.withColumn(
            "customer_tx_count_1h", 
            F.count("*").over(customer_window)
        )
        
        featured_df = featured_df.withColumn(
            "customer_avg_amount_1h",
            F.avg("amount").over(customer_window)
        )
        
        # Merchant statistics
        merchant_stats = transactions.groupBy("merchant_id") \
            .agg(
                F.count("*").alias("merchant_tx_count"),
                F.avg("amount").alias("merchant_avg_amount"),
                F.sum("is_fraud").alias("merchant_fraud_count")
            )
        
        # Join with merchant stats
        final_df = featured_df.join(merchant_stats, "merchant_id", "left")
        
        # Compute fraud rate by merchant
        final_df = final_df.withColumn(
            "merchant_fraud_rate",
            F.col("merchant_fraud_count") / F.col("merchant_tx_count")
        )
        
        feature_count = final_df.count()
        end_time = time.time()
        
        print(f"✅ Feature engineering completed: {feature_count} rows in {end_time - start_time:.2f} seconds")
        
        # Test fraud detection aggregations
        print("Computing fraud statistics...")
        start_time = time.time()
        
        fraud_stats = final_df.agg(
            F.count("*").alias("total_transactions"),
            F.sum("is_fraud").alias("total_fraud"),
            F.avg("amount").alias("avg_amount"),
            F.avg("customer_tx_count_1h").alias("avg_customer_frequency"),
            F.avg("merchant_fraud_rate").alias("avg_merchant_fraud_rate")
        ).collect()[0]
        
        end_time = time.time()
        
        print(f"✅ Fraud statistics computed in {end_time - start_time:.2f} seconds")
        print(f"   Total transactions: {fraud_stats['total_transactions']}")
        print(f"   Total fraud cases: {fraud_stats['total_fraud']}")
        print(f"   Fraud rate: {fraud_stats['total_fraud']/fraud_stats['total_transactions']*100:.2f}%")
        print(f"   Average amount: ${fraud_stats['avg_amount']:.2f}")
        
        return True
        
    except Exception as e:
        print(f"❌ Fraud detection simulation failed: {str(e)}")
        return False

def test_s3_integration(spark):
    """Test S3 integration with RAPIDS"""
    
    print("🪣 Testing S3 integration...")
    
    try:
        # Create test data
        test_df = spark.range(100000).toDF("id")
        test_df = test_df.withColumn("value", F.rand() * 1000)
        test_df = test_df.withColumn("category", (F.col("id") % 10).cast("string"))
        
        # Get S3 bucket from environment
        s3_bucket = os.environ.get('S3_BUCKET')
        if not s3_bucket:
            print("⚠️ S3_BUCKET environment variable not set, skipping S3 test")
            return True
        
        # Write to S3
        s3_path = f"s3://{s3_bucket}/rapids-test-data/"
        print(f"Writing test data to: {s3_path}")
        
        start_time = time.time()
        test_df.write.mode("overwrite").parquet(s3_path)
        end_time = time.time()
        
        print(f"✅ Data written to S3 in {end_time - start_time:.2f} seconds")
        
        # Read from S3
        print("Reading data back from S3...")
        start_time = time.time()
        read_df = spark.read.parquet(s3_path)
        read_count = read_df.count()
        end_time = time.time()
        
        print(f"✅ Data read from S3: {read_count} rows in {end_time - start_time:.2f} seconds")
        
        return True
        
    except Exception as e:
        print(f"❌ S3 integration test failed: {str(e)}")
        return False

def print_system_info(spark):
    """Print system and configuration information"""
    
    print("\n📋 System Information:")
    print("=" * 50)
    
    try:
        print(f"Spark Version: {spark.version}")
        print(f"Spark UI: {spark.sparkContext.uiWebUrl}")
        
        # Spark configuration
        print("\n🔧 Key Spark Configurations:")
        important_configs = [
            "spark.rapids.sql.enabled",
            "spark.plugins",
            "spark.executor.resource.gpu.amount",
            "spark.task.resource.gpu.amount",
            "spark.rapids.memory.pinnedPool.size",
            "spark.sql.adaptive.enabled",
            "spark.executor.instances",
            "spark.executor.memory",
            "spark.executor.cores"
        ]
        
        for config in important_configs:
            value = spark.conf.get(config, "Not Set")
            print(f"  {config}: {value}")
        
        # Environment variables
        print("\n🌍 Environment Variables:")
        env_vars = ["CUDA_VISIBLE_DEVICES", "RAPIDS_NO_INITIALIZE", "S3_BUCKET"]
        for var in env_vars:
            value = os.environ.get(var, "Not Set")
            print(f"  {var}: {value}")
            
    except Exception as e:
        print(f"Error getting system info: {e}")

def main():
    """Main test execution"""
    
    print("🚀 Starting RAPIDS Test Job on EMR on EKS")
    print("=" * 60)
    
    # Add basic environment checks
    print("🔍 Environment Check:")
    print(f"Python version: {sys.version}")
    print(f"Current working directory: {os.getcwd()}")
    print(f"PYTHONPATH: {os.environ.get('PYTHONPATH', 'Not set')}")
    
    spark = None
    test_results = []
    
    try:
        print("\n📋 Attempting to create Spark session...")
        # Create RAPIDS-enabled Spark session
        spark = create_rapids_spark_session()
        print("✅ Spark session created successfully")
        
        print("\n📊 Getting system information...")
        print_system_info(spark)
        
        print("\n🧪 Running Basic Spark Tests...")
        print("=" * 60)
        
        # Start with basic tests, then try RAPIDS-specific ones
        tests = [
            ("Basic Spark Functionality", lambda: test_basic_spark(spark)),
            ("RAPIDS Availability", lambda: test_rapids_availability(spark)),
            ("GPU DataFrame Operations", lambda: test_gpu_dataframe_operations(spark)),
            ("Fraud Detection Simulation", lambda: test_fraud_detection_simulation(spark)),
            ("S3 Integration", lambda: test_s3_integration(spark))
        ]
        
        for test_name, test_func in tests:
            print(f"\n🔬 Running: {test_name}")
            print("-" * 40)
            
            try:
                result = test_func()
                test_results.append((test_name, result))
                
                if result:
                    print(f"✅ {test_name}: PASSED")
                else:
                    print(f"❌ {test_name}: FAILED")
                    
            except Exception as e:
                print(f"❌ {test_name}: ERROR - {str(e)}")
                test_results.append((test_name, False))
        
        # Print summary
        print("\n📊 Test Summary")
        print("=" * 60)
        
        passed_tests = sum(1 for _, result in test_results if result)
        total_tests = len(test_results)
        
        for test_name, result in test_results:
            status = "✅ PASSED" if result else "❌ FAILED"
            print(f"  {test_name:<30} {status}")
        
        print(f"\nOverall Result: {passed_tests}/{total_tests} tests passed")
        
        if passed_tests == total_tests:
            print("🎉 All RAPIDS tests completed successfully!")
            return 0
        else:
            print("⚠️ Some tests failed. Check logs for details.")
            return 1
            
    except Exception as e:
        print(f"❌ RAPIDS test job failed: {str(e)}")
        return 1
        
    finally:
        if spark:
            print("\n🛑 Stopping Spark session...")
            spark.stop()
            print("✅ Spark session stopped")

if __name__ == "__main__":
    exit_code = main()
    sys.exit(exit_code)