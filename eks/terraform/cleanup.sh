#!/bin/bash

# Fraud Detection EMR on EKS Cleanup Script
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Cleanup EMR jobs
cleanup_emr_jobs() {
    print_status "Checking for running EMR jobs..."
    
    if terraform output emr_virtual_cluster_id &> /dev/null; then
        VIRTUAL_CLUSTER_ID=$(terraform output -raw emr_virtual_cluster_id)
        
        # List running jobs
        RUNNING_JOBS=$(aws emr-containers list-job-runs --virtual-cluster-id $VIRTUAL_CLUSTER_ID --states RUNNING PENDING --query 'jobRuns[].id' --output text)
        
        if [ ! -z "$RUNNING_JOBS" ]; then
            print_warning "Found running EMR jobs. Cancelling them..."
            for job_id in $RUNNING_JOBS; do
                print_status "Cancelling job: $job_id"
                aws emr-containers cancel-job-run --virtual-cluster-id $VIRTUAL_CLUSTER_ID --id $job_id
            done
            
            print_status "Waiting for jobs to terminate..."
            sleep 30
        else
            print_status "No running EMR jobs found."
        fi
    fi
}

# Cleanup Kubernetes resources
cleanup_kubernetes_resources() {
    print_status "Cleaning up Kubernetes resources..."
    
    # Check if kubectl is configured
    if kubectl cluster-info &> /dev/null; then
        # Delete any remaining pods in EMR namespace
        if kubectl get namespace emr-fraud-detection &> /dev/null; then
            print_status "Cleaning up EMR namespace resources..."
            kubectl delete pods --all -n emr-fraud-detection --force --grace-period=0 || true
        fi
        
        # Clean up any stuck finalizers
        print_status "Cleaning up any stuck resources..."
        kubectl get pods --all-namespaces --field-selector=status.phase=Failed -o json | kubectl delete -f - || true
    else
        print_warning "kubectl not configured or cluster not accessible. Skipping Kubernetes cleanup."
    fi
}

# Cleanup S3 bucket contents
cleanup_s3_bucket() {
    print_status "Cleaning up S3 bucket contents..."
    
    if terraform output s3_bucket_name &> /dev/null; then
        BUCKET_NAME=$(terraform output -raw s3_bucket_name)
        
        print_status "Emptying S3 bucket: $BUCKET_NAME"
        aws s3 rm s3://$BUCKET_NAME --recursive || true
        
        # Remove any versioned objects
        aws s3api list-object-versions --bucket $BUCKET_NAME --query 'Versions[].{Key:Key,VersionId:VersionId}' --output text | while read key version; do
            if [ ! -z "$key" ] && [ ! -z "$version" ]; then
                aws s3api delete-object --bucket $BUCKET_NAME --key $key --version-id $version || true
            fi
        done
        
        # Remove any delete markers
        aws s3api list-object-versions --bucket $BUCKET_NAME --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' --output text | while read key version; do
            if [ ! -z "$key" ] && [ ! -z "$version" ]; then
                aws s3api delete-object --bucket $BUCKET_NAME --key $key --version-id $version || true
            fi
        done
    fi
}

# Destroy Terraform resources
destroy_terraform() {
    print_status "Destroying Terraform resources..."
    
    terraform destroy -auto-approve
    
    if [ $? -eq 0 ]; then
        print_status "Terraform resources destroyed successfully!"
    else
        print_error "Terraform destroy failed! Some resources may still exist."
        print_warning "Please check the AWS console and clean up manually if needed."
        exit 1
    fi
}

# Main cleanup function
main() {
    print_warning "This will destroy all resources created by the fraud detection EMR on EKS deployment."
    print_warning "This action cannot be undone!"
    echo
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Cleanup cancelled by user."
        exit 0
    fi
    
    print_status "Starting cleanup process..."
    
    # Check if Terraform state exists
    if [ ! -f "terraform.tfstate" ] && [ ! -f ".terraform/terraform.tfstate" ]; then
        print_error "No Terraform state found. Nothing to clean up."
        exit 1
    fi
    
    cleanup_emr_jobs
    cleanup_kubernetes_resources
    cleanup_s3_bucket
    destroy_terraform
    
    print_status "Cleanup completed successfully!"
    print_status "All resources have been destroyed."
}

# Run main function
main "$@"