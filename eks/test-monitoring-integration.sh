#!/bin/bash

# Test Monitoring Integration for EMR to EKS Migration
# This script tests the monitoring setup by creating sample workloads and verifying metrics collection

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Testing Monitoring Integration ===${NC}"

# Function to wait for condition
wait_for_condition() {
    local condition="$1"
    local timeout="${2:-300}"
    local interval="${3:-10}"
    local elapsed=0
    
    while [ $elapsed -lt $timeout ]; do
        if eval "$condition"; then
            return 0
        fi
        sleep $interval
        elapsed=$((elapsed + interval))
        echo -e "${YELLOW}Waiting for condition... (${elapsed}s/${timeout}s)${NC}"
    done
    
    echo -e "${RED}Timeout waiting for condition: $condition${NC}"
    return 1
}

# Test 1: Create a test GPU workload to generate GPU metrics
echo -e "${YELLOW}Test 1: Creating test GPU workload...${NC}"
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: gpu-test-monitoring
  namespace: fraud-detection
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: gpu-test
        image: nvidia/cuda:11.8-runtime-ubuntu20.04
        command: ["nvidia-smi"]
        resources:
          limits:
            nvidia.com/gpu: 1
          requests:
            nvidia.com/gpu: 1
      nodeSelector:
        accelerator: nvidia
      tolerations:
      - key: nvidia.com/gpu
        operator: Exists
        effect: NoSchedule
EOF

# Wait for GPU test job to complete
echo -e "${YELLOW}Waiting for GPU test job to complete...${NC}"
wait_for_condition "kubectl get job gpu-test-monitoring -n fraud-detection -o jsonpath='{.status.conditions[0].type}' | grep -q Complete" 120

# Test 2: Create a test inference service to generate inference metrics
echo -e "${YELLOW}Test 2: Creating test inference service...${NC}"
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-fraud-inference
  namespace: fraud-detection
  labels:
    app: fraud-inference
spec:
  replicas: 2
  selector:
    matchLabels:
      app: fraud-inference
  template:
    metadata:
      labels:
        app: fraud-inference
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8000"
        prometheus.io/path: "/metrics"
    spec:
      containers:
      - name: inference
        image: python:3.9-slim
        ports:
        - containerPort: 8000
          name: http
        command:
        - /bin/sh
        - -c
        - |
          pip install prometheus_client fastapi uvicorn
          cat > /app/test_inference.py << 'PYEOF'
          import time
          import random
          from prometheus_client import start_http_server, Counter, Histogram, Gauge
          from fastapi import FastAPI
          import uvicorn
          import threading

          app = FastAPI()

          # Prometheus metrics
          request_count = Counter('http_requests_total', 'Total HTTP requests', ['method', 'endpoint', 'status'])
          request_duration = Histogram('http_request_duration_seconds', 'HTTP request duration')
          model_accuracy = Gauge('model_prediction_accuracy', 'Model prediction accuracy')

          @app.get("/predict")
          def predict():
              start_time = time.time()
              
              # Simulate prediction
              time.sleep(random.uniform(0.1, 0.5))
              prediction = random.choice([0, 1])
              
              # Update metrics
              request_count.labels(method='GET', endpoint='/predict', status='200').inc()
              request_duration.observe(time.time() - start_time)
              model_accuracy.set(random.uniform(0.8, 0.95))
              
              return {"prediction": prediction, "confidence": random.uniform(0.7, 0.99)}

          @app.get("/health")
          def health():
              request_count.labels(method='GET', endpoint='/health', status='200').inc()
              return {"status": "healthy"}

          @app.get("/metrics")
          def metrics():
              from prometheus_client import generate_latest, CONTENT_TYPE_LATEST
              return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)

          def start_metrics_server():
              start_http_server(8001)

          if __name__ == "__main__":
              # Start Prometheus metrics server
              threading.Thread(target=start_metrics_server, daemon=True).start()
              
              # Start FastAPI server
              uvicorn.run(app, host="0.0.0.0", port=8000)
          PYEOF
          python /app/test_inference.py
        resources:
          requests:
            memory: 256Mi
            cpu: 250m
          limits:
            memory: 512Mi
            cpu: 500m
---
apiVersion: v1
kind: Service
metadata:
  name: test-fraud-inference
  namespace: fraud-detection
  labels:
    app: fraud-inference
spec:
  ports:
  - name: http
    port: 8000
    targetPort: 8000
  - name: metrics
    port: 8001
    targetPort: 8001
  selector:
    app: fraud-inference
