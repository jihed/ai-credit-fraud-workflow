#!/bin/bash

#---------------------------------------------------------------
# Sample Fraud Detection Data Upload Script
# This script downloads and uploads sample fraud detection datasets to S3
#---------------------------------------------------------------

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}$1${NC}"
}

print_success() {
    echo -e "${GREEN}$1${NC}"
}

print_warning() {
    echo -e "${YELLOW}$1${NC}"
}

print_error() {
    echo -e "${RED}$1${NC}"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
print_status "🔍 Checking prerequisites..."

if ! command_exists aws; then
    print_error "❌ AWS CLI is required but not installed"
    print_warning "Please install AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
    exit 1
fi

if ! command_exists curl; then
    print_error "❌ curl is required but not installed"
    exit 1
fi

if ! command_exists tar; then
    print_error "❌ tar is required but not installed"
    exit 1
fi

# Verify AWS credentials
print_status "🔐 Verifying AWS credentials..."
if ! aws sts get-caller-identity --no-cli-pager >/dev/null 2>&1; then
    print_error "❌ AWS credentials not configured"
    print_warning "Please run: aws configure"
    exit 1
fi

# Get S3 bucket name from Terraform output or parameter
if [ -z "$1" ]; then
    print_status "📋 Getting S3 bucket name from Terraform output..."
    if [ -f "terraform.tfstate" ]; then
        S3_BUCKET=$(terraform output -raw s3_bucket_id 2>/dev/null || echo "")
        if [ -z "$S3_BUCKET" ]; then
            print_error "❌ Could not get S3 bucket from Terraform output"
            print_warning "Usage: $0 <s3-bucket-name>"
            print_warning "Or run this script from the directory containing terraform.tfstate"
            exit 1
        fi
    else
        print_error "❌ No terraform.tfstate found and no bucket name provided"
        print_warning "Usage: $0 <s3-bucket-name>"
        exit 1
    fi
else
    S3_BUCKET="$1"
fi

print_success "✅ Using S3 bucket: $S3_BUCKET"

# Verify S3 bucket exists and is accessible
print_status "🪣 Verifying S3 bucket access..."
if ! aws s3 ls "s3://$S3_BUCKET" --no-cli-pager >/dev/null 2>&1; then
    print_error "❌ Cannot access S3 bucket: $S3_BUCKET"
    print_warning "Please check bucket name and permissions"
    exit 1
fi

print_success "✅ S3 bucket is accessible"

# Create temporary directory
TEMP_DIR="/tmp/fraud-data-$$"
print_status "📁 Creating temporary directory: $TEMP_DIR"
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

# Download datasets
print_status "📊 Downloading sample fraud detection datasets..."

print_status "Downloading customers data..."
if ! curl -s -L -o customers_parquet.tar.gz "https://d2908q01vomqb2.cloudfront.net/artifacts/DBSBlogs/FSI-NVIDIA-rapids/customers_parquet.tar.gz"; then
    print_error "❌ Failed to download customers data"
    exit 1
fi

print_status "Downloading terminals data..."
if ! curl -s -L -o terminals_parquet.tar.gz "https://d2908q01vomqb2.cloudfront.net/artifacts/DBSBlogs/FSI-NVIDIA-rapids/terminals_parquet.tar.gz"; then
    print_error "❌ Failed to download terminals data"
    exit 1
fi

print_status "Downloading transactions data..."
if ! curl -s -L -o transactions_parquet_part1.tar.gz "https://d2908q01vomqb2.cloudfront.net/artifacts/DBSBlogs/FSI-NVIDIA-rapids/transactions_parquet_part1.tar.gz"; then
    print_error "❌ Failed to download transactions data"
    exit 1
fi

print_success "✅ All datasets downloaded successfully"

# Extract datasets
print_status "📦 Extracting datasets..."
for file in *.tar.gz; do
    if [ -f "$file" ]; then
        print_status "Extracting $file..."
        if ! tar -xzf "$file"; then
            print_error "❌ Failed to extract $file"
            exit 1
        fi
    fi
done

print_success "✅ All datasets extracted successfully"

# Upload to S3
print_status "☁️ Uploading datasets to S3..."

print_status "Uploading customers data..."
if ! aws s3 sync customers/ "s3://$S3_BUCKET/raw-data/customers/" --quiet --no-cli-pager; then
    print_error "❌ Failed to upload customers data"
    exit 1
fi

print_status "Uploading terminals data..."
if ! aws s3 sync terminals/ "s3://$S3_BUCKET/raw-data/terminals/" --quiet --no-cli-pager; then
    print_error "❌ Failed to upload terminals data"
    exit 1
fi

print_status "Uploading transactions data..."
if ! aws s3 sync transactions/ "s3://$S3_BUCKET/raw-data/transactions/" --quiet --no-cli-pager; then
    print_error "❌ Failed to upload transactions data"
    exit 1
fi

print_success "✅ All datasets uploaded successfully"

# Create and upload metadata file
print_status "📋 Creating metadata file..."
cat > metadata.json << 'METADATA'
{
  "dataset": "fraud-detection-sample",
  "version": "1.0.0",
  "upload_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "description": "Sample fraud detection dataset for EMR to EKS migration demo",
  "files": {
    "customers": {
      "path": "raw-data/customers/",
      "format": "parquet",
      "description": "Customer profile data with transaction patterns",
      "columns": ["CUSTOMER_ID", "x_customer_id", "y_customer_id", "mean_amount", "std_amount", "mean_nb_tx_per_day"]
    },
    "terminals": {
      "path": "raw-data/terminals/",
      "format": "parquet", 
      "description": "Terminal location and configuration data",
      "columns": ["TERMINAL_ID", "x_terminal_id", "y_terminal_id"]
    },
    "transactions": {
      "path": "raw-data/transactions/",
      "format": "parquet",
      "description": "Transaction data with fraud labels",
      "columns": ["TX_DATETIME", "CUSTOMER_ID", "TERMINAL_ID", "TX_AMOUNT", "TX_FRAUD_1", "yyyy", "mm", "dd"]
    }
  },
  "usage": {
    "spark_read_example": "df = spark.read.parquet('s3a://BUCKET/raw-data/transactions/')",
    "rapids_read_example": "import cudf; df = cudf.read_parquet('s3://BUCKET/raw-data/transactions/')",
    "pandas_read_example": "import pandas as pd; df = pd.read_parquet('s3://BUCKET/raw-data/transactions/')"
  },
  "data_size": {
    "customers": "~50MB",
    "terminals": "~1MB", 
    "transactions": "~500MB"
  }
}
METADATA

# Replace the timestamp placeholder
sed -i.bak "s/\$(date -u +%Y-%m-%dT%H:%M:%SZ)/$(date -u +%Y-%m-%dT%H:%M:%SZ)/" metadata.json
rm -f metadata.json.bak

print_status "Uploading metadata file..."
if ! aws s3 cp metadata.json "s3://$S3_BUCKET/raw-data/metadata.json" --no-cli-pager; then
    print_error "❌ Failed to upload metadata file"
    exit 1
fi

print_success "✅ Metadata file uploaded successfully"

# Verify upload
print_status "🔍 Verifying upload..."
print_status "Listing uploaded files:"

echo ""
print_status "📁 Customers data:"
aws s3 ls "s3://$S3_BUCKET/raw-data/customers/" --no-cli-pager | head -3

echo ""
print_status "📁 Terminals data:"
aws s3 ls "s3://$S3_BUCKET/raw-data/terminals/" --no-cli-pager | head -3

echo ""
print_status "📁 Transactions data:"
aws s3 ls "s3://$S3_BUCKET/raw-data/transactions/" --no-cli-pager | head -3

echo ""
print_status "📄 Metadata file:"
aws s3 ls "s3://$S3_BUCKET/raw-data/metadata.json" --no-cli-pager

# Cleanup
print_status "🧹 Cleaning up temporary files..."
cd /
rm -rf "$TEMP_DIR"

print_success "✅ Sample data upload completed successfully!"
print_success "📍 Data location: s3://$S3_BUCKET/raw-data/"

echo ""
print_status "🚀 Next steps:"
echo "1. Access the data in your Spark/RAPIDS applications using:"
echo "   s3://$S3_BUCKET/raw-data/customers/"
echo "   s3://$S3_BUCKET/raw-data/terminals/"
echo "   s3://$S3_BUCKET/raw-data/transactions/"
echo ""
echo "2. View metadata with:"
echo "   aws s3 cp s3://$S3_BUCKET/raw-data/metadata.json - --no-cli-pager"
echo ""
echo "3. Test data access in JupyterHub or submit Spark jobs to process the data"

print_success "🎉 Ready to start your fraud detection workloads!"