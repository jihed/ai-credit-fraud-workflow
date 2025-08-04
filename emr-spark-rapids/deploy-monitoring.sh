#!/bin/bash

# Deploy Enhanced Monitoring and Observability for EMR to EKS Migration
# This script deploys Prometheus, Grafana, custom metrics, and alerting rules

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_NAME=${CLUSTER_NAME:-"data-on-eks"}
AWS_REGION=${AWS_REGION:-"us-west-2"}
NAMESPACE_MONITORING="kube-prometheus-stack"
NAMESPACE_CLOUDWATCH="amazon-cloudwatch"
GRAFANA_PASSWORD=${GRAFANA_PASSWORD:-$(openssl rand -base64 32)}

echo -e "${GREEN}Starting Enhanced Monitoring Deployment for EMR to EKS Migration${NC}"
echo -e "${BLUE}Cluster: ${CLUSTER_NAME}, Region: ${AWS_REGION}${NC}"

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"
if ! command_exists kubectl; then
    echo -e "${RED}kubectl is required but not installed${NC}"
    exit 1
fi

if ! command_exists helm; then
    echo -e "${RED}helm is required but not installed${NC}"
    exit 1
fi

# Verify cluster connection
echo -e "${YELLOW}Verifying cluster connection...${NC}"
if ! kubectl cluster-info >/dev/null 2>&1; then
    echo -e "${RED}Cannot connect to Kubernetes cluster${NC}"
    exit 1
fi

# Create namespaces
echo -e "${YELLOW}Creating namespaces...${NC}"
kubectl create namespace ${NAMESPACE_MONITORING} --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace ${NAMESPACE_CLOUDWATCH} --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace fraud-detection --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace kubecost --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace ray-system --dry-run=client -o yaml | kubectl apply -f -

# Add Helm repositories
echo -e "${YELLOW}Adding Helm repositories...${NC}"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
helm repo add grafana https://grafana.github.io/helm-charts || true
helm repo add kubecost https://kubecost.github.io/cost-analyzer/ || true
helm repo update

# Deploy kube-prometheus-stack with enhanced configuration
echo -e "${YELLOW}Deploying kube-prometheus-stack...${NC}"
envsubst < monitoring/enhanced-kube-prometheus.yaml > /tmp/enhanced-kube-prometheus.yaml
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
    --namespace ${NAMESPACE_MONITORING} \
    --values /tmp/enhanced-kube-prometheus.yaml \
    --set grafana.adminPassword="${GRAFANA_PASSWORD}" \
    --wait --timeout=10m

# Deploy custom recording rules
echo -e "${YELLOW}Deploying custom recording rules...${NC}"
kubectl apply -f monitoring/custom-recording-rules.yaml

# Deploy alerting rules
echo -e "${YELLOW}Deploying alerting rules...${NC}"
kubectl apply -f monitoring/alerting-rules.yaml

# Deploy custom metrics exporters
echo -e "${YELLOW}Deploying custom metrics exporters...${NC}"
# Replace ACCOUNT_ID placeholder with actual account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
sed "s/ACCOUNT_ID/${ACCOUNT_ID}/g" monitoring/custom-metrics-exporters.yaml | kubectl apply -f -

# Deploy CloudWatch integration
echo -e "${YELLOW}Deploying CloudWatch integration...${NC}"
# Replace ACCOUNT_ID placeholder with actual account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
sed "s/ACCOUNT_ID/${ACCOUNT_ID}/g" monitoring/cloudwatch-integration.yaml | kubectl apply -f -

# Create Grafana dashboard ConfigMap
echo -e "${YELLOW}Creating Grafana dashboard ConfigMap...${NC}"
kubectl create configmap fraud-detection-dashboard \
    --from-file=monitoring/dashboards/fraud-detection-overview.json \
    --namespace=${NAMESPACE_MONITORING} \
    --dry-run=client -o yaml | kubectl apply -f -

# Label the ConfigMap for Grafana to pick it up
kubectl label configmap fraud-detection-dashboard \
    grafana_dashboard=1 \
    --namespace=${NAMESPACE_MONITORING} \
    --overwrite

