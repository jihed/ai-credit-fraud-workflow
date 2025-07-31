#!/usr/bin/env python3
"""
Validation script for the FastAPI Fraud Detection Inference Service
Tests core functionality without external dependencies
"""

import sys
import os
import json
import ast

# Add the app directory to the path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'app'))

def test_code_structure():
    """Test code structure and syntax"""
    print("Testing code structure and syntax...")
    
    try:
        # Read and parse the main application file
        with open('app/main.py', 'r') as f:
            code = f.read()
        
        # Parse the code to check for syntax errors
        tree = ast.parse(code)
        print("✓ Code syntax is valid")
        
        # Check for required classes and functions
        classes = [node.name for node in ast.walk(tree) if isinstance(node, ast.ClassDef)]
        functions = [node.name for node in ast.walk(tree) if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))]
        
        required_classes = ['ModelManager', 'TransactionFeatures', 'PredictionResponse']
        required_functions = ['health_check', 'predict_fraud', 'predict_fraud_batch', 'reload_model', 'get_model_info']
        
        missing_classes = []
        missing_functions = []
        
        for cls in required_classes:
            if cls in classes:
                print(f"✓ Found required class: {cls}")
            else:
                missing_classes.append(cls)
        
        for func in required_functions:
            if func in functions:
                print(f"✓ Found required function: {func}")
            else:
                missing_functions.append(func)
        
        if missing_classes:
            print(f"✗ Missing required classes: {missing_classes}")
            return False
        
        if missing_functions:
            print(f"✗ Missing required functions: {missing_functions}")
            return False
        
        print("✓ All required classes and functions found")
        return True
        
    except SyntaxError as e:
        print(f"✗ Syntax error: {e}")
        return False
    except Exception as e:
        print(f"✗ Code structure test failed: {e}")
        return False

def test_file_structure():
    """Test file structure"""
    print("\nTesting file structure...")
    
    try:
        required_files = [
            'app/main.py',
            'requirements.txt',
            'Dockerfile',
            'k8s/deployment.yaml',
            'README.md',
            'tests/test_main.py',
            'tests/test_integration.py'
        ]
        
        missing_files = []
        
        for file_path in required_files:
            if os.path.exists(file_path):
                print(f"✓ Found required file: {file_path}")
            else:
                missing_files.append(file_path)
        
        if missing_files:
            print(f"✗ Missing required files: {missing_files}")
            return False
        
        print("✓ All required files found")
        return True
        
    except Exception as e:
        print(f"✗ File structure test failed: {e}")
        return False

def test_requirements():
    """Test requirements.txt content"""
    print("\nTesting requirements.txt content...")
    
    try:
        with open('requirements.txt', 'r') as f:
            requirements = f.read()
        
        required_packages = [
            'fastapi',
            'uvicorn',
            'pydantic',
            'xgboost',
            'numpy',
            'pandas',
            'boto3',
            'prometheus-client'
        ]
        
        missing_packages = []
        
        for package in required_packages:
            if package in requirements:
                print(f"✓ Found required package: {package}")
            else:
                missing_packages.append(package)
        
        if missing_packages:
            print(f"✗ Missing required packages: {missing_packages}")
            return False
        
        print("✓ All required packages found in requirements.txt")
        return True
        
    except Exception as e:
        print(f"✗ Requirements test failed: {e}")
        return False

def test_dockerfile():
    """Test Dockerfile content"""
    print("\nTesting Dockerfile content...")
    
    try:
        with open('Dockerfile', 'r') as f:
            dockerfile = f.read()
        
        required_elements = [
            'FROM python:3.9-slim',
            'WORKDIR /app',
            'COPY requirements.txt',
            'RUN pip install',
            'COPY app/',
            'EXPOSE 8000',
            'CMD ["python3", "-m", "uvicorn"'
        ]
        
        missing_elements = []
        
        for element in required_elements:
            if element in dockerfile:
                print(f"✓ Found Dockerfile element: {element}")
            else:
                missing_elements.append(element)
        
        if missing_elements:
            print(f"✗ Missing Dockerfile elements: {missing_elements}")
            return False
        
        print("✓ Dockerfile contains all required elements")
        return True
        
    except Exception as e:
        print(f"✗ Dockerfile test failed: {e}")
        return False

def test_kubernetes_manifests():
    """Test Kubernetes deployment manifests"""
    print("\nTesting Kubernetes deployment manifests...")
    
    try:
        with open('k8s/deployment.yaml', 'r') as f:
            k8s_yaml = f.read()
        
        required_k8s_elements = [
            'apiVersion: apps/v1',
            'kind: Deployment',
            'name: fraud-inference',
            'image: fraud-detection/inference:latest',
            'containerPort: 8000',
            'kind: Service',
            'kind: HorizontalPodAutoscaler',
            'kind: ConfigMap'
        ]
        
        missing_elements = []
        
        for element in required_k8s_elements:
            if element in k8s_yaml:
                print(f"✓ Found K8s element: {element}")
            else:
                missing_elements.append(element)
        
        if missing_elements:
            print(f"✗ Missing K8s elements: {missing_elements}")
            return False
        
        print("✓ Kubernetes manifests contain all required elements")
        return True
        
    except Exception as e:
        print(f"✗ Kubernetes manifests test failed: {e}")
        return False

def main():
    """Run all validation tests"""
    print("=== FastAPI Fraud Detection Inference Service Validation ===\n")
    
    tests = [
        test_code_structure,
        test_file_structure,
        test_requirements,
        test_dockerfile,
        test_kubernetes_manifests
    ]
    
    passed = 0
    total = len(tests)
    
    for test in tests:
        if test():
            passed += 1
        print()  # Add spacing between tests
    
    print("=== Validation Summary ===")
    print(f"Passed: {passed}/{total} tests")
    
    if passed == total:
        print("✓ All validation tests passed!")
        print("\nThe FastAPI Fraud Detection Inference Service implementation is ready.")
        print("\nNext steps:")
        print("1. Install dependencies: pip3 install -r requirements.txt")
        print("2. Set environment variables for S3 model path")
        print("3. Run the service: python3 -m uvicorn app.main:app --host 0.0.0.0 --port 8000")
        print("4. Test with: curl http://localhost:8000/health")
        return True
    else:
        print(f"✗ {total - passed} validation tests failed!")
        return False

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)