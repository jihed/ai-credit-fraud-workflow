#!/bin/bash

#---------------------------------------------------------------
# Test Script for Sample Data Upload
#---------------------------------------------------------------

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🧪 Testing sample data upload script...${NC}"

# Get S3 bucket from Terraform output
S3_BUCKET=$(terraform output -raw s3_bucket_id 2>/dev/null || echo "")

if [ -z "$S3_BUCKET" ]; then
    echo "❌ Could not get S3 bucket from Terraform output"
    echo "Make sure Terraform has been applied successfully"
    exit 1
fi

echo -e "${GREEN}✅ Found S3 bucket: $S3_BUCKET${NC}"

# Run the upload script
echo -e "${BLUE}🚀 Running upload script...${NC}"
./upload-sample-data.sh "$S3_BUCKET"

echo -e "${GREEN}🎉 Upload test completed!${NC}"