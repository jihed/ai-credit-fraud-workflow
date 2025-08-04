# Production Configuration Adjustments

## Overview

This document outlines the configuration adjustments needed for production workloads based on the comprehensive validation and security audit results. These adjustments ensure optimal performance, security, and compliance for the EMR to EKS migration.

## Infrastructure Adjustments

### 1. EKS Cluster Configuration

#### Kubernetes Version Upgrade
**Priority: HIGH**
- **Current Issue**: Kubernetes version may be below 1.28
- **Recommendation**: Upgrade to Kubernetes 1.28 or higher
- **Implementation**:
  ```hcl
  # terraform/eks-cluster.tf
  resource "aws_eks_cluster" "main" {
    name     = var.cluster_name
    version  = "1.28"  # Updated from previous version
    
    # ... rest of configuration
  }
  ```
- **Benefits**: Latest security patches, improved performance, new features

#### Node Group Optimization
**Priority: MEDIUM**
- **Current Issue**: Suboptimal instance types for workload patterns
- **Recommendation**: Implement mixed instance types with spot instances
- **Implementation**:
  ```yaml
  # karpenter/nodepool.yaml
  apiVersion: karpenter.sh/v1beta1
  kind: NodePool
  metadata:
    name: gpu-optimized
  spec:
    template:
      spec:
        requirements:
          - key: kubernetes.io/arch
            operator: In
            values: ["amd64"]
          - key: node.kubernetes.io/instance-type
            operator: In
            values: ["g5.2xlarge", "g5.4xlarge", "g5.8xlarge"]
          - key: karpenter.sh/capacity-type
            operator: In
            values: ["spot", "on-demand"]
        nodeClassRef:
          apiVersion: karpenter.k8s.aws/v1beta1
          kind: EC2NodeClass
          name: gpu-nodeclass
    disruption:
      consolidationPolicy: WhenUnderutilized
      consolidateAfter: 30s
  ```

### 2. Storage Configuration

#### EBS Encryption
**Priority: HIGH**
- **Current Issue**: Storage classes may not have encryption enabled
- **Recommendation**: Enable encryption for all EBS volumes
- **Implementation**:
  ```yaml
  # k8s/storage/storage-class.yaml
  apiVersion: storage.k8s.io/v1
  kind: StorageClass
  metadata:
    name: gp3-encrypted
    annotations:
      storageclass.kubernetes.io/is-default-class: "true"
  provisioner: ebs.csi.aws.com
  parameters:
    type: gp3
    encrypted: "true"
    kmsKeyId: "arn:aws:kms:${AWS_REGION}:${AWS_ACCOUNT_ID}:key/${KMS_KEY_ID}"
  allowVolumeExpansion: true
  volumeBindingMode: WaitForFirstConsumer
  ```

#### S3 Bucket Security
**Priority: HIGH**
- **Current Issue**: S3 bucket may lack comprehensive security controls
- **Recommendation**: Implement bucket encryption, versioning, and access logging
- **Implementation**:
  ```hcl
  # terraform/s3.tf
  resource "aws_s3_bucket" "data_lake" {
    bucket = var.s3_bucket_name
  }
  
  resource "aws_s3_bucket_encryption_configuration" "data_lake" {
    bucket = aws_s3_bucket.data_lake.id
    
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = aws_kms_key.s3_key.arn
        sse_algorithm     = "aws:kms"
      }
      bucket_key_enabled = true
    }
  }
  
  resource "aws_s3_bucket_versioning" "data_lake" {
    bucket = aws_s3_bucket.data_lake.id
    versioning_configuration {
      status = "Enabled"
    }
  }
  
  resource "aws_s3_bucket_logging" "data_lake" {
    bucket = aws_s3_bucket.data_lake.id
    
    target_bucket = aws_s3_bucket.access_logs.id
    target_prefix = "access-logs/"
  }
  ```

## Security Adjustments

### 1. Network Security

