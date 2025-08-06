# EMR to EKS Migration Deployment Runbook

## Overview

This runbook provides step-by-step instructions for deploying the migrated fraud detection workloads from EMR to EKS using the existing EMR Spark RAPIDS infrastructure.

## Prerequisites

### Required Tools
- AWS CLI v2.x configured with appropriate permissions
- kubectl v1.28+ configured for target EKS cluster
- Terraform v1.5+
- Docker v20.10+
- Python 3.8+ with pip
- Helm v3.8+

### Required Permissions
- EKS cluster admin access
- EMR Containers service permissions
- S3 read/write access to data and model buckets
- ECR push/pull permissions
- IAM role creation and management

### Environment Variables
```bash
export AWS_REGION=us-west-2
export EKS_CLUSTER_NAME=data-on-eks-cluster
export VIRTUAL_CLUSTER_ID=your-virtual-cluster-id
export ECR_REGISTRY=your-account.dkr.ecr.us-west-2.amazonaws.com
export S3_BUCKET=your-data-bucket
```

## Phase 1: Infrastructure Deployment

### 1.1 Deploy EKS Cluster with EMR Spark RAPIDS

```bash
# Clone the data-on-eks repository
git clone https://github.com/awslabs/data-on-eks.git
cd data-on-eks/analytics/terraform/emr-eks-karpenter

# Initialize Terraform
terraform init

# Review and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your specific configuration

# Deploy infrastructure
terraform plan
terraform apply -auto-approve

# Get cluster credentials
aws eks update-kubeconfig --region $AWS_REGION --name $EKS_CLUSTER_NAME --no-paginate
```

### 1.2 Verify Infrastructure Deployment

```bash
# Check cluster status
kubectl get nodes
kubectl get namespaces

# Verify EMR virtual clusters
aws emr-containers list-virtual-clusters --region $AWS_REGION --no-paginate

# Check Karpenter deployment
kubectl get deployment karpenter -n karpenter

# Verify NVIDIA device plugin
kubectl get daemonset nvidia-device-plugin-daemonset -n kube-system
```

### 1.3 Deploy Ray Operator

```bash
# Add Ray Helm repository
helm repo add kuberay https://ray-project.github.io/kuberay-helm/
helm repo update

# Install Ray operator
helm install kuberay-operator kuberay/kuberay-operator \
  --namespace ray-system \
  --create-namespace \
  --version 1.0.0

# Verify Ray operator
kubectl get deployment kuberay-operator -n ray-system
```

## Phase 2: Application Deployment

### 2.1 Build and Push Container Images

```bash
# Build RAPIDS-enabled Spark image
cd emr-spark-rapids/fraud-detection
docker build -f Dockerfile.rapids -t $ECR_REGISTRY/spark-rapids:latest .

# Build inference service image
cd ../../inference-service
docker build -t $ECR_REGISTRY/fraud-inference:latest .

# Push images to ECR
aws ecr get-login-password --region $AWS_REGION --no-paginate | docker login --username AWS --password-stdin $ECR_REGISTRY
docker push $ECR_REGISTRY/spark-rapids:latest
docker push $ECR_REGISTRY/fraud-inference:latest
```

### 2.2 Deploy Inference Service

```bash
# Create namespace if not exists
kubectl create namespace ml-team-a --dry-run=client -o yaml | kubectl apply -f -

# Apply service account and RBAC
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: fraud-inference-sa
  namespace: ml-team-a
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::$(aws sts get-caller-identity --query Account --output text --no-paginate):role/EMRContainers-JobExecutionRole
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: fraud-inference-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: view
subjects:
- kind: ServiceAccount
  name: fraud-inference-sa
  namespace: ml-team-a
EOF

# Deploy inference service
kubectl apply -f migration/output/inference-deployment.yaml

# Create service and ingress
kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: fraud-inference
  namespace: ml-team-a
spec:
  selector:
    app: fraud-inference
  ports:
  - port: 80
    targetPort: 8000
  type: ClusterIP
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: fraud-inference
  namespace: ml-team-a
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
spec:
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: fraud-inference
            port:
              number: 80
EOF
```

### 2.3 Deploy JupyterHub

```bash
# Deploy JupyterHub using existing configuration
cd emr-spark-rapids
./deploy-jupyterhub.sh

# Verify JupyterHub deployment
kubectl get pods -n jupyterhub
kubectl get service -n jupyterhub
```

### 2.4 Deploy Monitoring Stack

```bash
# Deploy monitoring components
./deploy-monitoring.sh

# Verify monitoring deployment
kubectl get pods -n prometheus
kubectl get pods -n grafana
```

## Phase 3: Data Migration

### 3.1 Run Data Migration Script

```bash
# Set migration parameters
export SOURCE_EMR_CLUSTER_ID=j-1234567890abcdef0
export SOURCE_SCRIPTS_S3=s3://$S3_BUCKET/emr-scripts/
export TARGET_SCRIPTS_S3=s3://$S3_BUCKET/emr-eks-scripts/

# Run data migration
python migration/scripts/data-migration/emr-to-emr-on-eks.py \
  --emr-cluster-id $SOURCE_EMR_CLUSTER_ID \
  --virtual-cluster-id $VIRTUAL_CLUSTER_ID \
  --cluster-name $EKS_CLUSTER_NAME \
  --source-scripts-s3 $SOURCE_SCRIPTS_S3 \
  --target-scripts-s3 $TARGET_SCRIPTS_S3 \
  --output-manifest migration-manifest.json
```

### 3.2 Test EMR on EKS Job

