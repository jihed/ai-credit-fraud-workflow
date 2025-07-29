#!/bin/bash

#--------------------------------------------
# Integration Test Script for Fraud Detection EMR on EKS
# Tests the complete pipeline from configuration to job submission
#--------------------------------------------

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

#--------------------------------------------
# TEST CONFIGURATION
#--------------------------------------------
TEST_MODE="${TEST_MODE:-dry-run}"  # dry-run or full
SKIP_DOCKER_BUILD="${SKIP_DOCKER_BUILD:-true}"
SKIP_JOB_SUBMISSION="${SKIP_JOB_SUBMISSION:-true}"

#--------------------------------------------
# TEST FUNCTIONS
#--------------------------------------------
test_file_structure() {
    log "Testing file structure..."
    
    local required_files=(
        "README.md"
        "Dockerfile.rapids"
        "requirements.txt"
        "fraud_detection_feature_engineering.py"
        "fraud-detection-job-template.json"
        "driver-pod-template.yaml"
        "executor-pod-template.yaml"
        "submit_fraud_detection_job.sh"
        "build_docker_image.sh"
        "validate_job_config.py"
        "config/spark-defaults.conf"
        "config/example-env.sh"
    )
    
    local missing_files=()
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            missing_files+=("$file")
        fi
    done
    
    if [[ ${#missing_files[@]} -eq 0 ]]; then
        success "All required files present"
        return 0
    else
        error "Missing files: ${missing_files[*]}"
        return 1
    fi
}

test_script_permissions() {
    log "Testing script permissions..."
    
    local scripts=(
        "submit_fraud_detection_job.sh"
        "build_docker_image.sh"
        "validate_job_config.py"
    )
    
    local non_executable=()
    
    for script in "${scripts[@]}"; do
        if [[ ! -x "$script" ]]; then
            non_executable+=("$script")
        fi
    done
    
    if [[ ${#non_executable[@]} -eq 0 ]]; then
        success "All scripts are executable"
        return 0
    else
        error "Non-executable scripts: ${non_executable[*]}"
        return 1
    fi
}

test_json_syntax() {
    log "Testing JSON syntax..."
    
    if python3 -m json.tool fraud-detection-job-template.json > /dev/null 2>&1; then
        success "Job template JSON is valid"
        return 0
    else
        error "Invalid JSON in job template"
        return 1
    fi
}

test_python_syntax() {
    log "Testing Python syntax..."
    
    local python_files=(
        "fraud_detection_feature_engineering.py"
        "validate_job_config.py"
    )
    
    local syntax_errors=()
    
    for file in "${python_files[@]}"; do
        if ! python3 -m py_compile "$file" 2>/dev/null; then
            syntax_errors+=("$file")
        fi
    done
    
    if [[ ${#syntax_errors[@]} -eq 0 ]]; then
        success "All Python files have valid syntax"
        return 0
    else
        error "Python syntax errors in: ${syntax_errors[*]}"
        return 1
    fi
}

test_configuration_validation() {
    log "Testing configuration validation..."
    
    if python3 validate_job_config.py --templates-only; then
        success "Configuration validation passed"
        return 0
    else
        error "Configuration validation failed"
        return 1
    fi
}

test_docker_build() {
    if [[ "$SKIP_DOCKER_BUILD" == "true" ]]; then
        warning "Skipping Docker build test (SKIP_DOCKER_BUILD=true)"
        return 0
    fi
    
    log "Testing Docker build..."
    
    # Test Docker build without pushing
    if docker build -f Dockerfile.rapids -t fraud-detection-test:latest . > /dev/null 2>&1; then
        success "Docker build test passed"
        # Clean up test image
        docker rmi fraud-detection-test:latest > /dev/null 2>&1 || true
        return 0
    else
        error "Docker build test failed"
        return 1
    fi
}

test_environment_template() {
    log "Testing environment template..."
    
    # Source the example environment file to check for syntax errors
    if bash -n config/example-env.sh; then
        success "Environment template syntax is valid"
        return 0
    else
        error "Environment template has syntax errors"
        return 1
    fi
}

test_spark_configuration() {
    log "Testing Spark configuration..."
    
    local config_file="config/spark-defaults.conf"
    local required_settings=(
        "spark.plugins"
        "spark.rapids.sql.enabled"
        "spark.executor.resource.gpu.amount"
        "spark.driver.memory"
        "spark.executor.memory"
    )
    
    local missing_settings=()
    
    for setting in "${required_settings[@]}"; do
        if ! grep -q "^${setting}" "$config_file"; then
            missing_settings+=("$setting")
        fi
    done
    
    if [[ ${#missing_settings[@]} -eq 0 ]]; then
        success "All required Spark settings present"
        return 0
    else
        error "Missing Spark settings: ${missing_settings[*]}"
        return 1
    fi
}

test_job_submission_dry_run() {
    if [[ "$SKIP_JOB_SUBMISSION" == "true" ]]; then
        warning "Skipping job submission test (SKIP_JOB_SUBMISSION=true)"
        return 0
    fi
    
    log "Testing job submission (dry run)..."
    
    # Set minimal environment for dry run
    export EMR_VIRTUAL_CLUSTER_ID="test-cluster"
    export EMR_EXECUTION_ROLE_ARN="arn:aws:iam::123456789012:role/test-role"
    export S3_BUCKET="test-bucket"
    export CLOUDWATCH_LOG_GROUP="/test/log/group"
    
    # Test script execution without actual submission
    if bash -n submit_fraud_detection_job.sh; then
        success "Job submission script syntax is valid"
        return 0
    else
        error "Job submission script has syntax errors"
        return 1
    fi
}

run_all_tests() {
    log "Starting integration tests for fraud detection EMR on EKS..."
    
    local tests=(
        "test_file_structure"
        "test_script_permissions"
        "test_json_syntax"
        "test_python_syntax"
        "test_configuration_validation"
        "test_environment_template"
        "test_spark_configuration"
        "test_docker_build"
        "test_job_submission_dry_run"
    )
    
    local passed=0
    local failed=0
    local failed_tests=()
    
    for test in "${tests[@]}"; do
        echo ""
        if $test; then
            ((passed++))
        else
            ((failed++))
            failed_tests+=("$test")
        fi
    done
    
    echo ""
    log "Test Results Summary:"
    echo "  Passed: $passed"
    echo "  Failed: $failed"
    
    if [[ $failed -eq 0 ]]; then
        success "All integration tests passed! 🎉"
        return 0
    else
        error "Failed tests: ${failed_tests[*]}"
        return 1
    fi
}

show_help() {
    cat << EOF
Integration Test Script for Fraud Detection EMR on EKS

Usage: $0 [OPTIONS]

Environment Variables:
  TEST_MODE                 Test mode: dry-run or full (default: dry-run)
  SKIP_DOCKER_BUILD        Skip Docker build test (default: true)
  SKIP_JOB_SUBMISSION      Skip job submission test (default: true)

Options:
  -h, --help               Show this help message
  --full                   Run full tests including Docker build
  --docker                 Include Docker build test
  --submission             Include job submission test

Examples:
  # Basic tests (recommended for CI)
  $0
  
  # Full tests including Docker build
  $0 --full
  
  # Include Docker build test only
  $0 --docker
  
  # Custom configuration
  TEST_MODE=full SKIP_DOCKER_BUILD=false $0

EOF
}

#--------------------------------------------
# MAIN EXECUTION
#--------------------------------------------
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --full)
                TEST_MODE="full"
                SKIP_DOCKER_BUILD="false"
                SKIP_JOB_SUBMISSION="false"
                shift
                ;;
            --docker)
                SKIP_DOCKER_BUILD="false"
                shift
                ;;
            --submission)
                SKIP_JOB_SUBMISSION="false"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    log "Integration test configuration:"
    echo "  Test Mode: $TEST_MODE"
    echo "  Skip Docker Build: $SKIP_DOCKER_BUILD"
    echo "  Skip Job Submission: $SKIP_JOB_SUBMISSION"
    
    run_all_tests
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi