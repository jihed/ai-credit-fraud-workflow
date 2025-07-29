# EMR on EKS Configuration Documentation

## Overview

This document describes the EMR on EKS virtual cluster configuration that has been implemented using the existing EMR Spark RAPIDS blueprint. The configuration provides GPU-accelerated data processing capabilities for fraud detection workloads.

## Architecture Components

### 1. EMR Virtual Clusters

Two EMR virtual clusters have been configured:

- **emr-spark-rapids-emr-ml-team-a**
  - Namespace: `emr-ml-team-a`
  - State: RUNNING
  - ID: `t1pmuhtn1dzzm0rvnwhw4wz11`

- **emr-spark-rapids-emr-ml-team-b**
  - Namespace: `emr-ml-team-b`
  - State: RUNNING
  - ID: `dlwz9li2ww8b1hnktulhvj1de`

### 2. EKS Cluster Configuration

The EKS cluster `emr-spark-rapids` includes:

#### Node Groups:
- **core-node-group**: General purpose nodes (m5.xlarge, AL2_x86_64)
- **spark-driver-ng**: Spark driver nodes (m5.xlarge, AL2_x86_64)
- **spark-gpu-ng**: GPU executor nodes (g5.2xlarge, AL2_x86_64_GPU)

#### Key Features:
- NVIDIA device plugin (not GPU Operator) for GPU resource management
- Karpenter for auto-scaling with spot instance support
- Proper taints and tolerations for GPU scheduling

### 3. NVIDIA GPU Support

#### Device Plugin Configuration:
- **Namespace**: `nvidia-device-plugin`
- **Type**: NVIDIA Device Plugin (not GPU Operator as per blueprint)
- **AMI**: AL2_x86_64_GPU for GPU nodes
- **GPU Scheduling**: Enabled with `nvidia.com/gpu` resource requests

#### GPU Node Configuration:
```yaml
# GPU nodes have the following taint
taints:
  - key: nvidia.com/gpu
    value: "EXISTS"
    effect: "NO_SCHEDULE"

# GPU workloads need this toleration
tolerations:
  - key: nvidia.com/gpu
    operator: Exists
    effect: NoSchedule
```

### 4. Karpenter Auto-scaling

Two Karpenter node pools are configured:

#### spark-gpu-karpenter:
- **Instance Family**: g5
- **Instance Size**: 2xlarge
- **Capacity Type**: spot, on-demand
- **Labels**: `NodeGroupType=spark-executor-gpu-karpenter`
- **Taints**: `nvidia.com/gpu=Exists:NoSchedule`

#### spark-driver-cpu-karpenter:
- **Instance Family**: m5
- **Instance Sizes**: xlarge, 2xlarge, 4xlarge, 8xlarge
- **Capacity Type**: spot, on-demand
- **Labels**: `NodeGroupType=spark-driver-cpu-karpenter`

## EMR Job Configuration

### Basic EMR Spark Job with GPU

```yaml
apiVersion: emrcontainers.aws.com/v1beta1
kind: VirtualCluster
metadata:
  name: fraud-detection-rapids
spec:
  containerProvider:
    type: EKS
    id: emr-spark-rapids
  sparkSubmitParameters:
    # GPU Configuration
    spark.executor.resource.gpu.amount: "1"
    spark.plugins: "com.nvidia.spark.SQLPlugin"
    spark.rapids.sql.enabled: "true"
    
    # Resource Configuration
    spark.executor.memory: "30G"
    spark.executor.instances: "12"
    spark.executor.cores: "4"
    
    # Driver Configuration
    spark.driver.memory: "8G"
    spark.driver.cores: "2"
    
    # RAPIDS Configuration
    spark.sql.adaptive.enabled: "false"
    spark.sql.adaptive.coalescePartitions.enabled: "false"
    spark.rapids.sql.concurrentGpuTasks: "2"
```

### Pod Template for GPU Jobs

```yaml
apiVersion: v1
kind: Pod
spec:
  tolerations:
  - key: nvidia.com/gpu
    operator: Exists
    effect: NoSchedule
  nodeSelector:
    NodeGroupType: spark-executor-gpu-karpenter
  containers:
  - name: spark-executor
    resources:
      limits:
        nvidia.com/gpu: 1
      requests:
        nvidia.com/gpu: 1
```

## Verification Steps

### 1. Check EMR Virtual Clusters
```bash
aws emr-containers list-virtual-clusters --region us-west-2 --no-cli-pager
```

### 2. Verify Namespaces
```bash
kubectl get namespaces | grep emr
```

### 3. Check NVIDIA Device Plugin
```bash
kubectl get pods --all-namespaces | grep nvidia-device-plugin
```

### 4. Test GPU Scheduling
```bash
# Apply the test pod
kubectl apply -f gpu-test-pod.yaml

# Check if pod gets scheduled
kubectl get pod gpu-test-pod -n emr-ml-team-a -w
```

### 5. Run Verification Script
```bash
./verify-emr-eks-config.sh
```

## Requirements Compliance

### Requirement 1.2: EMR Virtual Clusters
✅ **COMPLETED**: EMR virtual clusters for ml-team-a and ml-team-b namespaces are configured and running

### Requirement 1.3: NVIDIA GPU Support
✅ **COMPLETED**: NVIDIA device plugin (not GPU Operator) is deployed and configured for AL2_x86_64_GPU AMI nodes

## Troubleshooting

### Common Issues

1. **GPU Pods Stuck in Pending**
   - Check if GPU nodes are available: `kubectl get nodes -l node.kubernetes.io/instance-type=g5.2xlarge`
   - Verify Karpenter is provisioning nodes: `kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter`

2. **EMR Jobs Failing to Schedule**
   - Verify namespace exists: `kubectl get namespace emr-ml-team-a`
   - Check RBAC permissions: `kubectl get rolebinding -n emr-ml-team-a`

3. **NVIDIA Device Plugin Not Working**
   - Check plugin pods: `kubectl get pods -n nvidia-device-plugin`
   - Verify GPU resources: `kubectl describe node <gpu-node-name>`

### Logs and Monitoring

- **EMR Job Logs**: Available in CloudWatch under `/emr-on-eks-logs/emr-spark-rapids/`
- **Karpenter Logs**: `kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter`
- **NVIDIA Plugin Logs**: `kubectl logs -n nvidia-device-plugin <pod-name>`

## Next Steps

1. **Test EMR Spark RAPIDS Jobs**: Submit actual fraud detection workloads
2. **Monitor GPU Utilization**: Set up monitoring for GPU resource usage
3. **Optimize Resource Allocation**: Fine-tune Spark and GPU configurations
4. **Implement Cost Controls**: Configure appropriate limits and quotas

## Security Considerations

- EMR execution roles have S3 full access (should be restricted in production)
- RBAC is configured per namespace for team isolation
- Network policies should be implemented for additional security
- Secrets management should be configured for sensitive data

## Cost Optimization

- GPU nodes (g5.2xlarge) are set to desired_size=0 by default
- Karpenter will provision GPU nodes only when needed
- Spot instances are enabled for cost savings
- Automatic scale-down is configured with consolidation policies