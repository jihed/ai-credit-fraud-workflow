# Security and Compliance Controls

This directory contains security configurations for the EMR to EKS migration, implementing comprehensive security controls including RBAC, mTLS, encryption, and audit logging.

## Components

### RBAC (Role-Based Access Control)
- Service account configurations for all components
- Role and ClusterRole definitions with least privilege
- RoleBindings and ClusterRoleBindings for proper access control

### Mutual TLS (mTLS)
- Certificate management using cert-manager
- Service mesh configuration with Istio
- TLS policies for service-to-service communication

### Data Encryption
- Encryption in transit using TLS
- Encryption at rest for S3 and EBS volumes
- Kubernetes secrets encryption

### Audit Logging
- Kubernetes audit logging configuration
- Application-level audit logs
- CloudWatch integration for centralized logging

## Deployment

Deploy security controls using:
```bash
kubectl apply -f rbac/
kubectl apply -f mtls/
kubectl apply -f encryption/
kubectl apply -f audit/
```

## Compliance

These configurations help meet financial services compliance requirements including:
- SOC 2 Type II
- PCI DSS
- GDPR data protection
- AWS Security Best Practices