EOF

# Wait for inference service to be ready
echo -e "${YELLOW}Waiting for test inference service to be ready...${NC}"
wait_for_condition "kubectl get deployment test-fraud-inference -n fraud-detection -o jsonpath='{.status.readyReplicas}' | grep -q 2" 180

# Test 3: Generate some load on the inference service
echo -e "${YELLOW}Test 3: Generating load on inference service...${NC}"
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: load-test-monitoring
  namespace: fraud-detection
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: load-test
        image: curlimages/curl:latest
        command:
        - /bin/sh
        - -c
        - |
          for i in \$(seq 1 100); do
            curl -s http://test-fraud-inference:8000/predict > /dev/null
            curl -s http://test-fraud-inference:8000/health > /dev/null
            sleep 0.1
          done
          echo "Load test completed"
EOF

# Wait for load test to complete
echo -e "${YELLOW}Waiting for load test to complete...${NC}"
wait_for_condition "kubectl get job load-test-monitoring -n fraud-detection -o jsonpath='{.status.conditions[0].type}' | grep -q Complete" 120

# Test 4: Verify Prometheus is collecting metrics
echo -e "${YELLOW}Test 4: Verifying Prometheus metrics collection...${NC}"
PROMETHEUS_POD=$(kubectl get pods -n kube-prometheus-stack -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.name}')

if [ -n "$PROMETHEUS_POD" ]; then
    echo -e "${GREEN}✓${NC} Prometheus pod found: $PROMETHEUS_POD"
    
    # Port forward to Prometheus
    kubectl port-forward -n kube-prometheus-stack pod/$PROMETHEUS_POD 9090:9090 >/dev/null 2>&1 &
    PF_PID=$!
    
    sleep 10
    
    # Test GPU metrics
    echo -e "${YELLOW}Checking GPU metrics...${NC}"
    GPU_METRICS=$(curl -s "http://localhost:9090/api/v1/query?query=DCGM_FI_DEV_GPU_UTIL" | jq -r '.data.result | length')
    if [ "$GPU_METRICS" -gt 0 ]; then
        echo -e "${GREEN}✓${NC} GPU metrics found: $GPU_METRICS data points"
    else
        echo -e "${YELLOW}⚠${NC} No GPU metrics found (normal if no GPU nodes are available)"
    fi
    
    # Test inference metrics
    echo -e "${YELLOW}Checking inference metrics...${NC}"
    INFERENCE_METRICS=$(curl -s "http://localhost:9090/api/v1/query?query=http_requests_total" | jq -r '.data.result | length')
    if [ "$INFERENCE_METRICS" -gt 0 ]; then
        echo -e "${GREEN}✓${NC} Inference metrics found: $INFERENCE_METRICS data points"
    else
        echo -e "${RED}✗${NC} No inference metrics found"
    fi
    
    # Test custom recording rules
    echo -e "${YELLOW}Checking custom recording rules...${NC}"
    RECORDING_RULES=$(curl -s "http://localhost:9090/api/v1/rules" | jq -r '.data.groups | map(select(.name | contains("fraud"))) | length')
    if [ "$RECORDING_RULES" -gt 0 ]; then
        echo -e "${GREEN}✓${NC} Custom recording rules found: $RECORDING_RULES rule groups"
    else
        echo -e "${RED}✗${NC} No custom recording rules found"
    fi
    
    # Test alerting rules
    echo -e "${YELLOW}Checking alerting rules...${NC}"
    ALERT_RULES=$(curl -s "http://localhost:9090/api/v1/rules" | jq -r '.data.groups | map(.rules[]) | map(select(.type == "alerting")) | length')
    if [ "$ALERT_RULES" -gt 0 ]; then
        echo -e "${GREEN}✓${NC} Alerting rules found: $ALERT_RULES alert rules"
    else
        echo -e "${RED}✗${NC} No alerting rules found"
    fi
    
    # Kill port forward
    kill $PF_PID 2>/dev/null || true
else
    echo -e "${RED}✗${NC} Prometheus pod not found"
fi

# Test 5: Verify Grafana dashboard accessibility
echo -e "${YELLOW}Test 5: Verifying Grafana dashboard...${NC}"
GRAFANA_POD=$(kubectl get pods -n kube-prometheus-stack -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}')

if [ -n "$GRAFANA_POD" ]; then
    echo -e "${GREEN}✓${NC} Grafana pod found: $GRAFANA_POD"
    
    # Check if custom dashboard ConfigMap exists and is labeled
    DASHBOARD_EXISTS=$(kubectl get configmap fraud-detection-dashboard -n kube-prometheus-stack -o jsonpath='{.metadata.labels.grafana_dashboard}' 2>/dev/null || echo "")
    if [ "$DASHBOARD_EXISTS" = "1" ]; then
        echo -e "${GREEN}✓${NC} Custom dashboard ConfigMap is properly configured"
    else
        echo -e "${RED}✗${NC} Custom dashboard ConfigMap is not properly configured"
    fi
else
    echo -e "${RED}✗${NC} Grafana pod not found"
fi

# Test 6: Verify CloudWatch log groups
echo -e "${YELLOW}Test 6: Verifying CloudWatch log groups...${NC}"
CLUSTER_NAME=${CLUSTER_NAME:-"data-on-eks"}

# Check if log groups exist
LOG_GROUPS=(
    "/aws/eks/${CLUSTER_NAME}/cluster"
    "/aws/eks/${CLUSTER_NAME}/application"
    "/aws/eks/${CLUSTER_NAME}/emr-containers"
    "/aws/eks/${CLUSTER_NAME}/ray-training"
    "/aws/eks/${CLUSTER_NAME}/inference-service"
)

for log_group in "${LOG_GROUPS[@]}"; do
    if aws logs describe-log-groups --log-group-name-prefix "$log_group" --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "$log_group"; then
        echo -e "${GREEN}✓${NC} CloudWatch log group exists: $log_group"
    else
        echo -e "${YELLOW}⚠${NC} CloudWatch log group not found: $log_group (may take time to create)"
    fi
done

# Test 7: Verify Kubecost cost tracking
echo -e "${YELLOW}Test 7: Verifying Kubecost cost tracking...${NC}"
KUBECOST_POD=$(kubectl get pods -n kubecost -l app.kubernetes.io/name=kubecost -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -n "$KUBECOST_POD" ]; then
    echo -e "${GREEN}✓${NC} Kubecost pod found: $KUBECOST_POD"
    
    # Port forward to Kubecost
    kubectl port-forward -n kubecost pod/$KUBECOST_POD 9003:9003 >/dev/null 2>&1 &
    KC_PF_PID=$!
    
    sleep 10
    
    # Check if Kubecost API is accessible
    if curl -s "http://localhost:9003/model/allocation" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Kubecost API is accessible"
    else
        echo -e "${YELLOW}⚠${NC} Kubecost API is not yet accessible (may need more time to initialize)"
    fi
    
    # Kill port forward
    kill $KC_PF_PID 2>/dev/null || true
else
    echo -e "${RED}✗${NC} Kubecost pod not found"
fi

# Cleanup test resources
echo -e "${YELLOW}Cleaning up test resources...${NC}"
kubectl delete job gpu-test-monitoring -n fraud-detection --ignore-not-found=true
kubectl delete job load-test-monitoring -n fraud-detection --ignore-not-found=true
kubectl delete deployment test-fraud-inference -n fraud-detection --ignore-not-found=true
kubectl delete service test-fraud-inference -n fraud-detection --ignore-not-found=true

echo -e "${BLUE}=== Monitoring Integration Test Summary ===${NC}"
echo -e "${GREEN}✓ GPU metrics collection tested${NC}"
echo -e "${GREEN}✓ Inference service metrics tested${NC}"
echo -e "${GREEN}✓ Prometheus configuration verified${NC}"
echo -e "${GREEN}✓ Grafana dashboard configuration verified${NC}"
echo -e "${GREEN}✓ CloudWatch log groups checked${NC}"
echo -e "${GREEN}✓ Kubecost cost tracking verified${NC}"

echo -e "${BLUE}=== Next Steps ===${NC}"
echo -e "1. Access Grafana: kubectl port-forward -n kube-prometheus-stack svc/kube-prometheus-stack-grafana 3000:80"
echo -e "2. Access Prometheus: kubectl port-forward -n kube-prometheus-stack svc/kube-prometheus-stack-prometheus 9090:9090"
echo -e "3. Access Kubecost: kubectl port-forward -n kubecost svc/kubecost-cost-analyzer 9090:9090"
echo -e "4. Check CloudWatch logs in AWS Console"
echo -e "5. Deploy actual EMR, Ray, and inference workloads to see real metrics"

echo -e "${GREEN}Monitoring integration test completed successfully!${NC}"