# EMR to EKS Migration Troubleshooting Runbook

## Overview

This runbook provides troubleshooting procedures for common issues encountered during and after the EMR to EKS migration.

## General Troubleshooting Approach

1. **Identify the Problem**: Gather symptoms and error messages
2. **Check System Status**: Verify cluster and service health
3. **Review Logs**: Examine relevant logs for error details
4. **Apply Solution**: Follow specific troubleshooting steps
5. **Verify Fix**: Confirm the issue is resolved
6. **Document**: Update runbook with new findings

## Infrastructure Issues

### EKS Cluster Issues

#### Issue: EKS Cluster Not Accessible

**Symptoms:**
- `kubectl` commands fail with connection errors
- Unable to access Kubernetes API

**Diagnosis:**
```bash
# Check cluster status
aws eks describe-cluster --name $EKS_CLUSTER_NAME --region $AWS_REGION

# Verify kubeconfig
kubectl config current-context
kubectl config view

# Test connectivity
kubectl get nodes
```

**Solutions:**

1. **Update kubeconfig:**
   ```bash
   aws eks update-kubeconfig --region $AWS_REGION --name $EKS_CLUSTER_NAME
   ```

2. **Check IAM permissions:**
   ```bash
   aws sts get-caller-identity
   # Verify the user/role has EKS access
   ```

3. **Verify security groups:**
   ```bash
   aws eks describe-cluster --name $EKS_CLUSTER_NAME --query 'cluster.resourcesVpcConfig.securityGroupIds'
   # Check security group rules allow access
   ```

#### Issue: Nodes Not Joining Cluster

**Symptoms:**
- Nodes show as "NotReady"
- Pods stuck in "Pending" state

**Diagnosis:**
```bash
# Check node status
kubectl get nodes -o wide

# Check node conditions
kubectl describe node <node-name>

# Check Karpenter logs
kubectl logs -n karpenter deployment/karpenter
```

**Solutions:**

1. **Check node group configuration:**
   ```bash
   aws eks describe-nodegroup --cluster-name $EKS_CLUSTER_NAME --nodegroup-name <nodegroup-name>
   ```

2. **Verify IAM roles:**
   ```bash
   # Check node instance profile
   aws iam get-instance-profile --instance-profile-name <profile-name>
   ```

3. **Check Karpenter provisioner:**
   ```bash
   kubectl get provisioner -o yaml
   kubectl get awsnodepool -o yaml
   ```

### EMR on EKS Issues

#### Issue: Virtual Cluster Not Running

**Symptoms:**
- Virtual cluster shows as "TERMINATED" or "FAILED"
- Cannot submit jobs to virtual cluster

**Diagnosis:**
```bash
# Check virtual cluster status
aws emr-containers describe-virtual-cluster --id $VIRTUAL_CLUSTER_ID

# List all virtual clusters
aws emr-containers list-virtual-clusters
```

**Solutions:**

1. **Recreate virtual cluster:**
   ```bash
   aws emr-containers create-virtual-cluster \
     --name fraud-detection-vc \
     --container-provider '{
       "type": "EKS",
       "id": "'$EKS_CLUSTER_NAME'",
       "info": {
         "eksInfo": {
           "namespace": "ml-team-a"
         }
       }
     }'
   ```

2. **Check namespace exists:**
   ```bash
   kubectl get namespace ml-team-a
   kubectl create namespace ml-team-a --dry-run=client -o yaml | kubectl apply -f -
   ```

#### Issue: EMR Jobs Failing

**Symptoms:**
- Jobs fail with "FAILED" status
- Error messages in job logs

**Diagnosis:**
```bash
# List job runs
aws emr-containers list-job-runs --virtual-cluster-id $VIRTUAL_CLUSTER_ID

# Describe specific job
aws emr-containers describe-job-run --virtual-cluster-id $VIRTUAL_CLUSTER_ID --id $JOB_RUN_ID

# Check job logs in CloudWatch
aws logs describe-log-groups --log-group-name-prefix /aws/emr-containers
```

**Solutions:**

1. **Check execution role permissions:**
   ```bash
   aws iam get-role --role-name EMRContainers-JobExecutionRole
   aws iam list-attached-role-policies --role-name EMRContainers-JobExecutionRole
   ```

2. **Verify S3 access:**
   ```bash
   aws s3 ls s3://$S3_BUCKET/scripts/
   aws s3 ls s3://$S3_BUCKET/data/
   ```

3. **Check resource allocation:**
   ```bash
   kubectl get pods -n ml-team-a
   kubectl describe pod <spark-driver-pod> -n ml-team-a
   ```

## Application Issues

### Ray Cluster Issues

#### Issue: Ray Cluster Not Starting

**Symptoms:**
- Ray cluster stuck in "pending" state
- Ray head or worker pods not starting

