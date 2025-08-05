#---------------------------------------------------------------
# Sample Fraud Detection Data Management
#---------------------------------------------------------------

# Null resource to download and upload sample data
resource "null_resource" "sample_data_upload" {
  count = var.enable_sample_data ? 1 : 0

  triggers = {
    s3_bucket = module.s3_bucket.s3_bucket_id
    timestamp = timestamp()
  }

  provisioner "local-exec" {
    command = <<-EOF
      set -e
      echo "📊 Downloading sample fraud detection datasets..."
      
      # Create temporary directory
      mkdir -p /tmp/fraud-data
      cd /tmp/fraud-data
      
      # Download datasets
      echo "Downloading customers data..."
      curl -s -L -o customers_parquet.tar.gz "https://d2908q01vomqb2.cloudfront.net/artifacts/DBSBlogs/FSI-NVIDIA-rapids/customers_parquet.tar.gz"
      
      echo "Downloading terminals data..."
      curl -s -L -o terminals_parquet.tar.gz "https://d2908q01vomqb2.cloudfront.net/artifacts/DBSBlogs/FSI-NVIDIA-rapids/terminals_parquet.tar.gz"
      
      echo "Downloading transactions data..."
      curl -s -L -o transactions_parquet_part1.tar.gz "https://d2908q01vomqb2.cloudfront.net/artifacts/DBSBlogs/FSI-NVIDIA-rapids/transactions_parquet_part1.tar.gz"
      
      # Extract datasets
      echo "Extracting datasets..."
      for file in *.tar.gz; do
        tar -xzf "$file"
      done
      
      # Upload to S3
      echo "Uploading to S3 bucket: ${module.s3_bucket.s3_bucket_id}"
      aws s3 sync customers/ s3://${module.s3_bucket.s3_bucket_id}/raw-data/customers/ --quiet
      aws s3 sync terminals/ s3://${module.s3_bucket.s3_bucket_id}/raw-data/terminals/ --quiet
      aws s3 sync transactions/ s3://${module.s3_bucket.s3_bucket_id}/raw-data/transactions/ --quiet
      
      # Create metadata file
      cat > metadata.json << 'METADATA'
{
  "dataset": "fraud-detection-sample",
  "version": "1.0.0",
  "upload_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "files": {
    "customers": {
      "path": "raw-data/customers/",
      "format": "parquet",
      "description": "Customer profile data with transaction patterns"
    },
    "terminals": {
      "path": "raw-data/terminals/",
      "format": "parquet", 
      "description": "Terminal location and configuration data"
    },
    "transactions": {
      "path": "raw-data/transactions/",
      "format": "parquet",
      "description": "Transaction data with fraud labels"
    }
  },
  "schema": {
    "customers": ["CUSTOMER_ID", "x_customer_id", "y_customer_id", "mean_amount", "std_amount", "mean_nb_tx_per_day"],
    "terminals": ["TERMINAL_ID", "x_terminal_id", "y_terminal_id"],
    "transactions": ["TX_DATETIME", "CUSTOMER_ID", "TERMINAL_ID", "TX_AMOUNT", "TX_FRAUD_1", "yyyy", "mm", "dd"]
  }
}
METADATA
      
      aws s3 cp metadata.json s3://${module.s3_bucket.s3_bucket_id}/raw-data/metadata.json
      
      # Cleanup
      cd /
      rm -rf /tmp/fraud-data
      
      echo "✅ Sample data uploaded successfully!"
      echo "📍 Data location: s3://${module.s3_bucket.s3_bucket_id}/raw-data/"
    EOF
  }

  depends_on = [module.s3_bucket]
}

