# End-to-End Testing Suite

This directory contains comprehensive tests for the EMR to EKS migration project, covering:

## Test Categories

### 1. Integration Tests (`integration/`)
- Complete data pipeline testing
- Cross-component communication validation
- End-to-end workflow verification

### 2. Performance Tests (`performance/`)
- GPU vs CPU performance benchmarking
- Load testing for inference service
- Resource utilization optimization

### 3. Load Tests (`load/`)
- Inference service capacity validation
- Concurrent request handling
- Scalability testing

### 4. CI/CD Pipeline (`ci-cd/`)
- Automated testing pipeline
- Deployment validation
- Rollback testing

## Running Tests

### Prerequisites
```bash
# Install test dependencies
pip install -r tests/requirements.txt

# Set environment variables
export AWS_REGION=us-west-2
export EKS_CLUSTER_NAME=data-on-eks-cluster
export S3_BUCKET=your-test-bucket
```

### Run All Tests
```bash
# Run complete test suite
./tests/run_all_tests.sh

# Run specific test category
./tests/run_integration_tests.sh
./tests/run_performance_tests.sh
./tests/run_load_tests.sh
```

### Individual Test Execution
```bash
# Integration tests
python -m pytest tests/integration/ -v

# Performance benchmarks
python tests/performance/benchmark_gpu_vs_cpu.py

# Load tests
python tests/load/test_inference_capacity.py
```

## Test Configuration

Tests use configuration files in `tests/config/` for:
- Test data paths
- Performance thresholds
- Load testing parameters
- CI/CD pipeline settings

## Test Data

Test data is generated synthetically or uses sample datasets in `tests/data/`:
- Synthetic fraud detection data
- Sample customer/terminal data
- Model artifacts for testing

## Reporting

Test results are output to `tests/reports/`:
- JUnit XML for CI/CD integration
- Performance benchmark reports
- Load testing metrics
- Coverage reports