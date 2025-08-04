# Enhanced Monitoring and Observability for EMR to EKS Migration

This document describes the comprehensive monitoring and observability solution implemented for the EMR to EKS migration with RAPIDS and AI/ML workloads.

## Overview

The monitoring solution provides:
- **Prometheus** for metrics collection and storage
- **Grafana** for visualization and dashboards
- **Custom metrics exporters** for EMR on EKS and Ray workloads
- **GPU monitoring** with NVIDIA DCGM Exporter
- **Cost tracking** with Kubecost
- **Centralized logging** with AWS for Fluent Bit and CloudWatch
- **Alerting** with custom rules for system health and performance

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Data Sources  │    │   Monitoring    │    │   Visualization │
│                 │    │                 │    │                 │
│ • EMR on EKS    │───▶│ • Prometheus    │───▶│ • Grafana       │
│ • Ray Clusters  │    │ • Custom        │    │ • Dashboards    │
│ • Inference     │    │   Exporters     │    │ • Alerts        │
│ • GPU Metrics   │    │ • DCGM Exporter │    │                 │
│ • Cost Data     │    │ • Kubecost      │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                │
                                ▼
                       ┌─────────────────┐
                       │   CloudWatch    │
                       │                 │
                       │ • Log Groups    │
                       │ • Metrics       │
                       │ • Alarms        │
                       └─────────────────┘
```

## Components

### 1. Prometheus Stack

**Deployment**: `kube-prometheus-stack` Helm chart with enhanced configuration
**Namespace**: `kube-prometheus-stack`
**Storage**: 100Gi persistent volume with gp2 storage class
**Retention**: 24 hours for metrics

**Key Features**:
- Enhanced scrape configurations for EMR, Ray, and inference services
- Custom recording rules for aggregated metrics
- Alerting rules for system health and performance
- GPU metrics collection via NVIDIA DCGM Exporter
- Cost metrics integration with Kubecost

### 2. Grafana

**Access**: Port-forward to `kube-prometheus-stack-grafana` service on port 3000
**Credentials**: admin / (stored in Kubernetes secret)
**Dashboards**: Custom fraud detection overview dashboard

**Features**:
- Pre-configured data sources (Prometheus, CloudWatch)
- Custom dashboard for fraud detection pipeline
- Real-time monitoring of GPU utilization, job completion, and costs
- Resource efficiency tracking

### 3. Custom Metrics Exporters

#### EMR Metrics Exporter
- **Purpose**: Collects EMR on EKS job metrics
- **Metrics**: Job completion/failure rates, duration, resource usage
- **Endpoint**: Port 8080 `/metrics`

#### Ray Metrics Exporter  
- **Purpose**: Collects Ray cluster and training job metrics
- **Metrics**: Worker count, CPU/memory utilization, job status
- **Endpoint**: Port 8081 `/metrics`

### 4. GPU Monitoring

**Component**: NVIDIA DCGM Exporter
**Deployment**: DaemonSet on GPU nodes
**Metrics**: GPU utilization, temperature, memory usage, power consumption
**Port**: 9400

### 5. Cost Tracking

**Component**: Kubecost
**Namespace**: `kubecost`
**Access**: Port-forward to `kubecost-cost-analyzer` service on port 9090
**Features**: Namespace-level cost allocation, GPU vs CPU cost breakdown

### 6. Centralized Logging

**Component**: AWS for Fluent Bit
**Namespace**: `amazon-cloudwatch`
**Log Groups**:
- `/aws/eks/data-on-eks/cluster` - Cluster-level logs
- `/aws/eks/data-on-eks/application` - General application logs
- `/aws/eks/data-on-eks/emr-containers` - EMR on EKS job logs
- `/aws/eks/data-on-eks/ray-training` - Ray training job logs
- `/aws/eks/data-on-eks/inference-service` - Inference service logs

## Deployment

### Prerequisites
- EKS cluster with EMR Spark RAPIDS infrastructure
- Helm 3.x installed
- kubectl configured for cluster access
- AWS CLI configured with appropriate permissions

### Deploy Monitoring Stack

```bash
# Deploy the complete monitoring solution
./deploy-monitoring.sh

# Validate the deployment
./validate-monitoring.sh