```bash
# Submit test job using migrated configuration
aws emr-containers start-job-run \
  --virtual-cluster-id $VIRTUAL_CLUSTER_ID \
  --name "fraud-detection-test-$(date +%s)" \
  --execution-role-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text --no-paginate):role/EMRContainers-JobExecutionRole \
  --release-label emr-6.15.0-latest \
  --job-driver file://migration-manifest.json \
  --configuration-overrides file://emr-eks-config.json

# Monitor job status
aws emr-containers list-job-runs --virtual-cluster-id $VIRTUAL_CLUSTER_ID --no-paginate
```

## Phase 4: Model Migration

### 4.1 Run Model Migration Script

```bash
# Set model migration parameters
export SAGEMAKER_TRAINING_JOB=fraud-detection-training-job
export SAGEMAKER_MODEL_NAME=fraud-detection-model

# Run model migration
python migration/scripts/model-migration/sagemaker-to-eks.py \
  --training-job-name $SAGEMAKER_TRAINING_JOB \
  --model-name $SAGEMAKER_MODEL_NAME \
  --output-dir migration/output/
```

### 4.2 Deploy Ray Training Job

```bash
# Apply Ray training job
kubectl apply -f migration/output/ray-training-job.yaml

# Monitor training job
kubectl get rayjob -n ml-team-a
kubectl logs -f job/ray-job-submitter -n ml-team-a
```

## Phase 5: Validation and Testing

### 5.1 Run Migration Validation

```bash
# Create validation configuration
cat > validation-config.json <<EOF
{
  "cluster_name": "$EKS_CLUSTER_NAME",
  "virtual_cluster_id": "$VIRTUAL_CLUSTER_ID",
  "namespace": "ml-team-a",
  "inference_service_url": "http://fraud-inference.ml-team-a.svc.cluster.local",
  "source_data_path": "s3://$S3_BUCKET/fraud-data/",
  "target_data_path": "s3://$S3_BUCKET/fraud-data-processed/"
}
EOF

# Run comprehensive validation
python migration/scripts/validation/validate-migration.py \
  --config validation-config.json \
  --output validation-report.json
```

### 5.2 Performance Testing

```bash
# Run performance benchmarks
cd tests/performance
python benchmark_gpu_vs_cpu.py --config ../../validation-config.json

# Run load testing
cd ../load
python test_inference_capacity.py --service-url http://fraud-inference.ml-team-a.svc.cluster.local
```

## Phase 6: Production Cutover

### 6.1 DNS and Traffic Routing

```bash
# Update DNS records to point to new EKS-based services
# This step depends on your DNS provider and setup

# Gradually shift traffic using weighted routing or blue-green deployment
# Monitor metrics and error rates during transition
```

### 6.2 Monitoring and Alerting

```bash
# Verify monitoring dashboards are working
kubectl port-forward -n grafana svc/grafana 3000:80

# Check alerting rules
kubectl get prometheusrule -n prometheus

# Test alert notifications
# Trigger test alerts and verify notifications are received
```

### 6.3 Backup and Rollback Plan

```bash
# Create backup of current configuration
kubectl get all -n ml-team-a -o yaml > ml-team-a-backup.yaml

# Document rollback procedures
# Keep original EMR cluster and SageMaker endpoints available for quick rollback
```

## Post-Deployment Tasks

### 1. Documentation Updates

- Update system architecture diagrams
- Update operational procedures
- Update monitoring runbooks
- Update disaster recovery plans

### 2. Team Training

- Conduct training sessions on new EKS-based workflows
- Update development and deployment procedures
- Create troubleshooting guides

### 3. Cost Optimization

- Monitor resource utilization
- Optimize instance types and scaling policies
- Implement cost alerting and budgets

## Rollback Procedures

### Emergency Rollback

If critical issues are encountered:

1. **Immediate Traffic Redirect**
   ```bash
   # Redirect traffic back to original services
   # Update DNS or load balancer configuration
   ```

2. **Revert Data Processing**
   ```bash
   # Stop EMR on EKS jobs
   aws emr-containers cancel-job-run --virtual-cluster-id $VIRTUAL_CLUSTER_ID --id $JOB_RUN_ID --no-paginate
   
   # Restart original EMR cluster if needed
   aws emr start-job-flow --name "Emergency-Rollback-Cluster" --instances file://original-cluster-config.json --no-paginate
   ```

3. **Revert Model Serving**
   ```bash
   # Scale down EKS inference service
   kubectl scale deployment fraud-inference --replicas=0 -n ml-team-a
   
   # Reactivate SageMaker endpoint
   aws sagemaker update-endpoint --endpoint-name fraud-detection-endpoint --endpoint-config-name original-config --no-paginate
   ```

### Planned Rollback

For planned rollback scenarios:

1. **Gradual Traffic Shift**
   - Reduce traffic to EKS services gradually
   - Monitor for any issues during transition
   - Complete rollback once traffic is fully shifted

2. **Data Consistency Check**
   - Ensure data consistency between old and new systems
   - Verify no data loss during rollback

3. **Clean Up Resources**
   - Scale down EKS resources
   - Clean up temporary migration resources
   - Update monitoring and alerting

## Support and Escalation

### Contact Information

- **Platform Team**: platform-team@company.com
- **Data Engineering**: data-eng@company.com
- **ML Engineering**: ml-eng@company.com
- **On-call**: +1-555-ON-CALL

### Escalation Matrix

1. **Level 1**: Platform Engineer (Response: 15 minutes)
2. **Level 2**: Senior Platform Engineer (Response: 30 minutes)
3. **Level 3**: Platform Architect (Response: 1 hour)
4. **Level 4**: Engineering Manager (Response: 2 hours)

### Common Issues and Solutions

See [Troubleshooting Runbook](troubleshooting-runbook.md) for detailed troubleshooting procedures.