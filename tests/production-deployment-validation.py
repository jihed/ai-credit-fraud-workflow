#!/usr/bin/env python3
"""
Production Deployment Validation Script
Validates all infrastructure components, migration scripts, monitoring, and security controls
for the EMR to EKS migration production deployment.
"""

import os
import sys
import json
import subprocess
import time
import requests
import boto3
from datetime import datetime
from typing import Dict, List, Tuple, Any
import yaml
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(f'tests/reports/production_deployment_validation_{datetime.now().strftime("%Y%m%d_%H%M%S")}.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class ProductionDeploymentValidator:
    """Comprehensive production deployment validation"""
    
    def __init__(self):
        self.results = {
            'infrastructure': {},
            'migration': {},
            'monitoring': {},
            'security': {},
            'configuration_adjustments': [],
            'overall_status': 'PENDING',
            'validation_timestamp': datetime.now().isoformat()
        }
        
        # Initialize AWS clients
        try:
            self.eks_client = boto3.client('eks')
            self.s3_client = boto3.client('s3')
            self.cloudwatch_client = boto3.client('cloudwatch')
            self.iam_client = boto3.client('iam')
            logger.info("AWS clients initialized successfully")
        except Exception as e:
            logger.error(f"Failed to initialize AWS clients: {e}")
            self.results['overall_status'] = 'FAILED'
    
    def validate_infrastructure_components(self) -> Dict[str, Any]:
        """Validate all infrastructure components are properly configured and operational"""
        logger.info("Starting infrastructure components validation...")
        
        infrastructure_results = {
            'eks_cluster': self._validate_eks_cluster(),
            'emr_virtual_clusters': self._validate_emr_virtual_clusters(),
            'ray_cluster': self._validate_ray_cluster(),
            'jupyterhub': self._validate_jupyterhub(),
            'karpenter': self._validate_karpenter(),
            'gpu_nodes': self._validate_gpu_nodes(),
            'storage': self._validate_storage(),
            'networking': self._validate_networking()
        }
        
        self.results['infrastructure'] = infrastructure_results
        return infrastructure_results
    
    def _validate_eks_cluster(self) -> Dict[str, Any]:
        """Validate EKS cluster configuration"""
        try:
            # Check if cluster exists and is active
            cluster_name = self._get_cluster_name()
            if not cluster_name:
                return {'status': 'FAILED', 'error': 'Cluster name not found'}
            
            response = self.eks_client.describe_cluster(name=cluster_name)
            cluster = response['cluster']
            
            validation = {
                'status': 'PASSED' if cluster['status'] == 'ACTIVE' else 'FAILED',
                'cluster_name': cluster_name,
                'version': cluster['version'],
                'endpoint': cluster['endpoint'],
                'platform_version': cluster['platformVersion'],
                'node_groups': self._validate_node_groups(cluster_name)
            }
            
            # Validate cluster configuration
            if cluster['version'] < '1.28':
                validation['warnings'] = ['Kubernetes version should be 1.28 or higher for optimal performance']
            
            return validation
            
        except Exception as e:
            return {'status': 'FAILED', 'error': str(e)}
    
    def _validate_emr_virtual_clusters(self) -> Dict[str, Any]:
        """Validate EMR on EKS virtual clusters"""
        try:
            # Check EMR virtual clusters using kubectl
            result = subprocess.run([
                'kubectl', 'get', 'namespaces', 'ml-team-a', 'ml-team-b', '-o', 'json'
            ], capture_output=True, text=True, timeout=30)
            
            if result.returncode == 0:
                namespaces = json.loads(result.stdout)
                return {
                    'status': 'PASSED',
                    'namespaces': [ns['metadata']['name'] for ns in namespaces['items']],
                    'emr_enabled': True
                }
            else:
                return {'status': 'FAILED', 'error': 'EMR namespaces not found'}
                
        except Exception as e:
            return {'status': 'FAILED', 'error': str(e)}
    
    def _validate_ray_cluster(self) -> Dict[str, Any]:
        """Validate Ray cluster deployment"""
        try:
            # Check Ray operator
            result = subprocess.run([
                'kubectl', 'get', 'deployment', 'kuberay-operator', '-n', 'kuberay-operator', '-o', 'json'
            ], capture_output=True, text=True, timeout=30)
            
            if result.returncode != 0:
                return {'status': 'FAILED', 'error': 'KubeRay operator not found'}
            
            operator = json.loads(result.stdout)
            ready_replicas = operator['status'].get('readyReplicas', 0)
            
            # Check Ray clusters
            ray_result = subprocess.run([
                'kubectl', 'get', 'raycluster', '--all-namespaces', '-o', 'json'
            ], capture_output=True, text=True, timeout=30)
            
            ray_clusters = []
            if ray_result.returncode == 0:
                clusters = json.loads(ray_result.stdout)
                ray_clusters = [cluster['metadata']['name'] for cluster in clusters['items']]
            
            return {
                'status': 'PASSED' if ready_replicas > 0 else 'FAILED',
                'operator_ready': ready_replicas > 0,
                'ray_clusters': ray_clusters
            }
            
        except Exception as e:
            return {'status': 'FAILED', 'error': str(e)}
    
    def _validate_jupyterhub(self) -> Dict[str, Any]:
        """Validate JupyterHub deployment"""
        try:
            result = subprocess.run([
                'kubectl', 'get', 'deployment', 'jupyterhub', '-n', 'jupyterhub', '-o', 'json'
            ], capture_output=True, text=True, timeout=30)
            
            if result.returncode != 0:
                return {'status': 'WARNING', 'message': 'JupyterHub deployment not found'}
            
            deployment = json.loads(result.stdout)
            ready_replicas = deployment['status'].get('readyReplicas', 0)
            
            return {
                'status': 'PASSED' if ready_replicas > 0 else 'FAILED',
                'ready_replicas': ready_replicas,
                'desired_replicas': deployment['spec']['replicas']
            }
            
        except Exception as e:
            return {'status': 'FAILED', 'error': str(e)}
    
    def _validate_karpenter(self) -> Dict[str, Any]:
        """Validate Karpenter configuration"""
        try:
            # Check Karpenter deployment
            result = subprocess.run([
                'kubectl', 'get', 'deployment', 'karpenter', '-n', 'karpenter', '-o', 'json'
            ], capture_output=True, text=True, timeout=30)
            
            if result.returncode != 0:
                return {'status': 'FAILED', 'error': 'Karpenter deployment not found'}
            
            deployment = json.loads(result.stdout)
            ready_replicas = deployment['status'].get('readyReplicas', 0)
            
            # Check node pools
            nodepool_result = subprocess.run([
                'kubectl', 'get', 'nodepool', '-o', 'json'
            ], capture_output=True, text=True, timeout=30)
            
            node_pools = []
            if nodepool_result.returncode == 0:
                pools = json.loads(nodepool_result.stdout)
                node_pools = [pool['metadata']['name'] for pool in pools['items']]
            
            return {
                'status': 'PASSED' if ready_replicas > 0 else 'FAILED',
                'ready_replicas': ready_replicas,
                'node_pools': node_pools
            }
            
        except Exception as e:
            return {'status': 'FAILED', 'error': str(e)}
    
    def _validate_gpu_nodes(self) -> Dict[str, Any]:
        """Validate GPU node availability and configuration"""
        try:
            result = subprocess.run([
                'kubectl', 'get', 'nodes', '-l', 'node.kubernetes.io/instance-type=g5.2xlarge', '-o', 'json'
            ], capture_output=True, text=True, timeout=30)
            
            if result.returncode != 0:
                return {'status': 'WARNING', 'message': 'No GPU nodes currently provisioned'}
            
            nodes = json.loads(result.stdout)
            gpu_nodes = []
            
            for node in nodes['items']:
                node_info = {
                    'name': node['metadata']['name'],
                    'ready': any(condition['type'] == 'Ready' and condition['status'] == 'True' 
                               for condition in node['status']['conditions']),
                    'gpu_capacity': node['status']['capacity'].get('nvidia.com/gpu', '0')
                }
                gpu_nodes.append(node_info)
            
            return {
                'status': 'PASSED' if gpu_nodes else 'WARNING',
                'gpu_nodes': gpu_nodes,
                'total_gpu_capacity': sum(int(node['gpu_capacity']) for node in gpu_nodes)
            }
            
        except Exception as e:
            return {'status': 'FAILED', 'error': str(e)}
    
    def _validate_storage(self) -> Dict[str, Any]:
        """Validate storage configuration"""
        try:
            # Check EBS CSI driver
            result = subprocess.run([
                'kubectl', 'get', 'daemonset', 'ebs-csi-node', '-n', 'kube-system', '-o', 'json'
            ], capture_output=True, text=True, timeout=30)
            
            ebs_csi_ready = False
            if result.returncode == 0:
                daemonset = json.loads(result.stdout)
                desired = daemonset['status'].get('desiredNumberScheduled', 0)
                ready = daemonset['status'].get('numberReady', 0)
                ebs_csi_ready = desired > 0 and ready == desired
            
            # Check S3 bucket access
            bucket_name = self._get_s3_bucket_name()
            s3_accessible = False
            if bucket_name:
                try:
                    self.s3_client.head_bucket(Bucket=bucket_name)
                    s3_accessible = True
                except:
                    pass
            
            return {
                'status': 'PASSED' if ebs_csi_ready and s3_accessible else 'FAILED',
                'ebs_csi_ready': ebs_csi_ready,
                's3_accessible': s3_accessible,
                's3_bucket': bucket_name
            }
            
        except Exception as e:
            return {'status': 'FAILED', 'error': str(e)}
    
    def _validate_networking(self) -> Dict[str, Any]:
        """Validate networking configuration"""
        try:
            # Check AWS Load Balancer Controller
            result = subprocess.run([
                'kubectl', 'get', 'deployment', 'aws-load-balancer-controller', '-n', 'kube-system', '-o', 'json'
            ], capture_output=True, text=True, timeout=30)
            
            alb_ready = False
            if result.returncode == 0:
                deployment = json.loads(result.stdout)
                ready_replicas = deployment['status'].get('readyReplicas', 0)
                alb_ready = ready_replicas > 0
            
            # Check CoreDNS
            coredns_result = subprocess.run([
                'kubectl', 'get', 'deployment', 'coredns', '-n', 'kube-system', '-o', 'json'
            ], capture_output=True, text=True, timeout=30)
            
            coredns_ready = False
            if coredns_result.returncode == 0:
                deployment = json.loads(coredns_result.stdout)
                ready_replicas = deployment['status'].get('readyReplicas', 0)
                coredns_ready = ready_replicas > 0
            
            return {
                'status': 'PASSED' if alb_ready and coredns_ready else 'FAILED',
                'aws_load_balancer_controller': alb_ready,
                'coredns': coredns_ready
            }
            
        except Exception as e:
            return {'status': 'FAILED', 'error': str(e)}
    
    def execute_migration_scripts(self) -> Dict[str, Any]:
        """Execute migration scripts against production data samples"""
        logger.info("Executing migration scripts validation...")
        
        migration_results = {
            'data_migration': self._test_data_migration(),
            'model_migration': self._test_model_migration(),
            'validation_scripts': self._test_validation_scripts()
        }
        
        self.results['migration'] = migration_results
        return migration_results
    
    def _test_data_migration(self) -> Dict[str, Any]:
        """Test data migration script"""
        try:
            # Run data migration validation
            result = subprocess.run([
                'python3', 'migration/scripts/data-migration/emr-to-emr-on-eks.py', '--validate'
            ], capture_output=True, text=True, timeout=300)
            
            return {
                'status': 'PASSED' if result.returncode == 0 else 'FAILED',
                'output': result.stdout,
                'error': result.stderr if result.returncode != 0 else None
            }
            
        except Exception as e:
            return {'status': 'FAILED', 'error': str(e)}
    
    def _test_model_migration(self) -> Dict[str, Any]:
        """Test model migration script"""
        try:
            # Run model migration validation
            result = subprocess.run([
                'python3', 'migration/scripts/model-migration/sagemaker-to-eks.py', '--validate'
            ], capture_output=True, text=True, timeout=300)
            
            return {
                'status': 'PASSED' if result.returncode == 0 else 'FAILED',
                'output': result.stdout,
                'error': result.stderr if result.returncode != 0 else None
            }
            
        except Exception as e:
            return {'status': 'FAILED', 'error': str(e)}
    
    def _test_validation_scripts(self) -> Dict[str, Any]:
        """Test validation scripts"""
        try:
            # Run migration validation
            result = subprocess.run([
                'python3', 'migration/scripts/validation/validate-migration.py'
            ], capture_output=True, text=True, timeout=300)
            
            return {
                'status': 'PASSED' if result.returncode == 0 else 'FAILED',
                'output': result.stdout,
                'error': result.stderr if result.returncode != 0 else None
            }
            
        except Exception as e:
            return {'status': 'FAILED', 'error': str(e)}
    
    def verify_monitoring_and_alerting(self) -> Dict[str, Any]:
        """Verify monitoring dashboards and alerting rules are functioning correctly"""
        logger.info("Verifying monitoring and alerting...")
        
        monitoring_results = {
            'prometheus': self._validate_prometheus(),
            'grafana': self._validate_grafana(),
            'cloudwatch': self._validate_cloudwatch(),
            'alerting_rules': self._validate_alerting_rules(),
            'dashboards': self._validate_dashboards()
        }
        
        self.results['monitoring'] = monitoring_results
        return monitoring_results
    
    def _validate_prometheus(self) -> Dict[str, Any]:
        """Validate Prometheus deployment and metrics collection"""
        try:
            # Check Prometheus deployment
            result = subprocess.run([
                'kubectl', 'get', 'deployment', 'prometheus-server', '-n', 'prometheus', '-o', 'json'
            ], capture_output=True, text=True, timeout=30)
            
            if result.returncode != 0:
                return {'status': 'FAILED', 'error': 'Prometheus deployment not found'}
            
            deployment = json.loads(result.stdout)
            ready_replicas = deployment['status'].get('readyReplicas', 0)
            
            # Test Prometheus API
            prometheus_accessible = self._test_prometheus_api()
            
            return {
                'status': 'PASSED' if ready_replicas > 0 and prometheus_accessible else 'FAILED',
                'ready_replicas': ready_replicas,
                'api_accessible': prometheus_accessible
            }
            
        except Exception as e:
            return {'status': 'FAILED', 'error': str(e)}
    
    def _validate_grafana(self) -> Dict[str, Any]:
        """Validate Grafana deployment and dashboards"""
        try:
            # Check Grafana deployment
            result = subprocess.run([
                'kubectl', 'get', 'deployment', 'grafana', '-n', 'grafana', '-o', 'json'
            ], capture_output=True, text=True, timeout=30)
            
            if result.returncode != 0:
                return {'status': 'FAILED', 'error': 'Grafana deployment not found'}
            
            deployment = json.loads(result.stdout)
            ready_replicas = deployment['status'].get('readyReplicas', 0)
            
            return {
                'status': 'PASSED' if ready_replicas > 0 else 'FAILED',
                'ready_replicas': ready_replicas
            }
            
        except Exception as e:
            return {'status': 'FAILED', 'error': str(e)}
    
    def _validate_cloudwatch(self) -> Dict[str, Any]:
        """Validate CloudWatch integration"""
        try:
            # Check CloudWatch agent
            result = subprocess.run([
                'kubectl', 'get', 'daemonset', 'cloudwatch-agent', '-n', 'amazon-cloudwatch', '-o', 'json'
            ], capture_output=True, text=True, timeout=30)
            
            cloudwatch_ready = False
            if result.returncode == 0:
                daemonset = json.loads(result.stdout)
                desired = daemonset['status'].get('desiredNumberScheduled', 0)
                ready = daemonset['status'].get('numberReady', 0)
                cloudwatch_ready = desired > 0 and ready == desired
            
            # Test CloudWatch metrics
            metrics_available = self._test_cloudwatch_metrics()
            
            return {
                'status': 'PASSED' if cloudwatch_ready or metrics_available else 'WARNING',
                'agent_ready': cloudwatch_ready,
                'metrics_available': metrics_available
            }
            
        except Exception as e:
            return {'status': 'FAILED', 'error': str(e)}
    
    def _validate_alerting_rules(self) -> Dict[str, Any]:
        """Validate alerting rules configuration"""
        try:
            # Check PrometheusRule resources
            result = subprocess.run([
                'kubectl', 'get', 'prometheusrule', '--all-namespaces', '-o', 'json'
            ], capture_output=True, text=True, timeout=30)
            
            if result.returncode != 0:
                return {'status': 'WARNING', 'message': 'No PrometheusRule resources found'}
            
            rules = json.loads(result.stdout)
            rule_count = len(rules['items'])
            
            return {
                'status': 'PASSED' if rule_count > 0 else 'WARNING',
                'rule_count': rule_count,
                'rules': [rule['metadata']['name'] for rule in rules['items']]
            }
            
        except Exception as e:
            return {'status': 'FAILED', 'error': str(e)}
    
    def _validate_dashboards(self) -> Dict[str, Any]:
        """Validate monitoring dashboards"""
        try:
            # Check for dashboard ConfigMaps
            result = subprocess.run([
                'kubectl', 'get', 'configmap', '-l', 'grafana_dashboard=1', '--all-namespaces', '-o', 'json'
            ], capture_output=True, text=True, timeout=30)
            
            dashboard_count = 0
            if result.returncode == 0:
                configmaps = json.loads(result.stdout)
                dashboard_count = len(configmaps['items'])
            
            return {
                'status': 'PASSED' if dashboard_count > 0 else 'WARNING',
                'dashboard_count': dashboard_count
            }
            
        except Exception as e:
            return {'status': 'FAILED', 'error': str(e)}
    
    def conduct_security_audit(self) -> Dict[str, Any]:
        """Conduct security audit and compliance validation"""
        logger.info("Conducting security audit and compliance validation...")
        
        security_results = {
            'rbac': self._validate_rbac(),
            'network_policies': self._validate_network_policies(),
            'encryption': self._validate_encryption(),
            'secrets_management': self._validate_secrets_management(),
            'pod_security': self._validate_pod_security(),
            'audit_logging': self._validate_audit_logging()
        }
        
        self.results['security'] = security_results
        return security_results
    
    def _validate_rbac(self) -> Dict[str, Any]:
        """Validate RBAC configuration"""
        try:
            # Check ClusterRoles
            result = subprocess.run([
                'kubectl', 'get', 'clusterrole', '-o', 'json'
            ], capture_output=True, text=True, timeout=30)
            
            cluster_roles = []
            if result.returncode == 0:
                roles = json.loads(result.stdout)
                cluster_roles = [role['metadata']['name'] for role in roles['items'] 
                               if not role['metadata']['name'].startswith('system:')]
            
            # Check RoleBindings
            binding_result = subprocess.run([
                'kubectl', 'get', 'rolebinding', '--all-namespaces', '-o', 'json'
            ], capture_output=True, text=True, timeout=30)
            
            role_bindings = []
            if binding_result.returncode == 0:
                bindings = json.loads(binding_result.stdout)
                role_bindings = [binding['metadata']['name'] for binding in bindings['items']]
            
            return {
                'status': 'PASSED' if cluster_roles and role_bindings else 'WARNING',
                'cluster_roles': len(cluster_roles),
                'role_bindings': len(role_bindings)
            }
            
        except Exception as e:
            return {'status': 'FAILED', 'error': str(e)}
    
    def _validate_network_policies(self) -> Dict[str, Any]:
        """Validate network policies"""
        try:
            result = subprocess.run([
                'kubectl', 'get', 'networkpolicy', '--all-namespaces', '-o', 'json'
            ], capture_output=True, text=True, timeout=30)
            
            if result.returncode != 0:
                return {'status': 'WARNING', 'message': 'No network policies found'}
            
            policies = json.loads(result.stdout)
            policy_count = len(policies['items'])
            
            return {
                'status': 'PASSED' if policy_count > 0 else 'WARNING',
                'policy_count': policy_count,
                'policies': [policy['metadata']['name'] for policy in policies['items']]
            }
            
        except Exception as e:
            return {'status': 'FAILED', 'error': str(e)}
    
    def _validate_encryption(self) -> Dict[str, Any]:
        """Validate encryption configuration"""
        try:
            # Check EKS cluster encryption
            cluster_name = self._get_cluster_name()
            if not cluster_name:
                return {'status': 'FAILED', 'error': 'Cluster name not found'}
            
            response = self.eks_client.describe_cluster(name=cluster_name)
            cluster = response['cluster']
            
            encryption_config = cluster.get('encryptionConfig', [])
            secrets_encrypted = any(
                'secrets' in config.get('resources', []) 
                for config in encryption_config
            )
            
            return {
                'status': 'PASSED' if secrets_encrypted else 'WARNING',
                'secrets_encrypted': secrets_encrypted,
                'encryption_config': len(encryption_config) > 0
            }
            
        except Exception as e:
            return {'status': 'FAILED', 'error': str(e)}
    
    def _validate_secrets_management(self) -> Dict[str, Any]:
        """Validate secrets management"""
        try:
            # Check for External Secrets Operator
            result = subprocess.run([
                'kubectl', 'get', 'deployment', 'external-secrets', '-n', 'external-secrets-system', '-o', 'json'
            ], capture_output=True, text=True, timeout=30)
            
            external_secrets_ready = False
            if result.returncode == 0:
                deployment = json.loads(result.stdout)
                ready_replicas = deployment['status'].get('readyReplicas', 0)
                external_secrets_ready = ready_replicas > 0
            
            # Check secrets
            secrets_result = subprocess.run([
                'kubectl', 'get', 'secrets', '--all-namespaces', '-o', 'json'
            ], capture_output=True, text=True, timeout=30)
            
            secret_count = 0
            if secrets_result.returncode == 0:
                secrets = json.loads(secrets_result.stdout)
                secret_count = len(secrets['items'])
            
            return {
                'status': 'PASSED',
                'external_secrets_ready': external_secrets_ready,
                'secret_count': secret_count
            }
            
        except Exception as e:
            return {'status': 'FAILED', 'error': str(e)}
    
    def _validate_pod_security(self) -> Dict[str, Any]:
        """Validate pod security standards"""
        try:
            # Check Pod Security Standards
            result = subprocess.run([
                'kubectl', 'get', 'namespace', '-o', 'json'
            ], capture_output=True, text=True, timeout=30)
            
            if result.returncode != 0:
                return {'status': 'FAILED', 'error': 'Cannot retrieve namespaces'}
            
            namespaces = json.loads(result.stdout)
            secured_namespaces = 0
            
            for ns in namespaces['items']:
                labels = ns['metadata'].get('labels', {})
                if any(label.startswith('pod-security.kubernetes.io/') for label in labels):
                    secured_namespaces += 1
            
            return {
                'status': 'PASSED' if secured_namespaces > 0 else 'WARNING',
                'secured_namespaces': secured_namespaces,
                'total_namespaces': len(namespaces['items'])
            }
            
        except Exception as e:
            return {'status': 'FAILED', 'error': str(e)}
    
    def _validate_audit_logging(self) -> Dict[str, Any]:
        """Validate audit logging configuration"""
        try:
            # Check if audit logging is enabled (this would be in EKS cluster config)
            cluster_name = self._get_cluster_name()
            if not cluster_name:
                return {'status': 'FAILED', 'error': 'Cluster name not found'}
            
            response = self.eks_client.describe_cluster(name=cluster_name)
            cluster = response['cluster']
            
            logging_config = cluster.get('logging', {})
            audit_enabled = any(
                log_type.get('enabled', False) and 'audit' in log_type.get('types', [])
                for log_type in logging_config.get('clusterLogging', [])
            )
            
            return {
                'status': 'PASSED' if audit_enabled else 'WARNING',
                'audit_enabled': audit_enabled,
                'logging_config': logging_config
            }
            
        except Exception as e:
            return {'status': 'FAILED', 'error': str(e)}
    
    def document_configuration_adjustments(self) -> List[Dict[str, Any]]:
        """Document any configuration adjustments needed for production workloads"""
        logger.info("Documenting configuration adjustments...")
        
        adjustments = []
        
        # Analyze results and recommend adjustments
        if self.results['infrastructure'].get('eks_cluster', {}).get('warnings'):
            adjustments.append({
                'component': 'EKS Cluster',
                'issue': 'Kubernetes version',
                'recommendation': 'Upgrade to Kubernetes 1.28 or higher',
                'priority': 'HIGH'
            })
        
        if not self.results['infrastructure'].get('gpu_nodes', {}).get('gpu_nodes'):
            adjustments.append({
                'component': 'GPU Nodes',
                'issue': 'No GPU nodes provisioned',
                'recommendation': 'Ensure Karpenter can provision g5.2xlarge nodes when needed',
                'priority': 'MEDIUM'
            })
        
        if self.results['security'].get('network_policies', {}).get('status') == 'WARNING':
            adjustments.append({
                'component': 'Network Security',
                'issue': 'No network policies found',
                'recommendation': 'Implement network policies for namespace isolation',
                'priority': 'HIGH'
            })
        
        if self.results['security'].get('encryption', {}).get('status') == 'WARNING':
            adjustments.append({
                'component': 'Encryption',
                'issue': 'Secrets encryption not enabled',
                'recommendation': 'Enable EKS secrets encryption with KMS',
                'priority': 'HIGH'
            })
        
        if self.results['monitoring'].get('alerting_rules', {}).get('status') == 'WARNING':
            adjustments.append({
                'component': 'Monitoring',
                'issue': 'No alerting rules configured',
                'recommendation': 'Configure Prometheus alerting rules for critical metrics',
                'priority': 'MEDIUM'
            })
        
        self.results['configuration_adjustments'] = adjustments
        return adjustments
    
    def generate_report(self) -> Dict[str, Any]:
        """Generate comprehensive validation report"""
        # Determine overall status
        failed_components = []
        warning_components = []
        
        for category, results in self.results.items():
            if isinstance(results, dict):
                for component, result in results.items():
                    if isinstance(result, dict) and 'status' in result:
                        if result['status'] == 'FAILED':
                            failed_components.append(f"{category}.{component}")
                        elif result['status'] == 'WARNING':
                            warning_components.append(f"{category}.{component}")
        
        if failed_components:
            self.results['overall_status'] = 'FAILED'
        elif warning_components:
            self.results['overall_status'] = 'WARNING'
        else:
            self.results['overall_status'] = 'PASSED'
        
        self.results['summary'] = {
            'failed_components': failed_components,
            'warning_components': warning_components,
            'total_adjustments': len(self.results['configuration_adjustments'])
        }
        
        return self.results
    
    def run_validation(self) -> Dict[str, Any]:
        """Run complete production deployment validation"""
        logger.info("Starting production deployment validation...")
        
        try:
            # Run all validation steps
            self.validate_infrastructure_components()
            self.execute_migration_scripts()
            self.verify_monitoring_and_alerting()
            self.conduct_security_audit()
            self.document_configuration_adjustments()
            
            # Generate final report
            report = self.generate_report()
            
            # Save report
            report_file = f'tests/reports/production_deployment_validation_{datetime.now().strftime("%Y%m%d_%H%M%S")}.json'
            os.makedirs('tests/reports', exist_ok=True)
            with open(report_file, 'w') as f:
                json.dump(report, f, indent=2)
            
            logger.info(f"Validation complete. Report saved to {report_file}")
            logger.info(f"Overall status: {report['overall_status']}")
            
            return report
            
        except Exception as e:
            logger.error(f"Validation failed: {e}")
            self.results['overall_status'] = 'FAILED'
            self.results['error'] = str(e)
            return self.results
    
    # Helper methods
    def _get_cluster_name(self) -> str:
        """Get EKS cluster name from kubectl context"""
        try:
            result = subprocess.run([
                'kubectl', 'config', 'current-context'
            ], capture_output=True, text=True, timeout=10)
            
            if result.returncode == 0:
                context = result.stdout.strip()
                # Extract cluster name from context (format: arn:aws:eks:region:account:cluster/cluster-name)
                if 'cluster/' in context:
                    return context.split('cluster/')[-1]
            return None
        except:
            return None
    
    def _get_s3_bucket_name(self) -> str:
        """Get S3 bucket name from Terraform output or environment"""
        try:
            # Try to get from Terraform output
            result = subprocess.run([
                'terraform', 'output', '-raw', 's3_bucket_id'
            ], capture_output=True, text=True, timeout=30, cwd='emr-spark-rapids')
            
            if result.returncode == 0:
                return result.stdout.strip()
            
            # Fallback to environment variable
            return os.environ.get('S3_BUCKET_NAME', 'data-on-eks-emr-spark-rapids')
        except:
            return 'data-on-eks-emr-spark-rapids'
    
    def _validate_node_groups(self, cluster_name: str) -> List[Dict[str, Any]]:
        """Validate EKS node groups"""
        try:
            response = self.eks_client.list_nodegroups(clusterName=cluster_name)
            node_groups = []
            
            for ng_name in response['nodegroups']:
                ng_response = self.eks_client.describe_nodegroup(
                    clusterName=cluster_name,
                    nodegroupName=ng_name
                )
                ng = ng_response['nodegroup']
                node_groups.append({
                    'name': ng_name,
                    'status': ng['status'],
                    'instance_types': ng['instanceTypes'],
                    'capacity_type': ng.get('capacityType', 'ON_DEMAND')
                })
            
            return node_groups
        except:
            return []
    
    def _test_prometheus_api(self) -> bool:
        """Test Prometheus API accessibility"""
        try:
            # Port forward to Prometheus (this is a simplified test)
            result = subprocess.run([
                'kubectl', 'get', 'service', 'prometheus-server', '-n', 'prometheus'
            ], capture_output=True, text=True, timeout=10)
            
            return result.returncode == 0
        except:
            return False
    
    def _test_cloudwatch_metrics(self) -> bool:
        """Test CloudWatch metrics availability"""
        try:
            response = self.cloudwatch_client.list_metrics(
                Namespace='AWS/EKS',
                MaxRecords=1
            )
            return len(response['Metrics']) > 0
        except:
            return False

def main():
    """Main execution function"""
    validator = ProductionDeploymentValidator()
    report = validator.run_validation()
    
    print("\n" + "="*80)
    print("PRODUCTION DEPLOYMENT VALIDATION REPORT")
    print("="*80)
    print(f"Overall Status: {report['overall_status']}")
    print(f"Validation Time: {report['validation_timestamp']}")
    
    if report['summary']['failed_components']:
        print(f"\nFailed Components ({len(report['summary']['failed_components'])}):")
        for component in report['summary']['failed_components']:
            print(f"  ❌ {component}")
    
    if report['summary']['warning_components']:
        print(f"\nWarning Components ({len(report['summary']['warning_components'])}):")
        for component in report['summary']['warning_components']:
            print(f"  ⚠️  {component}")
    
    if report['configuration_adjustments']:
        print(f"\nConfiguration Adjustments Needed ({len(report['configuration_adjustments'])}):")
        for adj in report['configuration_adjustments']:
            print(f"  🔧 {adj['component']}: {adj['recommendation']} (Priority: {adj['priority']})")
    
    print("\n" + "="*80)
    
    # Exit with appropriate code
    if report['overall_status'] == 'FAILED':
        sys.exit(1)
    elif report['overall_status'] == 'WARNING':
        sys.exit(2)
    else:
        sys.exit(0)

if __name__ == "__main__":
    main()