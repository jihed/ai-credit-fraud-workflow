#!/bin/bash

# Add Helm repositories for fraud detection applications
set -e

echo "Adding Helm repositories..."

# JupyterHub
helm repo add jupyterhub https://hub.jupyter.org/helm-chart/
echo "✓ Added JupyterHub repository"

# KubeRay (Ray cluster)
helm repo add kuberay https://ray-project.github.io/kuberay-helm/
echo "✓ Added KubeRay repository"

# Apache Airflow
helm repo add apache-airflow https://airflow.apache.org
echo "✓ Added Apache Airflow repository"

# Strimzi (Kafka)
helm repo add strimzi https://strimzi.io/charts/
echo "✓ Added Strimzi repository"

# Update repositories
echo "Updating Helm repositories..."
helm repo update

echo "✅ All Helm repositories added and updated successfully!"

# List available charts
echo ""
echo "Available charts:"
echo "- JupyterHub: helm search repo jupyterhub/jupyterhub"
echo "- Ray Cluster: helm search repo kuberay/ray-cluster"
echo "- Airflow: helm search repo apache-airflow/airflow"
echo "- Kafka: helm search repo strimzi/strimzi-kafka-operator"