**Diagnosis:**
```bash
# Check Ray cluster status
kubectl get raycluster -n ml-team-a

# Check Ray pods
kubectl get pods -n ml-team-a -l ray.io/cluster=<cluster-name>

# Check Ray operator logs
kubectl logs -n ray-system deployment/kuberay-operator
```

**Solutions:**

1. **Check resource availability:**
   ```bash
   kubectl describe nodes
   kubectl get pods -n ml-team-a -o wide
   ```

2. **Verify Ray cluster configuration:**
   ```bash
   kubectl get raycluster <cluster-name> -n ml-team-a -o yaml
   ```

3. **Check image pull issues:**
   ```bash
   kubectl describe pod <ray-head-pod> -n ml-team-a
   # Look for ImagePullBackOff errors
   ```

#### Issue: Ray Training Jobs Failing

**Symptoms:**
- Ray jobs fail with error status
- Training scripts not executing properly

**Diagnosis:**
```bash
# Check Ray job status
kubectl get rayjob -n ml-team-a

# Check job logs
kubectl logs job/<ray-job-submitter> -n ml-team-a

# Check Ray dashboard
kubectl port-forward -n ml-team-a svc/<ray-head-svc> 8265:8265
# Access http://localhost:8265
```

**Solutions:**

1. **Check Python dependencies:**
   ```bash
   # Verify runtime environment in Ray job spec
   kubectl get rayjob <job-name> -n ml-team-a -o yaml
   ```

2. **Verify data access:**
   ```bash
   # Test S3 access from Ray worker
   kubectl exec -it <ray-worker-pod> -n ml-team-a -- python -c "import boto3; print(boto3.client('s3').list_buckets())"
   ```

3. **Check GPU availability:**
   ```bash
   kubectl exec -it <ray-worker-pod> -n ml-team-a -- nvidia-smi
   ```

### Inference Service Issues

#### Issue: Inference Service Not Responding

**Symptoms:**
- HTTP requests to inference service timeout
- Health checks failing

**Diagnosis:**
```bash
# Check service status
kubectl get deployment fraud-inference -n ml-team-a
kubectl get pods -l app=fraud-inference -n ml-team-a

# Check service logs
kubectl logs -l app=fraud-inference -n ml-team-a

# Test service connectivity
kubectl port-forward -n ml-team-a svc/fraud-inference 8080:80
curl http://localhost:8080/health
```

**Solutions:**

1. **Check pod health:**
   ```bash
   kubectl describe pod <inference-pod> -n ml-team-a
   kubectl exec -it <inference-pod> -n ml-team-a -- curl localhost:8000/health
   ```

2. **Verify model loading:**
   ```bash
   kubectl logs <inference-pod> -n ml-team-a | grep -i model
   # Check for model loading errors
   ```

3. **Check resource limits:**
   ```bash
   kubectl top pod <inference-pod> -n ml-team-a
   kubectl describe pod <inference-pod> -n ml-team-a | grep -A 10 Resources
   ```

#### Issue: High Inference Latency

**Symptoms:**
- Slow response times from inference service
- Timeouts under load

**Diagnosis:**
```bash
# Check HPA status
kubectl get hpa fraud-inference-hpa -n ml-team-a

# Monitor resource usage
kubectl top pods -n ml-team-a -l app=fraud-inference

# Check service metrics
kubectl port-forward -n prometheus svc/prometheus 9090:9090
# Query inference metrics in Prometheus
```

**Solutions:**

1. **Scale up replicas:**
   ```bash
   kubectl scale deployment fraud-inference --replicas=5 -n ml-team-a
   ```

2. **Optimize resource allocation:**
   ```bash
   kubectl patch deployment fraud-inference -n ml-team-a -p '{"spec":{"template":{"spec":{"containers":[{"name":"inference","resources":{"requests":{"cpu":"1","memory":"2Gi"},"limits":{"cpu":"4","memory":"8Gi"}}}]}}}}'
   ```

3. **Check model optimization:**
   - Review model size and complexity
   - Consider model quantization or pruning
   - Implement model caching

## Data Issues

### Data Processing Failures

#### Issue: RAPIDS Processing Errors

**Symptoms:**
- Spark jobs fail with RAPIDS-related errors
- GPU memory errors

**Diagnosis:**
```bash
# Check Spark driver logs
kubectl logs <spark-driver-pod> -n ml-team-a

# Check GPU availability
kubectl get nodes -l node.kubernetes.io/instance-type=g5.2xlarge
kubectl describe node <gpu-node>
```

**Solutions:**

1. **Verify GPU configuration:**
   ```bash
   # Check NVIDIA device plugin
   kubectl get daemonset nvidia-device-plugin-daemonset -n kube-system
   
   # Test GPU access
   kubectl run gpu-test --rm -it --restart=Never --image=nvidia/cuda:11.8-runtime-ubuntu20.04 -- nvidia-smi
   ```