# Test the monitoring integration
./test-monitoring-integration.sh
```

### Manual Deployment Steps

1. **Deploy kube-prometheus-stack**:
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
    --namespace kube-prometheus-stack \
    --create-namespace \
    --values monitoring/enhanced-kube-prometheus.yaml
```

2. **Deploy custom recording and alerting rules**:
```bash
kubectl apply -f monitoring/custom-recording-rules.yaml
kubectl apply -f monitoring/alerting-rules.yaml
```

3. **Deploy custom metrics exporters**:
```bash
kubectl apply -f monitoring/custom-metrics-exporters.yaml
```

4. **Deploy NVIDIA DCGM Exporter**:
```bash
# Automatically deployed by deploy-monitoring.sh
# Runs as DaemonSet on GPU nodes
```

5. **Deploy Kubecost**:
```bash
helm repo add kubecost https://kubecost.github.io/cost-analyzer/
helm upgrade --install kubecost kubecost/cost-analyzer \
    --namespace kubecost \
    --create-namespace \
    --values helm-values/kubecost-values.yaml
```

6. **Deploy AWS for Fluent Bit**:
```bash
helm repo add aws https://aws.github.io/eks-charts
helm upgrade --install aws-for-fluent-bit aws/aws-for-fluent-bit \
    --namespace amazon-cloudwatch \
    --create-namespace \
    --values helm-values/aws-for-fluentbit-values.yaml
```

## Access and Usage

### Grafana Dashboard
```bash
# Port forward to Grafana
kubectl port-forward -n kube-prometheus-stack svc/kube-prometheus-stack-grafana 3000:80

# Get admin password
kubectl get secret -n kube-prometheus-stack kube-prometheus-stack-grafana \
    -o jsonpath='{.data.admin-password}' | base64 -d

# Access: http://localhost:3000
# Username: admin
# Password: (from above command)
```

### Prometheus UI
```bash
# Port forward to Prometheus
kubectl port-forward -n kube-prometheus-stack svc/kube-prometheus-stack-prometheus 9090:9090

# Access: http://localhost:9090
```

### Kubecost UI
```bash
# Port forward to Kubecost
kubectl port-forward -n kubecost svc/kubecost-cost-analyzer 9090:9090

# Access: http://localhost:9090
```

## Key Metrics

### GPU Metrics
- `gpu:utilization:rate5m` - GPU utilization percentage
- `gpu:memory_utilization:rate5m` - GPU memory utilization
- `gpu:temperature:rate5m` - GPU temperature
- `cluster:gpu:utilization:avg` - Average GPU utilization across cluster

### Spark Job Metrics
- `spark:job_completion_rate:5m` - Job completion rate
- `spark:job_failure_rate:5m` - Job failure rate
- `spark:job_duration:avg5m` - Average job duration
- `spark:executor_count:current` - Current executor count

### Ray Metrics
- `ray:worker_count:current` - Active Ray workers
- `ray:cpu_utilization:rate5m` - Ray cluster CPU utilization
- `ray:memory_utilization:rate5m` - Ray cluster memory utilization
- `ray:training_duration:avg5m` - Average training job duration

### Inference Metrics
- `inference:request_rate:5m` - Request rate
- `inference:request_latency:p95` - 95th percentile latency
- `inference:error_rate:5m` - Error rate
- `inference:availability:5m` - Service availability

### Cost Metrics
- `cost:gpu_hourly:rate1h` - GPU cost per hour
- `cost:cpu_hourly:rate1h` - CPU cost per hour
- `cost:namespace_hourly:rate1h` - Cost per namespace per hour

## Alerting Rules

### GPU Alerts
- **GPUHighUtilization**: GPU utilization > 90% for 5 minutes
- **GPUHighTemperature**: GPU temperature > 80°C for 2 minutes
- **GPUMemoryExhaustion**: GPU memory utilization > 95% for 3 minutes
- **GPUNotAvailable**: GPU monitoring unavailable for 1 minute

### Spark Job Alerts
- **SparkJobHighFailureRate**: Failure rate > 10% for 5 minutes
- **SparkJobLongRunning**: Job running > 1 hour
- **SparkJobStuck**: No task completion for 30 minutes with active executors

### Ray Cluster Alerts
- **RayClusterDown**: Ray cluster not responding for 1 minute
- **RayWorkerNodeDown**: No worker nodes for 5 minutes
- **RayHighCPUUtilization**: CPU utilization > 90% for 5 minutes