#### Network Policies Implementation
**Priority: HIGH**
- **Current Issue**: No network policies for namespace isolation
- **Recommendation**: Implement comprehensive network policies
- **Implementation**:
  ```yaml
  # k8s/security/network-policies.yaml
  apiVersion: networking.k8s.io/v1
  kind: NetworkPolicy
  metadata:
    name: default-deny-all
    namespace: ml-team-a
  spec:
    podSelector: {}
    policyTypes:
    - Ingress
    - Egress
  ---
  apiVersion: networking.k8s.io/v1
  kind: NetworkPolicy
  metadata:
    name: allow-ml-workloads
    namespace: ml-team-a
  spec:
    podSelector:
      matchLabels:
        app: fraud-detection
    policyTypes:
    - Ingress
    - Egress
    ingress:
    - from:
      - namespaceSelector:
          matchLabels:
            name: ml-team-a
      ports:
      - protocol: TCP
        port: 8000
    egress:
    - to:
      - namespaceSelector:
          matchLabels:
            name: kube-system
      ports:
      - protocol: TCP
        port: 53
      - protocol: UDP
        port: 53
    - to: []
      ports:
      - protocol: TCP
        port: 443
  ```

#### Service Mesh Implementation
**Priority: MEDIUM**
- **Current Issue**: No service mesh for mTLS and traffic management
- **Recommendation**: Implement Istio for enhanced security
- **Implementation**:
  ```yaml
  # istio/peerauthentication.yaml
  apiVersion: security.istio.io/v1beta1
  kind: PeerAuthentication
  metadata:
    name: default
    namespace: ml-team-a
  spec:
    mtls:
      mode: STRICT
  ---
  apiVersion: security.istio.io/v1beta1
  kind: AuthorizationPolicy
  metadata:
    name: fraud-detection-authz
    namespace: ml-team-a
  spec:
    selector:
      matchLabels:
        app: fraud-detection
    rules:
    - from:
      - source:
          principals: ["cluster.local/ns/ml-team-a/sa/fraud-detection"]
      to:
      - operation:
          methods: ["GET", "POST"]
  ```

### 2. RBAC Enhancements

#### Principle of Least Privilege
**Priority: HIGH**
- **Current Issue**: Overly permissive RBAC configurations
- **Recommendation**: Implement granular RBAC policies
- **Implementation**:
  ```yaml
  # k8s/rbac/ml-team-rbac.yaml
  apiVersion: rbac.authorization.k8s.io/v1
  kind: Role
  metadata:
    namespace: ml-team-a
    name: ml-developer
  rules:
  - apiGroups: [""]
    resources: ["pods", "pods/log", "pods/exec"]
    verbs: ["get", "list", "create", "delete"]
  - apiGroups: ["apps"]
    resources: ["deployments", "replicasets"]
    verbs: ["get", "list", "create", "update", "patch"]
  - apiGroups: ["batch"]
    resources: ["jobs"]
    verbs: ["get", "list", "create", "delete"]
  - apiGroups: ["ray.io"]
    resources: ["rayclusters", "rayjobs"]
    verbs: ["get", "list", "create", "delete"]
  ---
  apiVersion: rbac.authorization.k8s.io/v1
  kind: RoleBinding
  metadata:
    name: ml-team-a-binding
    namespace: ml-team-a
  subjects:
  - kind: User
    name: ml-team-a-users
    apiGroup: rbac.authorization.k8s.io
  roleRef:
    kind: Role
    name: ml-developer
    apiGroup: rbac.authorization.k8s.io
  ```

#### Service Account Security
**Priority: MEDIUM**
- **Current Issue**: Service accounts with auto-mounted tokens
- **Recommendation**: Disable auto-mounting where not needed
- **Implementation**:
  ```yaml
  # k8s/rbac/service-accounts.yaml
  apiVersion: v1
  kind: ServiceAccount
  metadata:
    name: fraud-detection-sa
    namespace: ml-team-a
    annotations:
      eks.amazonaws.com/role-arn: arn:aws:iam::${AWS_ACCOUNT_ID}:role/FraudDetectionRole
  automountServiceAccountToken: false
  ---
  apiVersion: apps/v1
  kind: Deployment
  metadata:
    name: fraud-inference
    namespace: ml-team-a
  spec:
    template:
      spec:
        serviceAccountName: fraud-detection-sa
        automountServiceAccountToken: true  # Only when needed
        containers:
        - name: inference
          image: fraud-detection/inference:latest
  ```