2. **Adjust RAPIDS memory settings:**
   ```bash
   # Update Spark configuration
   --conf spark.rapids.memory.pinnedPool.size=2G
   --conf spark.executor.memory=28G
   --conf spark.executor.memoryFraction=0.8
   ```

3. **Check data format compatibility:**
   ```bash
   # Verify parquet file format
   aws s3 cp s3://$S3_BUCKET/data/sample.parquet /tmp/
   python -c "import pandas as pd; print(pd.read_parquet('/tmp/sample.parquet').dtypes)"
   ```

#### Issue: Data Inconsistency

**Symptoms:**
- Different results between EMR and EMR on EKS
- Missing or corrupted data

**Diagnosis:**
```bash
# Compare data checksums
aws s3api head-object --bucket $S3_BUCKET --key data/input/file.parquet
aws s3api head-object --bucket $S3_BUCKET --key data/output/file.parquet

# Run data validation script
python migration/scripts/validation/validate-migration.py --config validation-config.json
```

**Solutions:**

1. **Re-run data migration:**
   ```bash
   python migration/scripts/data-migration/emr-to-emr-on-eks.py \
     --emr-cluster-id $SOURCE_EMR_CLUSTER_ID \
     --virtual-cluster-id $VIRTUAL_CLUSTER_ID \
     --cluster-name $EKS_CLUSTER_NAME
   ```

2. **Check data transformation logic:**
   - Review feature engineering code
   - Verify datetime handling
   - Check aggregation functions

## Performance Issues

### Slow Job Execution

#### Issue: EMR on EKS Jobs Running Slowly

**Symptoms:**
- Jobs take longer than expected
- Low resource utilization

**Diagnosis:**
```bash
# Check resource allocation
kubectl get pods -n ml-team-a -o wide
kubectl top pods -n ml-team-a

# Monitor Spark UI
kubectl port-forward <spark-driver-pod> -n ml-team-a 4040:4040
# Access http://localhost:4040
```

**Solutions:**

1. **Optimize Spark configuration:**
   ```bash
   --conf spark.executor.instances=12
   --conf spark.executor.cores=4
   --conf spark.executor.memory=30G
   --conf spark.sql.shuffle.partitions=400
   --conf spark.sql.adaptive.enabled=true
   ```

2. **Use appropriate instance types:**
   ```bash
   # Update Karpenter provisioner for better instance selection
   kubectl patch provisioner default --type='merge' -p='{"spec":{"requirements":[{"key":"karpenter.sh/capacity-type","operator":"In","values":["spot","on-demand"]},{"key":"node.kubernetes.io/instance-type","operator":"In","values":["m5.xlarge","m5.2xlarge","g5.xlarge","g5.2xlarge"]}]}}'
   ```

### Memory Issues

#### Issue: Out of Memory Errors

**Symptoms:**
- Pods killed with OOMKilled status
- Java heap space errors

**Diagnosis:**
```bash
# Check pod resource usage
kubectl top pod <pod-name> -n ml-team-a
kubectl describe pod <pod-name> -n ml-team-a

# Check node memory
kubectl top nodes
```

**Solutions:**

1. **Increase memory limits:**
   ```bash
   kubectl patch deployment <deployment-name> -n ml-team-a -p '{"spec":{"template":{"spec":{"containers":[{"name":"<container-name>","resources":{"limits":{"memory":"8Gi"}}}]}}}}'
   ```

2. **Optimize memory usage:**
   ```bash
   # For Spark jobs
   --conf spark.executor.memory=28G
   --conf spark.executor.memoryFraction=0.8
   --conf spark.serializer=org.apache.spark.serializer.KryoSerializer
   ```

## Monitoring and Alerting Issues

### Missing Metrics

#### Issue: Prometheus Not Collecting Metrics

**Symptoms:**
- Missing metrics in Grafana dashboards
- Prometheus targets down

**Diagnosis:**
```bash
# Check Prometheus status
kubectl get pods -n prometheus
kubectl port-forward -n prometheus svc/prometheus 9090:9090

# Check service monitors
kubectl get servicemonitor -n prometheus
```

**Solutions:**

1. **Verify service monitor configuration:**
   ```bash
   kubectl get servicemonitor -n prometheus -o yaml
   ```

2. **Check service labels:**
   ```bash
   kubectl get service -n ml-team-a --show-labels
   ```

3. **Restart Prometheus:**
   ```bash
   kubectl rollout restart deployment prometheus -n prometheus
   ```

### Alert Fatigue

#### Issue: Too Many False Positive Alerts

**Symptoms:**
- Excessive alert notifications
- Important alerts missed due to noise

**Solutions:**