### Inference Service Alerts
- **InferenceServiceDown**: Availability < 90% for 2 minutes
- **InferenceHighLatency**: 95th percentile latency > 1s for 5 minutes
- **InferenceHighErrorRate**: Error rate > 5% for 3 minutes

### Cost Alerts
- **HighHourlyCost**: Hourly cost > $100 for 1 hour
- **CostTrendIncreasing**: Daily cost increased > $500 over 7 days

## Troubleshooting

### Common Issues

1. **Prometheus not scraping targets**:
   - Check ServiceMonitor configurations
   - Verify pod annotations for scraping
   - Check network policies and firewall rules

2. **GPU metrics not available**:
   - Ensure GPU nodes have `accelerator: nvidia` label
   - Verify NVIDIA device plugin is running
   - Check DCGM Exporter DaemonSet status

3. **Custom metrics not appearing**:
   - Check custom exporter pod logs
   - Verify AWS IAM permissions for EMR access
   - Ensure Ray clusters are accessible

4. **Grafana dashboard not loading**:
   - Verify ConfigMap is labeled with `grafana_dashboard=1`
   - Check Grafana pod logs for errors
   - Ensure data sources are configured correctly

5. **CloudWatch logs not appearing**:
   - Check Fluent Bit DaemonSet status
   - Verify AWS IAM permissions for CloudWatch
   - Check log group creation in AWS Console

### Debugging Commands

```bash
# Check Prometheus targets
kubectl port-forward -n kube-prometheus-stack svc/kube-prometheus-stack-prometheus 9090:9090
curl http://localhost:9090/api/v1/targets

# Check custom exporter logs
kubectl logs -n kube-prometheus-stack deployment/emr-metrics-exporter
kubectl logs -n kube-prometheus-stack deployment/ray-metrics-exporter

# Check DCGM Exporter status
kubectl get pods -n kube-system -l app=nvidia-dcgm-exporter
kubectl logs -n kube-system -l app=nvidia-dcgm-exporter

# Check Fluent Bit logs
kubectl logs -n amazon-cloudwatch -l k8s-app=fluent-bit

# Verify ServiceMonitors
kubectl get servicemonitors -A
```

## Performance Considerations

### Resource Requirements
- **Prometheus**: 4Gi memory, 2 CPU cores, 100Gi storage
- **Grafana**: 1Gi memory, 500m CPU, 10Gi storage
- **Custom Exporters**: 256Mi memory, 200m CPU each
- **DCGM Exporter**: 256Mi memory, 100m CPU per GPU node
- **Kubecost**: 512Mi memory, 500m CPU, 32Gi storage

### Scaling Recommendations
- Increase Prometheus retention for longer-term analysis
- Use remote write to Amazon Managed Prometheus for production
- Configure Grafana with external database for high availability
- Implement metric federation for multi-cluster setups

## Security Considerations

### RBAC
- Custom exporters use dedicated service accounts with minimal permissions
- Prometheus has cluster-wide read access for metrics collection
- Grafana users should be configured with appropriate role-based access

### Network Security
- All metrics endpoints use internal cluster networking
- External access requires port-forwarding or ingress configuration
- Consider network policies to restrict metric scraping access

### Data Privacy
- Metrics may contain sensitive information about workloads
- CloudWatch logs should be configured with appropriate retention policies
- Consider encryption at rest for persistent volumes

## Maintenance

### Regular Tasks
- Monitor Prometheus storage usage and adjust retention as needed
- Review and update alerting rules based on operational experience
- Update custom exporters when EMR or Ray APIs change
- Rotate Grafana admin password periodically

### Backup and Recovery
- Prometheus data is stored in persistent volumes
- Grafana dashboards and data sources are configured via code
- Custom rules and exporters are version controlled
- CloudWatch logs provide additional backup for historical data

## Integration with CI/CD

The monitoring solution integrates with GitOps workflows:
- All configurations are stored as code
- Helm values can be templated for different environments
- Custom rules and dashboards can be version controlled
- Automated testing validates monitoring functionality

## Support and Documentation

For additional support:
- Check the validation script output for common issues
- Review Prometheus and Grafana documentation
- Consult AWS documentation for CloudWatch integration
- Use the test script to verify functionality after changes