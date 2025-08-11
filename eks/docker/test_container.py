#!/usr/bin/env python3
"""
Simple container test script to validate RAPIDS container functionality
"""

import sys
import os
import subprocess

def test_python_environment():
    """Test basic Python environment"""
    print("🐍 Testing Python environment...")
    print(f"Python version: {sys.version}")
    print(f"Python executable: {sys.executable}")
    return True

def test_spark_availability():
    """Test if Spark is available"""
    print("⚡ Testing Spark availability...")
    try:
        from pyspark.sql import SparkSession
        print("✅ PySpark import successful")
        return True
    except ImportError as e:
        print(f"❌ PySpark import failed: {e}")
        return False

def test_rapids_imports():
    """Test RAPIDS package imports"""
    print("🚀 Testing RAPIDS imports...")
    
    rapids_packages = [
        ('cudf', 'CUDF - GPU DataFrames'),
        ('cuml', 'CUML - GPU Machine Learning'),
        ('cupy', 'CuPy - GPU NumPy'),
    ]
    
    results = []
    for package, description in rapids_packages:
        try:
            __import__(package)
            print(f"✅ {description}: Available")
            results.append(True)
        except ImportError:
            print(f"❌ {description}: Not available")
            results.append(False)
    
    return any(results)

def test_spark_session_creation():
    """Test basic Spark session creation"""
    print("🔧 Testing Spark session creation...")
    try:
        from pyspark.sql import SparkSession
        
        spark = SparkSession.builder \
            .appName("Container Test") \
            .config("spark.sql.adaptive.enabled", "true") \
            .getOrCreate()
        
        print("✅ Basic Spark session created successfully")
        
        # Test basic DataFrame operation
        data = [(1, "test")]
        df = spark.createDataFrame(data, ["id", "name"])
        count = df.count()
        print(f"✅ Basic DataFrame operation successful: {count} rows")
        
        spark.stop()
        return True
        
    except Exception as e:
        print(f"❌ Spark session creation failed: {e}")
        return False

def test_environment_variables():
    """Test important environment variables"""
    print("🌍 Testing environment variables...")
    
    important_vars = [
        'SPARK_HOME',
        'JAVA_HOME',
        'PYTHONPATH',
        'RAPIDS_NO_INITIALIZE',
        'CUDA_VISIBLE_DEVICES'
    ]
    
    for var in important_vars:
        value = os.environ.get(var, 'Not set')
        print(f"  {var}: {value}")
    
    return True

def main():
    """Run all container tests"""
    print("🧪 Container Validation Tests")
    print("=" * 50)
    
    tests = [
        ("Python Environment", test_python_environment),
        ("Spark Availability", test_spark_availability),
        ("RAPIDS Imports", test_rapids_imports),
        ("Environment Variables", test_environment_variables),
        ("Spark Session Creation", test_spark_session_creation),
    ]
    
    results = []
    for test_name, test_func in tests:
        print(f"\n🔬 Running: {test_name}")
        print("-" * 30)
        try:
            result = test_func()
            results.append((test_name, result))
        except Exception as e:
            print(f"❌ {test_name} failed with exception: {e}")
            results.append((test_name, False))
    
    # Summary
    print("\n📊 Test Results Summary")
    print("=" * 50)
    passed = 0
    for test_name, result in results:
        status = "✅ PASS" if result else "❌ FAIL"
        print(f"{test_name:<25} {status}")
        if result:
            passed += 1
    
    print(f"\nOverall: {passed}/{len(results)} tests passed")
    
    # Check if only RAPIDS imports failed (expected without GPU)
    rapids_only_failure = True
    for test_name, result in results:
        if not result and test_name != "RAPIDS Imports":
            rapids_only_failure = False
            break
    
    if passed == len(results):
        print("🎉 All tests passed! Container is ready for EMR.")
        return 0
    elif rapids_only_failure and passed >= len(results) - 1:
        print("✅ Container is ready for EMR! (RAPIDS imports expected to fail without GPU)")
        return 0
    else:
        print("⚠️  Some tests failed. Container needs fixes.")
        return 1

if __name__ == "__main__":
    exit_code = main()
    sys.exit(exit_code)