### 3. Secrets Management

#### External Secrets Operator
**Priority: HIGH**
- **Current Issue**: Secrets stored in Kubernetes etcd
- **Recommendation**: Implement External Secrets Operator with AWS Secrets Manager
- **Implementation**:
  ```yaml
  # k8s/secrets/external-secrets.yaml
  apiVersion: external-secrets.io/v1beta1
  kind: SecretStore
  metadata:
    name: aws-secrets-manager
    namespace: ml-team-a
  spec:
    provider:
      aws:
        service: SecretsManager
        region: us-west-2
        auth:
          secretRef:
            accessKeyID:
              name: aws-credentials
              key: access-key-id
            secretAccessKey:
              name: aws-credentials
              key: secret-access-key
  ---
  apiVersion: external-secrets.io/v1beta1
  kind: ExternalSecret
  metadata:
    name: fraud-detection-secrets
    namespace: ml-team-a
  spec:
    refreshInterval: 1h
    secretStoreRef:
      name: aws-secrets-manager
      kind: SecretStore
    target:
      name: fraud-detection-secrets
      creationPolicy: Owner
    data:
    - secretKey: database-password
      remoteRef:
        key: fraud-detection/database
        property: password
    - secretKey: api-key
      remoteRef:
        key: fraud-detection/api
        property: key
  ```

## Monitoring and Observability Adjustments

### 1. Enhanced Alerting

#### Prometheus Alerting Rules
**Priority: MEDIUM**
- **Current Issue**: No alerting rules configured
- **Recommendation**: Implement comprehensive alerting rules
- **Implementation**:
  ```yaml
  # k8s/monitoring/prometheus-rules.yaml
  apiVersion: monitoring.coreos.com/v1
  kind: PrometheusRule
  metadata:
    name: fraud-detection-alerts
    namespace: prometheus
  spec:
    groups:
    - name: fraud-detection.rules
      rules:
      - alert: HighInferenceLatency
        expr: histogram_quantile(0.95, rate(http_request_duration_seconds_bucket{job="fraud-inference"}[5m])) > 0.5
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "High inference latency detected"
          description: "95th percentile latency is {{ $value }}s"
      
      - alert: GPUUtilizationLow
        expr: avg(nvidia_gpu_utilization) < 20
        for: 10m
        labels:
          severity: info
        annotations:
          summary: "GPU utilization is low"
          description: "Average GPU utilization is {{ $value }}%"
      
      - alert: TrainingJobFailed
        expr: increase(ray_job_failed_total[5m]) > 0
        for: 0m
        labels:
          severity: critical
        annotations:
          summary: "Ray training job failed"
          description: "{{ $value }} training jobs have failed in the last 5 minutes"
  ```

#### Grafana Dashboard Updates
**Priority: LOW**
- **Current Issue**: Basic dashboards without business metrics
- **Recommendation**: Add fraud detection specific dashboards
- **Implementation**:
  ```json
  {
    "dashboard": {
      "title": "Fraud Detection Pipeline",
      "panels": [
        {
          "title": "Inference Requests per Second",
          "type": "graph",
          "targets": [
            {
              "expr": "rate(http_requests_total{job=\"fraud-inference\"}[5m])"
            }
          ]
        },
        {
          "title": "Model Accuracy",
          "type": "stat",
          "targets": [
            {
              "expr": "fraud_model_accuracy"
            }
          ]
        },
        {
          "title": "GPU Memory Usage",
          "type": "graph",
          "targets": [
            {
              "expr": "nvidia_gpu_memory_used_bytes / nvidia_gpu_memory_total_bytes * 100"
            }
          ]
        }
      ]
    }
  }
  ```

### 2. Cost Optimization

