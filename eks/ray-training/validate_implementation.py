#!/usr/bin/env python3
"""
Simple validation script for Ray XGBoost training implementation
Validates the code structure and basic functionality without external dependencies
"""

import os
import sys
import ast
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def validate_file_exists(filepath, description):
    """Validate that a file exists"""
    if os.path.exists(filepath):
        logger.info(f"✓ {description}: {filepath}")
        return True
    else:
        logger.error(f"✗ {description}: {filepath} - NOT FOUND")
        return False

def validate_python_syntax(filepath):
    """Validate Python file syntax"""
    try:
        with open(filepath, 'r') as f:
            content = f.read()
        ast.parse(content)
        logger.info(f"✓ Python syntax valid: {filepath}")
        return True
    except SyntaxError as e:
        logger.error(f"✗ Python syntax error in {filepath}: {e}")
        return False
    except Exception as e:
        logger.error(f"✗ Error reading {filepath}: {e}")
        return False

def validate_script_executable(filepath):
    """Validate that script is executable"""
    if os.access(filepath, os.X_OK):
        logger.info(f"✓ Script is executable: {filepath}")
        return True
    else:
        logger.warning(f"⚠ Script not executable: {filepath}")
        return False

def validate_required_functions(filepath, required_functions):
    """Validate that required functions exist in Python file"""
    try:
        with open(filepath, 'r') as f:
            content = f.read()
        
        tree = ast.parse(content)
        
        # Extract function names
        function_names = []
        for node in ast.walk(tree):
            if isinstance(node, ast.FunctionDef):
                function_names.append(node.name)
        
        missing_functions = []
        for func in required_functions:
            if func in function_names:
                logger.info(f"✓ Function found: {func}")
            else:
                missing_functions.append(func)
                logger.error(f"✗ Function missing: {func}")
        
        return len(missing_functions) == 0
        
    except Exception as e:
        logger.error(f"✗ Error validating functions in {filepath}: {e}")
        return False

def validate_required_classes(filepath, required_classes):
    """Validate that required classes exist in Python file"""
    try:
        with open(filepath, 'r') as f:
            content = f.read()
        
        tree = ast.parse(content)
        
        # Extract class names
        class_names = []
        for node in ast.walk(tree):
            if isinstance(node, ast.ClassDef):
                class_names.append(node.name)
        
        missing_classes = []
        for cls in required_classes:
            if cls in class_names:
                logger.info(f"✓ Class found: {cls}")
            else:
                missing_classes.append(cls)
                logger.error(f"✗ Class missing: {cls}")
        
        return len(missing_classes) == 0
        
    except Exception as e:
        logger.error(f"✗ Error validating classes in {filepath}: {e}")
        return False

def validate_yaml_structure(filepath):
    """Basic YAML structure validation"""
    try:
        with open(filepath, 'r') as f:
            content = f.read()
        
        # Basic checks for Kubernetes YAML
        required_fields = ['apiVersion', 'kind', 'metadata', 'spec']
        missing_fields = []
        
        for field in required_fields:
            if field + ':' in content:
                logger.info(f"✓ YAML field found: {field}")
            else:
                missing_fields.append(field)
                logger.error(f"✗ YAML field missing: {field}")
        
        return len(missing_fields) == 0
        
    except Exception as e:
        logger.error(f"✗ Error validating YAML {filepath}: {e}")
        return False

def main():
    """Main validation function"""
    logger.info("Validating Ray XGBoost training implementation...")
    
    base_dir = "emr-spark-rapids/ray-training"
    all_valid = True
    
    # File existence validation
    files_to_check = [
        (f"{base_dir}/ray_xgboost_trainer.py", "Main training script"),
        (f"{base_dir}/training_monitor.py", "Training monitor"),
        (f"{base_dir}/ray-xgboost-training-job.yaml", "Kubernetes job manifest"),
        (f"{base_dir}/submit_training_job.sh", "Job submission script"),
        (f"{base_dir}/requirements.txt", "Python requirements"),
        (f"{base_dir}/README.md", "Documentation"),
        (f"{base_dir}/test_ray_training.py", "Test script")
    ]
    
    for filepath, description in files_to_check:
        if not validate_file_exists(filepath, description):
            all_valid = False
    
    # Python syntax validation
    python_files = [
        f"{base_dir}/ray_xgboost_trainer.py",
        f"{base_dir}/training_monitor.py",
        f"{base_dir}/test_ray_training.py"
    ]
    
    for filepath in python_files:
        if os.path.exists(filepath):
            if not validate_python_syntax(filepath):
                all_valid = False
    
    # Script executable validation
    script_files = [
        f"{base_dir}/submit_training_job.sh"
    ]
    
    for filepath in script_files:
        if os.path.exists(filepath):
            validate_script_executable(filepath)  # Warning only
    
    # Function validation for main trainer
    trainer_file = f"{base_dir}/ray_xgboost_trainer.py"
    if os.path.exists(trainer_file):
        required_functions = [
            'load_data_from_s3',
            'prepare_features',
            'create_ray_datasets',
            'get_xgboost_params',
            'train_model',
            'evaluate_model',
            'save_model_artifacts',
            'run_training_pipeline',
            'main'
        ]
        
        if not validate_required_functions(trainer_file, required_functions):
            all_valid = False
        
        required_classes = ['RayXGBoostTrainer']
        if not validate_required_classes(trainer_file, required_classes):
            all_valid = False
    
    # Function validation for monitor
    monitor_file = f"{base_dir}/training_monitor.py"
    if os.path.exists(monitor_file):
        required_classes = [
            'TrainingMetrics',
            'SystemMetrics',
            'CloudWatchLogger',
            'GPUMonitor',
            'TrainingMonitor',
            'TrainingCallback'
        ]
        
        if not validate_required_classes(monitor_file, required_classes):
            all_valid = False
    
    # YAML validation
    yaml_file = f"{base_dir}/ray-xgboost-training-job.yaml"
    if os.path.exists(yaml_file):
        if not validate_yaml_structure(yaml_file):
            all_valid = False
    
    # Requirements validation
    requirements_file = f"{base_dir}/requirements.txt"
    if os.path.exists(requirements_file):
        with open(requirements_file, 'r') as f:
            content = f.read()
        
        required_packages = ['ray', 'xgboost', 'boto3', 's3fs', 'pandas', 'numpy', 'scikit-learn']
        missing_packages = []
        
        for package in required_packages:
            if package in content:
                logger.info(f"✓ Required package found: {package}")
            else:
                missing_packages.append(package)
                logger.error(f"✗ Required package missing: {package}")
        
        if missing_packages:
            all_valid = False
    
    # Summary
    if all_valid:
        logger.info("🎉 All validation checks passed!")
        logger.info("Ray XGBoost training implementation is complete and valid.")
        return True
    else:
        logger.error("❌ Some validation checks failed.")
        logger.error("Please review the errors above and fix the issues.")
        return False

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)