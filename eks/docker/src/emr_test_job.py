#!/usr/bin/env python3
from pyspark.sql import SparkSession
import sys

print("🚀 Starting EMR on EKS test job...")

try:
    spark = SparkSession.builder.appName("EMR-Connectivity-Test").getOrCreate()
    print(f"✅ Spark session created - Version: {spark.version}")
    print(f"✅ Spark UI: {spark.sparkContext.uiWebUrl}")
    
    # Test basic DataFrame operations
    data = [(1, "test", 100.0), (2, "data", 200.0), (3, "sample", 300.0)]
    df = spark.createDataFrame(data, ["id", "name", "value"])
    
    count = df.count()
    total_value = df.agg({"value": "sum"}).collect()[0][0]
    
    print(f"✅ DataFrame created with {count} rows")
    print(f"✅ Total value: {total_value}")
    
    # Test RAPIDS if available
    rapids_enabled = spark.conf.get("spark.rapids.sql.enabled", "false")
    print(f"✅ RAPIDS SQL enabled: {rapids_enabled}")
    
    spark.stop()
    print("✅ Test job completed successfully!")
    
except Exception as e:
    print(f"❌ Test job failed: {str(e)}")
    sys.exit(1)