#### Resource Quotas and Limits
**Priority: MEDIUM**
- **Current Issue**: No resource quotas to prevent cost overruns
- **Recommendation**: Implement namespace resource quotas
- **Implementation**:
  ```yaml
  # k8s/resources/resource-quotas.yaml
  apiVersion: v1
  kind: ResourceQuota
  metadata:
    name: ml-team-a-quota
    namespace: ml-team-a
  spec:
    hard:
      requests.cpu: "100"
      requests.memory: 200Gi
      requests.nvidia.com/gpu: "20"
      limits.cpu: "200"
      limits.memory: 400Gi
      limits.nvidia.com/gpu: "20"
      persistentvolumeclaims: "50"
      requests.storage: 1Ti
  ---
  apiVersion: v1
  kind: LimitRange
  metadata:
    name: ml-team-a-limits
    namespace: ml-team-a
  spec:
    limits:
    - default:
        cpu: "2"
        memory: "4Gi"
      defaultRequest:
        cpu: "500m"
        memory: "1Gi"
      type: Container
    - max:
        cpu: "16"
        memory: "64Gi"
        nvidia.com/gpu: "4"
      type: Container
  ```

#### Spot Instance Configuration
**Priority: MEDIUM**
- **Current Issue**: Not maximizing spot instance usage
- **Recommendation**: Optimize spot instance configuration
- **Implementation**:
  ```yaml
  # karpenter/spot-nodepool.yaml
  apiVersion: karpenter.sh/v1beta1
  kind: NodePool
  metadata:
    name: spot-gpu-pool
  spec:
    template:
      spec:
        requirements:
          - key: karpenter.sh/capacity-type
            operator: In
            values: ["spot"]
          - key: node.kubernetes.io/instance-type
            operator: In
            values: ["g5.2xlarge", "g5.4xlarge"]
        nodeClassRef:
          apiVersion: karpenter.k8s.aws/v1beta1
          kind: EC2NodeClass
          name: spot-gpu-nodeclass
        taints:
          - key: nvidia.com/gpu
            value: "true"
            effect: NoSchedule
    disruption:
      consolidationPolicy: WhenEmpty
      consolidateAfter: 30s
      expireAfter: 30m
  ```

## Compliance Adjustments

### 1. Audit Logging

#### EKS Audit Logging
**Priority: HIGH**
- **Current Issue**: Audit logging may not be enabled
- **Recommendation**: Enable comprehensive audit logging
- **Implementation**:
  ```hcl
  # terraform/eks-cluster.tf
  resource "aws_eks_cluster" "main" {
    name     = var.cluster_name
    version  = "1.28"
    
    enabled_cluster_log_types = [
      "api",
      "audit",
      "authenticator",
      "controllerManager",
      "scheduler"
    ]
    
    # ... rest of configuration
  }
  
  resource "aws_cloudwatch_log_group" "eks_cluster" {
    name              = "/aws/eks/${var.cluster_name}/cluster"
    retention_in_days = 30
    kms_key_id        = aws_kms_key.cloudwatch_key.arn
  }
  ```

### 2. Data Protection

#### Encryption at Rest
**Priority: HIGH**
- **Current Issue**: Not all data encrypted with customer-managed keys
- **Recommendation**: Implement comprehensive encryption
- **Implementation**:
  ```hcl
  # terraform/kms.tf
  resource "aws_kms_key" "eks_secrets" {
    description             = "EKS Secrets Encryption Key"
    deletion_window_in_days = 7
    
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Sid    = "Enable IAM User Permissions"
          Effect = "Allow"
          Principal = {
            AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
          }
          Action   = "kms:*"
          Resource = "*"
        }
      ]
    })
  }
  
  resource "aws_kms_alias" "eks_secrets" {
    name          = "alias/eks-secrets-${var.cluster_name}"
    target_key_id = aws_kms_key.eks_secrets.key_id
  }
  ```

## Performance Optimization Adjustments

### 1. GPU Optimization

