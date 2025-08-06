# Fraud Detection Application Deployment with Helm

This directory contains Helm charts and values for deploying the fraud detection application stack on the EKS cluster.

## Prerequisites

1. EKS cluster deployed via Terraform (see `../terraform/`)
2. kubectl configured to access the cluster
3. Helm 3.x installed

## Application Stack

The fraud detection demo uses the following applications:

- **JupyterHub**: Interactive notebook environment for data scientists
- **Ray Cluster**: Distributed computing for ML training and inference
- **Airflow** (optional): Workflow orchestration
- **Kafka** (optional): Real-time data streaming

## Quick Start

1. **Add Helm repositories**:
   ```bash
   ./scripts/add-helm-repos.sh
   ```

2. **Deploy core applications**:
   ```bash
   # Deploy JupyterHub
   helm install jupyterhub jupyterhub/jupyterhub \
     --namespace jupyterhub \
     --create-namespace \
     --values values/jupyterhub-values.yaml

   # Deploy Ray cluster
   helm install ray-cluster kuberay/ray-cluster \
     --namespace ray-system \
     --create-namespace \
     --values values/ray-values.yaml
   ```

3. **Verify deployments**:
   ```bash
   kubectl get pods -n jupyterhub
   kubectl get pods -n ray-system
   ```

## Individual Application Deployment

### JupyterHub

```bash
helm install jupyterhub jupyterhub/jupyterhub \
  --namespace jupyterhub \
  --create-namespace \
  --values values/jupyterhub-values.yaml \
  --version 3.2.1
```

### Ray Cluster

```bash
helm install ray-cluster kuberay/ray-cluster \
  --namespace ray-system \
  --create-namespace \
  --values values/ray-values.yaml \
  --version 1.2.2
```

### Airflow (Optional)

```bash
helm install airflow apache-airflow/airflow \
  --namespace airflow \
  --create-namespace \
  --values values/airflow-values.yaml \
  --version 1.15.0
```

## Configuration

Each application has its own values file in the `values/` directory:

- `jupyterhub-values.yaml`: JupyterHub configuration with fraud detection profiles
- `ray-values.yaml`: Ray cluster configuration for ML workloads
- `airflow-values.yaml`: Airflow configuration for workflow orchestration

## Accessing Applications

After deployment, access applications via:

1. **JupyterHub**: Get the LoadBalancer URL
   ```bash
   kubectl get svc -n jupyterhub
   ```

2. **Ray Dashboard**: Port-forward to access locally
   ```bash
   kubectl port-forward -n ray-system svc/ray-cluster-head-svc 8265:8265
   ```

## Cleanup

```bash
# Remove all applications
helm uninstall jupyterhub -n jupyterhub
helm uninstall ray-cluster -n ray-system
helm uninstall airflow -n airflow

# Remove namespaces
kubectl delete namespace jupyterhub ray-system airflow
```