1. **Tune alert thresholds:**
   ```bash
   kubectl edit prometheusrule -n prometheus
   # Adjust alert conditions and thresholds
   ```

2. **Implement alert grouping:**
   ```yaml
   # Update Alertmanager configuration
   route:
     group_by: ['alertname', 'cluster', 'service']
     group_wait: 10s
     group_interval: 10s
     repeat_interval: 1h
   ```

## Security Issues

### RBAC Issues

#### Issue: Permission Denied Errors

**Symptoms:**
- Pods cannot access Kubernetes API
- Service account permission errors

**Diagnosis:**
```bash
# Check service account
kubectl get serviceaccount -n ml-team-a
kubectl describe serviceaccount <sa-name> -n ml-team-a

# Check role bindings
kubectl get rolebinding -n ml-team-a
kubectl get clusterrolebinding | grep ml-team-a
```

**Solutions:**

1. **Create proper RBAC:**
   ```bash
   kubectl apply -f - <<EOF
   apiVersion: rbac.authorization.k8s.io/v1
   kind: Role
   metadata:
     namespace: ml-team-a
     name: fraud-detection-role
   rules:
   - apiGroups: [""]
     resources: ["pods", "services"]
     verbs: ["get", "list", "watch"]
   ---
   apiVersion: rbac.authorization.k8s.io/v1
   kind: RoleBinding
   metadata:
     name: fraud-detection-binding
     namespace: ml-team-a
   subjects:
   - kind: ServiceAccount
     name: fraud-inference-sa
     namespace: ml-team-a
   roleRef:
     kind: Role
     name: fraud-detection-role
     apiGroup: rbac.authorization.k8s.io
   EOF
   ```

### Network Security Issues

#### Issue: Service Communication Failures

**Symptoms:**
- Services cannot communicate with each other
- Network policy blocking traffic

**Diagnosis:**
```bash
# Check network policies
kubectl get networkpolicy -n ml-team-a

# Test connectivity
kubectl run test-pod --rm -it --restart=Never --image=busybox -- nslookup fraud-inference.ml-team-a.svc.cluster.local
```

**Solutions:**

1. **Update network policies:**
   ```bash
   kubectl apply -f - <<EOF
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: allow-inference-traffic
     namespace: ml-team-a
   spec:
     podSelector:
       matchLabels:
         app: fraud-inference
     policyTypes:
     - Ingress
     - Egress
     ingress:
     - from: []
     egress:
     - to: []
   EOF
   ```

## Emergency Procedures

### Complete System Failure

#### Immediate Actions

1. **Assess Impact:**
   ```bash
   # Check cluster status
   kubectl get nodes
   kubectl get pods --all-namespaces
   
   # Check critical services
   kubectl get deployment -n ml-team-a
   kubectl get service -n ml-team-a
   ```

2. **Activate Rollback:**
   ```bash
   # Redirect traffic to backup systems
   # Update DNS or load balancer configuration
   
   # Scale down failed services
   kubectl scale deployment fraud-inference --replicas=0 -n ml-team-a
   ```

3. **Notify Stakeholders:**
   - Send incident notification
   - Update status page
   - Coordinate with on-call team

#### Recovery Actions

1. **Restore from Backup:**
   ```bash
   # Restore cluster configuration
   kubectl apply -f backup/cluster-config.yaml
   
   # Restore data from S3 backup
   aws s3 sync s3://$BACKUP_BUCKET/data/ s3://$S3_BUCKET/data/
   ```

2. **Validate Recovery:**
   ```bash
   # Run validation tests
   python migration/scripts/validation/validate-migration.py --config validation-config.json
   
   # Test critical paths
   curl -X POST http://fraud-inference.ml-team-a.svc.cluster.local/predict -d '{"features": {...}}'
   ```

## Escalation Procedures

### When to Escalate

- System-wide outages lasting > 15 minutes
- Data corruption or loss
- Security breaches
- Performance degradation > 50% for > 30 minutes

### Escalation Contacts

1. **Level 1 - Platform Engineer**
   - Response time: 15 minutes
   - Contact: platform-oncall@company.com

2. **Level 2 - Senior Platform Engineer**
   - Response time: 30 minutes
   - Contact: senior-platform-oncall@company.com

3. **Level 3 - Platform Architect**
   - Response time: 1 hour
   - Contact: platform-architect@company.com

4. **Level 4 - Engineering Manager**
   - Response time: 2 hours
   - Contact: eng-manager@company.com

### Incident Communication

1. **Create incident ticket**
2. **Join incident bridge**: +1-555-INCIDENT
3. **Update status page**: status.company.com
4. **Send stakeholder updates every 30 minutes**

## Post-Incident Actions

1. **Conduct post-mortem**
2. **Update runbooks with lessons learned**
3. **Implement preventive measures**
4. **Update monitoring and alerting**
5. **Schedule follow-up reviews**