#### NVIDIA GPU Operator
**Priority: MEDIUM**
- **Current Issue**: Using device plugin instead of GPU Operator
- **Recommendation**: Consider GPU Operator for advanced features
- **Implementation**:
  ```yaml
  # k8s/gpu/gpu-operator.yaml
  apiVersion: v1
  kind: Namespace
  metadata:
    name: gpu-operator
  ---
  apiVersion: argoproj.io/v1alpha1
  kind: Application
  metadata:
    name: gpu-operator
    namespace: argocd
  spec:
    project: default
    source:
      repoURL: https://helm.ngc.nvidia.com/nvidia
      chart: gpu-operator
      targetRevision: v23.9.1
      helm:
        values: |
          operator:
            defaultRuntime: containerd
          driver:
            enabled: true
          toolkit:
            enabled: true
          devicePlugin:
            enabled: true
          dcgmExporter:
            enabled: true
          gfd:
            enabled: true
          migManager:
            enabled: false
          nodeStatusExporter:
            enabled: true
    destination:
      server: https://kubernetes.default.svc
      namespace: gpu-operator
    syncPolicy:
      automated:
        prune: true
        selfHeal: true
  ```

### 2. Data Processing Optimization

#### RAPIDS Configuration
**Priority: MEDIUM**
- **Current Issue**: Default RAPIDS configuration may not be optimal
- **Recommendation**: Tune RAPIDS for fraud detection workload
- **Implementation**:
  ```yaml
  # k8s/emr/spark-config.yaml
  apiVersion: v1
  kind: ConfigMap
  metadata:
    name: spark-rapids-config
    namespace: ml-team-a
  data:
    spark-defaults.conf: |
      spark.plugins=com.nvidia.spark.SQLPlugin
      spark.sql.extensions=com.nvidia.spark.rapids.sql.RapidsSparkSessionExtensions
      spark.rapids.sql.enabled=true
      spark.rapids.sql.explain=ALL
      spark.rapids.memory.pinnedPool.size=2G
      spark.rapids.sql.concurrentGpuTasks=2
      spark.sql.adaptive.enabled=true
      spark.sql.adaptive.coalescePartitions.enabled=true
      spark.sql.adaptive.skewJoin.enabled=true
      spark.serializer=org.apache.spark.serializer.KryoSerializer
      spark.sql.execution.arrow.pyspark.enabled=true
  ```

## Implementation Timeline

### Phase 1: Critical Security (Week 1)
- [ ] Enable EKS secrets encryption
- [ ] Implement network policies
- [ ] Configure RBAC with least privilege
- [ ] Enable audit logging

### Phase 2: Infrastructure Optimization (Week 2)
- [ ] Upgrade Kubernetes version
- [ ] Implement External Secrets Operator
- [ ] Configure encrypted storage classes
- [ ] Set up resource quotas

### Phase 3: Monitoring and Compliance (Week 3)
- [ ] Deploy Prometheus alerting rules
- [ ] Configure Grafana dashboards
- [ ] Implement cost monitoring
- [ ] Set up compliance reporting

### Phase 4: Performance Optimization (Week 4)
- [ ] Optimize RAPIDS configuration
- [ ] Fine-tune Karpenter settings
- [ ] Implement spot instance strategies
- [ ] Performance testing and validation

## Validation Checklist

After implementing these adjustments, validate the following:

- [ ] All security audit findings addressed
- [ ] Performance benchmarks meet requirements
- [ ] Cost optimization targets achieved
- [ ] Compliance requirements satisfied
- [ ] Monitoring and alerting functional
- [ ] Disaster recovery procedures tested
- [ ] Documentation updated
- [ ] Team training completed

## Rollback Procedures

Each adjustment should include rollback procedures:

1. **Infrastructure Changes**: Use Terraform state management
2. **Kubernetes Resources**: Maintain previous versions in Git
3. **Configuration Changes**: Document previous settings
4. **Security Policies**: Test in staging environment first

## Support and Maintenance

- **Security Updates**: Monthly security patch reviews
- **Performance Monitoring**: Weekly performance reports
- **Cost Optimization**: Monthly cost analysis
- **Compliance Audits**: Quarterly compliance reviews
- **Documentation Updates**: Continuous documentation maintenance

---

*This document should be reviewed and updated regularly as the production environment evolves and new requirements emerge.*