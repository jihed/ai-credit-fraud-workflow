# Cost Optimization and Resource Management

This directory contains cost optimization and resource management configurations for the EMR on EKS cluster. The implementation focuses on reducing infrastructure costs while maintaining performance through intelligent resource allocation, automated scaling, and proactive cleanup.

## Overview

The cost optimization solution enhances the existing EMR on EKS cluster (which already has Karpenter enabled) with:

1. **Karpenter Cost Optimization** - Additional cost-optimized NodePools and configurations
2. **Resource Quotas and Limits** - Prevent resource waste through namespace-level controls
3. **Cost Monitoring Dashboards** - Real-time visibility into cluster costs and utilization
4. **Automated Resource Cleanup** - Automatic cleanup of completed jobs and unused resources
5. **Alerting and Notifications** - Proactive alerts for cost thresholds and resource waste

**Note**: This cluster already has Karpenter enabled with spot instance support. This implementation adds additional cost optimization features on top of the existing setup.

## Components

### 1. Karpenter Cost Optimization

**File**: `karpenter-cost-optimization.tf`

- Additional cost-optimized NodePools for Karpenter (Karpenter is already enabled in the cluster)
- Spot instance prioritization for maximum cost savings
- Cost-optimized EC2NodeClass with efficient instance selection
- Enhanced disruption policies for cost efficiency

**Key Features**:
- Spot-only NodePool for cost-sensitive workloads
- Optimized instance family selection (m5, c5 families)
- Fast consolidation and termination policies
- Cost tracking through resource tags

### 2. Resource Quotas and Limits

**File**: `resource-quotas.yaml`

Implements namespace-level resource controls:

#### Namespaces:
- `ml-team-a`: Production ML workloads (200 CPU cores, 800GB memory, 32 GPUs)
- `ml-team-b`: Standard ML workloads (100 CPU cores, 400GB memory, 16 GPUs)  
- `ml-development`: Development workloads (50 CPU cores, 200GB memory, 8 GPUs)

#### Priority Classes:
- `high-priority-ml`: Critical production workloads (value: 1000)
- `medium-priority-ml`: Standard workloads (value: 500)
- `low-priority-ml`: Development/experimental workloads (value: 100)

#### Features:
- CPU, memory, and GPU quotas per namespace
- Storage quotas and PVC limits
- Network policies for traffic optimization
- Pod disruption budgets for availability

### 3. Cost Monitoring Dashboard

**File**: `cost-monitoring-dashboard.json`

Comprehensive Grafana dashboard providing:

#### Cost Metrics:
- Real-time cluster cost estimation
- Cost per ML job analysis
- Spot vs on-demand instance ratio
- Resource waste detection

#### Utilization Metrics:
- CPU, memory, and GPU utilization by namespace
- Resource requests vs actual usage
- Node scaling events and patterns
- Quota utilization tracking

#### Optimization Insights:
- Idle resource identification
- Cost optimization recommendations
- Spot instance interruption tracking
- Resource efficiency scoring

### 4. Cost Alerting Rules

**File**: `cost-alerting-rules.yaml`

Prometheus alerting rules for cost optimization:

#### Cost Alerts:
- High cluster cost (>$100/hour)
- Expensive long-running jobs (>$50)
- High resource waste (>50% unused)
- Low GPU utilization (<30%)

#### Operational Alerts:
- Resource quota near limits (>85%)
- High spot interruption rates
- Karpenter provisioning errors
- Slow node provisioning

#### Recording Rules:
- Cost calculation metrics
- Resource utilization percentages
- Waste detection metrics
- Efficiency scoring

### 5. Automated Resource Cleanup

**File**: `resource-cleanup.yaml`

Automated cleanup jobs for cost optimization:

#### Cleanup Jobs:
- **Spark Cleanup**: Removes completed Spark applications (1 hour retention)
- **Ray Cleanup**: Removes completed Ray jobs and idle clusters (1 hour retention)
- **PVC Cleanup**: Removes unused persistent volume claims (24 hour retention)
- **Job Cleanup**: Removes completed Kubernetes jobs (30 minute retention)

#### Features:
- Configurable retention periods
- Safe cleanup with validation checks
- Metrics collection for cleanup operations
- Error handling and logging

## Deployment

### Prerequisites

1. EKS cluster with EMR on EKS configured
2. Prometheus and Grafana installed
3. kubectl and helm CLI tools
4. Terraform for infrastructure changes

### Quick Start

1. **Deploy all components**:
   ```bash
   ./deploy-cost-optimization.sh
   ```

2. **Apply Terraform configurations**:
   ```bash
   cd cost-optimization
   terraform plan
   terraform apply
   ```

3. **Import Grafana dashboard**:
   - Access Grafana UI
   - Import `cost-monitoring-dashboard.json`

4. **Validate deployment**:
   ```bash
   ./validate-cost-optimization.sh
   ```

### Manual Deployment

1. **Apply resource quotas**:
   ```bash
   kubectl apply -f cost-optimization/resource-quotas.yaml
   ```