# ConfigMap with data access information
resource "kubernetes_config_map" "sample_data_info" {
  count = var.enable_sample_data ? 1 : 0
  
  metadata {
    name      = "sample-data-info"
    namespace = kubernetes_namespace.ml_team_a[0].metadata[0].name
  }

  data = {
    "data_config.yaml" = yamlencode({
      s3_bucket = module.s3_bucket.s3_bucket_id
      data_paths = {
        customers    = "raw-data/customers/"
        terminals    = "raw-data/terminals/"
        transactions = "raw-data/transactions/"
        metadata     = "raw-data/metadata.json"
      }
      processed_paths = {
        features = "processed-data/features/"
        models   = "models/"
        outputs  = "outputs/"
      }
      aws_region = local.region
    })
    
    "sample_notebook.py" = <<-EOF
# Sample Python code for accessing fraud detection data
import cudf
import s3fs
import yaml

# Load configuration
with open('/etc/config/data_config.yaml', 'r') as f:
    config = yaml.safe_load(f)

# Initialize S3 filesystem
fs = s3fs.S3FileSystem()
bucket = config['s3_bucket']

# Load data with RAPIDS cuDF (GPU-accelerated)
print("Loading fraud detection data with GPU acceleration...")

customers_df = cudf.read_parquet(f's3://{bucket}/{config["data_paths"]["customers"]}')
transactions_df = cudf.read_parquet(f's3://{bucket}/{config["data_paths"]["transactions"]}')
terminals_df = cudf.read_parquet(f's3://{bucket}/{config["data_paths"]["terminals"]}')

print(f"Customers: {customers_df.shape}")
print(f"Transactions: {transactions_df.shape}")
print(f"Terminals: {terminals_df.shape}")

# Sample feature engineering
print("\\nPerforming GPU-accelerated feature engineering...")
transactions_df['TX_DATETIME'] = cudf.to_datetime(transactions_df['TX_DATETIME'])
transactions_df['hour'] = transactions_df['TX_DATETIME'].dt.hour
transactions_df['day_of_week'] = transactions_df['TX_DATETIME'].dt.dayofweek

# Customer aggregations
customer_features = transactions_df.groupby('CUSTOMER_ID').agg({
    'TX_AMOUNT': ['mean', 'std', 'count'],
    'TX_FRAUD_1': 'sum'
}).reset_index()

customer_features.columns = ['CUSTOMER_ID', 'avg_amount', 'std_amount', 'tx_count', 'fraud_count']

print(f"Customer features: {customer_features.shape}")
print("\\n✅ Sample processing completed!")
print("\\nTo save results:")
print(f"customer_features.to_parquet('s3://{bucket}/processed-data/customer-features/')")
EOF
  }

  depends_on = [
    kubernetes_namespace.ml_team_a,
    null_resource.sample_data_upload
  ]
}

# Job to verify data upload
resource "kubernetes_job" "verify_sample_data" {
  count = var.enable_sample_data ? 1 : 0
  
  metadata {
    name      = "verify-sample-data"
    namespace = kubernetes_namespace.ml_team_a[0].metadata[0].name
  }

  spec {
    template {
      metadata {
        labels = {
          app = "data-verification"
        }
      }

      spec {
        restart_policy = "Never"

        container {
          name  = "verify-data"
          image = "amazon/aws-cli:latest"

          command = ["/bin/bash", "-c"]
          args = [
            <<-EOF
            echo "🔍 Verifying sample data upload..."
            
            # Check if data exists in S3
            aws s3 ls s3://${module.s3_bucket.s3_bucket_id}/raw-data/customers/ --recursive | head -5
            aws s3 ls s3://${module.s3_bucket.s3_bucket_id}/raw-data/terminals/ --recursive | head -5
            aws s3 ls s3://${module.s3_bucket.s3_bucket_id}/raw-data/transactions/ --recursive | head -5
            
            # Check metadata
            aws s3 cp s3://${module.s3_bucket.s3_bucket_id}/raw-data/metadata.json - | head -20
            
            echo "✅ Data verification completed!"
            EOF
          ]

          env {
            name  = "AWS_DEFAULT_REGION"
            value = local.region
          }
        }

        node_selector = {
          "workload-type" = "cpu"
        }
      }
    }

    backoff_limit = 3
  }

  depends_on = [
    null_resource.sample_data_upload,
    kubernetes_namespace.ml_team_a
  ]
}