# Deploy NVIDIA DCGM Exporter for GPU metrics
echo -e "${YELLOW}Deploying NVIDIA DCGM Exporter...${NC}"
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: nvidia-dcgm-exporter
  namespace: kube-system
  labels:
    app: nvidia-dcgm-exporter
spec:
  selector:
    matchLabels:
      app: nvidia-dcgm-exporter
  template:
    metadata:
      labels:
        app: nvidia-dcgm-exporter
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "9400"
    spec:
      tolerations:
      - key: nvidia.com/gpu
        operator: Exists
        effect: NoSchedule
      nodeSelector:
        accelerator: nvidia
      containers:
      - name: nvidia-dcgm-exporter
        image: nvcr.io/nvidia/k8s/dcgm-exporter:3.3.5-3.4.0-ubuntu22.04
        ports:
        - name: metrics
          containerPort: 9400
        securityContext:
          runAsNonRoot: false
          runAsUser: 0
        volumeMounts:
        - name: proc
          mountPath: /host/proc
          readOnly: true
        - name: sys
          mountPath: /host/sys
          readOnly: true
        env:
        - name: DCGM_EXPORTER_LISTEN
          value: ":9400"
        - name: DCGM_EXPORTER_KUBERNETES
          value: "true"
        resources:
          requests:
            memory: 128Mi
            cpu: 50m
          limits:
            memory: 256Mi
            cpu: 100m
      volumes:
      - name: proc
        hostPath:
          path: /proc
      - name: sys
        hostPath:
          path: /sys
      hostNetwork: true
      hostPID: true
EOF

# Create ServiceMonitor for NVIDIA DCGM Exporter
echo -e "${YELLOW}Creating ServiceMonitor for NVIDIA DCGM Exporter...${NC}"
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: nvidia-dcgm-exporter
  namespace: kube-system
  labels:
    app: nvidia-dcgm-exporter
spec:
  ports:
  - name: metrics
    port: 9400
    targetPort: 9400
  selector:
    app: nvidia-dcgm-exporter
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: nvidia-dcgm-exporter
  namespace: kube-system
  labels:
    app: nvidia-dcgm-exporter
spec:
  selector:
    matchLabels:
      app: nvidia-dcgm-exporter
  endpoints:
  - port: metrics
    interval: 30s
    path: /metrics
EOF

# Deploy Kubecost for cost monitoring
echo -e "${YELLOW}Deploying Kubecost for cost monitoring...${NC}"
helm upgrade --install kubecost kubecost/cost-analyzer \
    --namespace kubecost \
    --values helm-values/kubecost-values.yaml \
    --wait --timeout=10m

# Create ServiceMonitor for Kubecost
cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: kubecost
  namespace: kubecost
  labels:
    app: kubecost
spec:
  selector:
    matchLabels:
      app: cost-analyzer
  endpoints:
  - port: http
    interval: 60s
    path: /metrics
EOF

# Deploy enhanced AWS for Fluent Bit for log aggregation
echo -e "${YELLOW}Deploying enhanced AWS for Fluent Bit configuration...${NC}"
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluent-bit-config
  namespace: amazon-cloudwatch
  labels:
    k8s-app: fluent-bit