2. **Apply alerting rules**:
   ```bash
   kubectl apply -f cost-optimization/cost-alerting-rules.yaml
   ```

3. **Apply cleanup jobs**:
   ```bash
   kubectl apply -f cost-optimization/resource-cleanup.yaml
   ```

## Configuration

### Environment Variables

- `CLUSTER_NAME`: EKS cluster name (default: emr-spark-rapids)
- `AWS_REGION`: AWS region (default: us-west-2)
- `NAMESPACE_MONITORING`: Monitoring namespace (default: kube-prometheus-stack)

### Customization

#### Adjust Resource Quotas

Edit `resource-quotas.yaml` to modify:
- CPU, memory, and GPU limits per namespace
- Storage quotas and PVC limits
- Priority class values
- Network policy rules

#### Modify Cleanup Retention

Edit `resource-cleanup.yaml` ConfigMap:
```yaml
data:
  spark-retention-hours: "1"
  ray-retention-hours: "1"
  failed-job-retention-hours: "2"
  pvc-retention-hours: "24"
```

#### Customize Alert Thresholds

Edit `cost-alerting-rules.yaml`:
```yaml
- alert: HighClusterCost
  expr: sum(kube_node_info) * 0.096 > 100  # Adjust threshold
```

## Monitoring and Observability

### Key Metrics

#### Cost Metrics:
- `cluster:cost_per_hour`: Total cluster cost per hour
- `namespace:cost_per_hour`: Cost per namespace per hour
- `spark_job_duration_seconds`: Job execution time for cost calculation

#### Utilization Metrics:
- `namespace:cpu_utilization_percent`: CPU utilization by namespace
- `namespace:memory_utilization_percent`: Memory utilization by namespace
- `namespace:gpu_utilization_percent`: GPU utilization by namespace

#### Karpenter Metrics:
- `karpenter_nodes_created_total`: Total nodes created by Karpenter
- `karpenter_nodes_terminated_total`: Total nodes terminated by Karpenter
- `karpenter_pods_startup_duration_seconds`: Pod startup time

#### Waste Metrics:
- `namespace:cpu_waste_percent`: CPU resource waste by namespace
- `namespace:memory_waste_percent`: Memory resource waste by namespace

### Dashboards

Access the cost optimization dashboard in Grafana:
1. Navigate to Dashboards
2. Search for "EMR on EKS Cost Optimization"
3. View real-time cost and utilization metrics

### Alerts

Monitor alerts in Prometheus/Alertmanager:
- High cost alerts
- Resource waste alerts
- Quota utilization alerts
- Operational alerts

## Troubleshooting

### Common Issues

#### Resource Quota Exceeded
```bash
# Check quota usage
kubectl describe resourcequota -n ml-team-a

# Increase quota if needed
kubectl patch resourcequota ml-team-a-quota -n ml-team-a --patch '{"spec":{"hard":{"requests.cpu":"300"}}}'
```

#### Cleanup Jobs Not Running
```bash
# Check cleanup job status
kubectl get cronjobs -n kube-system -l app=resource-cleanup

# Check job logs
kubectl logs -n kube-system -l app=resource-cleanup
```

#### High Cost Alerts
```bash
# Check node utilization
kubectl top nodes

# Check resource waste
kubectl get prometheusrules cost-optimization-alerts -o yaml
```

### Validation Commands

```bash
# Validate resource quotas
kubectl get resourcequotas --all-namespaces

# Check cleanup job schedules
kubectl get cronjobs -n kube-system -l app=resource-cleanup

# Verify alerting rules
kubectl get prometheusrules -n kube-prometheus-stack

# Check priority classes
kubectl get priorityclasses | grep ml
```

## Cost Optimization Best Practices

### 1. Resource Right-Sizing
- Use resource requests and limits appropriately
- Monitor actual vs requested resources
- Adjust quotas based on usage patterns

### 2. Spot Instance Usage
- Prioritize spot instances for fault-tolerant workloads
- Use mixed instance types for cost optimization
- Implement graceful handling of spot interruptions

### 3. Automated Cleanup
- Enable automatic cleanup of completed resources
- Set appropriate retention periods
- Monitor cleanup operations

### 4. Workload Scheduling
- Use priority classes for workload prioritization
- Schedule non-critical workloads during off-peak hours
- Implement resource quotas to prevent resource hogging

### 5. Monitoring and Alerting
- Set up cost threshold alerts
- Monitor resource utilization regularly
- Track cost trends and optimization opportunities

## Integration with Requirements

This implementation addresses the following requirements:

- **Requirement 9.1**: Cluster autoscaler with spot instance integration
- **Requirement 9.3**: Cost monitoring dashboards and alerting thresholds  
- **Requirement 9.4**: Automatic resource cleanup for completed jobs
- **Requirement 9.5**: Resource quotas and limits for different workload types

## Support

For issues or questions:
1. Check the troubleshooting section
2. Review logs from cleanup jobs and monitoring components
3. Validate configuration using the provided validation script
4. Consult the EMR on EKS documentation for additional guidance