data:
  fluent-bit.conf: |
    [SERVICE]
        Flush                     5
        Grace                     30
        Log_Level                 info
        Daemon                    off
        Parsers_File              parsers.conf
        HTTP_Server               On
        HTTP_Listen               0.0.0.0
        HTTP_Port                 2020
        storage.path              /var/fluent-bit/state/flb-storage/
        storage.sync              normal
        storage.checksum          off
        storage.backlog.mem_limit 5M

    @INCLUDE application-log.conf
    @INCLUDE dataplane-log.conf
    @INCLUDE host-log.conf

  application-log.conf: |
    [INPUT]
        Name                tail
        Tag                 application.*
        Exclude_Path        /var/log/containers/cloudwatch-agent*, /var/log/containers/fluent-bit*, /var/log/containers/aws-node*, /var/log/containers/kube-proxy*
        Path                /var/log/containers/*.log
        multiline.parser    docker, cri
        DB                  /var/fluent-bit/state/flb_container.db
        Mem_Buf_Limit       50MB
        Skip_Long_Lines     On
        Refresh_Interval    10
        Rotate_Wait         30
        storage.type        filesystem
        Read_from_Head      \${READ_FROM_HEAD}

    [INPUT]
        Name                tail
        Tag                 application.emr.*
        Path                /var/log/containers/*emr*.log
        multiline.parser    docker, cri
        DB                  /var/fluent-bit/state/flb_emr.db
        Mem_Buf_Limit       50MB
        Skip_Long_Lines     On
        Refresh_Interval    10
        storage.type        filesystem
        Read_from_Head      \${READ_FROM_HEAD}

    [INPUT]
        Name                tail
        Tag                 application.ray.*
        Path                /var/log/containers/*ray*.log
        multiline.parser    docker, cri
        DB                  /var/fluent-bit/state/flb_ray.db
        Mem_Buf_Limit       50MB
        Skip_Long_Lines     On
        Refresh_Interval    10
        storage.type        filesystem
        Read_from_Head      \${READ_FROM_HEAD}

    [INPUT]
        Name                tail
        Tag                 application.inference.*
        Path                /var/log/containers/*fraud-inference*.log
        multiline.parser    docker, cri
        DB                  /var/fluent-bit/state/flb_inference.db
        Mem_Buf_Limit       50MB
        Skip_Long_Lines     On
        Refresh_Interval    10
        storage.type        filesystem
        Read_from_Head      \${READ_FROM_HEAD}

    [FILTER]
        Name                kubernetes
        Match               application.*
        Kube_URL            https://kubernetes.default.svc:443
        Kube_Tag_Prefix     application.var.log.containers.
        Merge_Log           On
        Merge_Log_Key       log_processed
        K8S-Logging.Parser  On
        K8S-Logging.Exclude Off
        Labels              Off
        Annotations         Off
        Use_Kubelet         On
        Kubelet_Port        10250
        Buffer_Size         0

    [OUTPUT]
        Name                cloudwatch_logs
        Match               application.emr.*
        region              \${AWS_REGION}
        log_group_name      /aws/eks/\${CLUSTER_NAME}/emr-containers
        log_stream_prefix   \${HOST_NAME}-
        auto_create_group   true
        extra_user_agent    container-insights

    [OUTPUT]
        Name                cloudwatch_logs
        Match               application.ray.*
        region              \${AWS_REGION}
        log_group_name      /aws/eks/\${CLUSTER_NAME}/ray-training
        log_stream_prefix   \${HOST_NAME}-
        auto_create_group   true
        extra_user_agent    container-insights

    [OUTPUT]
        Name                cloudwatch_logs
        Match               application.inference.*
        region              \${AWS_REGION}
        log_group_name      /aws/eks/\${CLUSTER_NAME}/inference-service
        log_stream_prefix   \${HOST_NAME}-
        auto_create_group   true
        extra_user_agent    container-insights

    [OUTPUT]
        Name                cloudwatch_logs
        Match               application.*
        region              \${AWS_REGION}
        log_group_name      /aws/eks/\${CLUSTER_NAME}/application
        log_stream_prefix   \${HOST_NAME}-
        auto_create_group   true
        extra_user_agent    container-insights

  dataplane-log.conf: |
    [INPUT]
        Name                systemd
        Tag                 dataplane.systemd.*
        Systemd_Filter      _SYSTEMD_UNIT=docker.service
        Systemd_Filter      _SYSTEMD_UNIT=containerd.service
        Systemd_Filter      _SYSTEMD_UNIT=kubelet.service
        DB                  /var/fluent-bit/state/systemd.db
        Path                /var/log/journal
        Read_From_Tail      \${READ_FROM_TAIL}

    [INPUT]
        Name                tail
        Tag                 dataplane.tail.*
        Path                /var/log/containers/aws-node*, /var/log/containers/kube-proxy*
        multiline.parser    docker, cri
        DB                  /var/fluent-bit/state/flb_dataplane_tail.db
        Mem_Buf_Limit       50MB
        Skip_Long_Lines     On
        Refresh_Interval    10
        Rotate_Wait         30
        storage.type        filesystem
        Read_from_Head      \${READ_FROM_HEAD}

    [FILTER]
        Name                modify
        Match               dataplane.systemd.*
        Rename              _HOSTNAME                   hostname
        Rename              _SYSTEMD_UNIT               systemd_unit
        Rename              MESSAGE                     message
        Remove_regex        ^((?!hostname|systemd_unit|message).)*$

    [FILTER]
        Name                aws
        Match               dataplane.*
        imds_version        v1

    [OUTPUT]
        Name                cloudwatch_logs
        Match               dataplane.*
        region              \${AWS_REGION}
        log_group_name      /aws/eks/\${CLUSTER_NAME}/cluster
        log_stream_prefix   \${HOST_NAME}-
        auto_create_group   true
        extra_user_agent    container-insights

  host-log.conf: |
    [INPUT]
        Name                tail
        Tag                 host.dmesg
        Path                /var/log/dmesg
        Key                 message
        DB                  /var/fluent-bit/state/flb_dmesg.db
        Mem_Buf_Limit       5MB
        Skip_Long_Lines     On
        Refresh_Interval    10
        Read_from_Head      \${READ_FROM_HEAD}

    [INPUT]
        Name                tail
        Tag                 host.messages
        Path                /var/log/messages
        Parser              syslog
        DB                  /var/fluent-bit/state/flb_messages.db
        Mem_Buf_Limit       5MB
        Skip_Long_Lines     On
        Refresh_Interval    10
        Read_from_Head      \${READ_FROM_HEAD}

    [INPUT]
        Name                tail
        Tag                 host.secure
        Path                /var/log/secure
        Parser              syslog
        DB                  /var/fluent-bit/state/flb_secure.db
        Mem_Buf_Limit       5MB
        Skip_Long_Lines     On
        Refresh_Interval    10
        Read_from_Head      \${READ_FROM_HEAD}

    [FILTER]
        Name                aws
        Match               host.*
        imds_version        v1

    [OUTPUT]
        Name                cloudwatch_logs
        Match               host.*
        region              \${AWS_REGION}
        log_group_name      /aws/eks/\${CLUSTER_NAME}/host
        log_stream_prefix   \${HOST_NAME}-
        auto_create_group   true
        extra_user_agent    container-insights

  parsers.conf: |
    [PARSER]
        Name                syslog
        Format              regex
        Regex               ^(?<time>[^ ]* {1,2}[^ ]* [^ ]*) (?<host>[^ ]*) (?<ident>[a-zA-Z0-9_\/\.\-]*)(?:\[(?<pid>[0-9]+)\])?(?:[^\:]*\:)? *(?<message>.*)$
        Time_Key            time
        Time_Format         %b %d %H:%M:%S

    [PARSER]
        Name                container_firstline
        Format              regex
        Regex               (?<log>(?<="log":")\S(?!\.).*?)(?<!\\)".*(?<stream>(?<="stream":").*?)".*(?<time>\d{4}-\d{1,2}-\d{1,2}T\d{2}:\d{2}:\d{2}\.\w*).*(?=})
        Time_Key            time
        Time_Format         %Y-%m-%dT%H:%M:%S.%LZ

    [PARSER]
        Name                cwagent_firstline
        Format              regex
        Regex               (?<log>(?<="log":")\d{4}[\/-]\d{1,2}[\/-]\d{1,2}[ T]\d{2}:\d{2}:\d{2}(?!\.).*?)(?<!\\)".*(?<stream>(?<="stream":").*?)".*(?<time>\d{4}-\d{1,2}-\d{1,2}T\d{2}:\d{2}:\d{2}\.\w*).*(?=})
        Time_Key            time
        Time_Format         %Y-%m-%dT%H:%M:%S.%LZ
EOF

# Deploy AWS for Fluent Bit DaemonSet
helm repo add aws https://aws.github.io/eks-charts || true
helm repo update

helm upgrade --install aws-for-fluent-bit aws/aws-for-fluent-bit \
    --namespace amazon-cloudwatch \
    --values helm-values/aws-for-fluentbit-values.yaml \
    --set cloudWatchLogs.region=${AWS_REGION} \
    --set cloudWatchLogs.logGroupName="/aws/eks/${CLUSTER_NAME}" \
    --set firehose.enabled=false \
    --set kinesis.enabled=false \
    --wait --timeout=5m

# Wait for deployments to be ready
echo -e "${YELLOW}Waiting for monitoring components to be ready...${NC}"
kubectl wait --for=condition=ready pod -l app=nvidia-dcgm-exporter -n kube-system --timeout=300s || true
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=kubecost -n kubecost --timeout=300s || true

# Verify Prometheus targets
echo -e "${YELLOW}Verifying Prometheus configuration...${NC}"
sleep 30

# Get Prometheus pod
PROMETHEUS_POD=$(kubectl get pods -n ${NAMESPACE_MONITORING} -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.name}')

if [ -n "$PROMETHEUS_POD" ]; then
    echo -e "${GREEN}Prometheus pod found: $PROMETHEUS_POD${NC}"
    
    # Port forward to check targets (run in background)
    kubectl port-forward -n ${NAMESPACE_MONITORING} pod/$PROMETHEUS_POD 9090:9090 &
    PF_PID=$!
    
    sleep 10
    
    # Check if targets are up
    echo -e "${YELLOW}Checking Prometheus targets...${NC}"
    curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.health != "up") | {job: .labels.job, health: .health, lastError: .lastError}' || true
    
    # Kill port forward
    kill $PF_PID 2>/dev/null || true
fi

# Create monitoring validation script
echo -e "${YELLOW}Creating monitoring validation script...${NC}"
cat <<'EOF' > validate-monitoring.sh
#!/bin/bash

echo "=== Monitoring Validation ==="

# Check Prometheus
echo "Checking Prometheus..."
kubectl get pods -n kube-prometheus-stack -l app.kubernetes.io/name=prometheus

# Check Grafana
echo "Checking Grafana..."
kubectl get pods -n kube-prometheus-stack -l app.kubernetes.io/name=grafana

# Check NVIDIA DCGM Exporter
echo "Checking NVIDIA DCGM Exporter..."
kubectl get pods -n kube-system -l app=nvidia-dcgm-exporter

# Check Kubecost
echo "Checking Kubecost..."
kubectl get pods -n kubecost -l app.kubernetes.io/name=kubecost

# Check custom rules
echo "Checking custom PrometheusRules..."
kubectl get prometheusrules -n kube-prometheus-stack

# Check ServiceMonitors
echo "Checking ServiceMonitors..."
kubectl get servicemonitors -A

echo "=== Access Information ==="
echo "Grafana: kubectl port-forward -n kube-prometheus-stack svc/kube-prometheus-stack-grafana 3000:80"
echo "Prometheus: kubectl port-forward -n kube-prometheus-stack svc/kube-prometheus-stack-prometheus 9090:9090"
echo "Kubecost: kubectl port-forward -n kubecost svc/kubecost-cost-analyzer 9090:9090"

echo "=== Grafana Admin Password ==="
kubectl get secret -n kube-prometheus-stack kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d
echo
EOF

chmod +x validate-monitoring.sh

echo -e "${GREEN}Enhanced monitoring deployment completed successfully!${NC}"
echo -e "${YELLOW}Run ./validate-monitoring.sh to verify the deployment${NC}"
echo -e "${YELLOW}Access Grafana: kubectl port-forward -n kube-prometheus-stack svc/kube-prometheus-stack-grafana 3000:80${NC}"
echo -e "${YELLOW}Default Grafana credentials: admin / (run kubectl get secret -n kube-prometheus-stack kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d)${NC}"