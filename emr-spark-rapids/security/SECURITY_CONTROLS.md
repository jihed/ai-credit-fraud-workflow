# Security and Compliance Controls Documentation

## Overview

This document provides comprehensive documentation for the security and compliance controls implemented for the EMR to EKS migration project. These controls ensure data protection, access control, audit logging, and compliance with financial services regulations.

## Security Architecture

### Defense in Depth Strategy

The security implementation follows a defense-in-depth approach with multiple layers:

1. **Network Security**: Network policies, VPC isolation, security groups
2. **Identity and Access Management**: RBAC, service accounts, IRSA
3. **Data Protection**: Encryption in transit and at rest
4. **Monitoring and Auditing**: Comprehensive logging and monitoring
5. **Compliance**: Pod security standards and security policies

## Implemented Controls

### 1. Role-Based Access Control (RBAC)

#### Service Accounts
- **EMR Spark Driver/Executor**: Separate service accounts for driver and executor pods
- **Ray Head/Worker**: Dedicated service accounts for Ray cluster components
- **Fraud Detection Processor**: Service account for data processing workloads
- **Inference Service**: Service account for model serving
- **Monitoring**: Service account for Prometheus and monitoring components

#### Roles and Permissions
- **Principle of Least Privilege**: Each service account has minimal required permissions
- **Namespace Isolation**: Roles scoped to specific namespaces where possible
- **Resource-Specific Access**: Granular permissions for specific Kubernetes resources

#### IRSA Integration
All service accounts are configured with IAM Roles for Service Accounts (IRSA) for secure AWS API access without storing credentials.

### 2. Network Security

#### Network Policies
- **Default Deny**: All namespaces have default deny ingress policies
- **Selective Allow**: Specific policies allow required communication patterns
- **Cross-Namespace Communication**: Controlled communication between services
- **Monitoring Access**: Prometheus can access metrics endpoints

#### Namespace Isolation
- **ml-team-a/ml-team-b**: Isolated EMR on EKS environments
- **ray-system**: Ray cluster isolation
- **fraud-detection**: Data processing isolation
- **inference**: Model serving isolation

### 3. Mutual TLS (mTLS)

#### Certificate Management
- **cert-manager**: Automated certificate lifecycle management
- **Internal CA**: Self-signed root CA for internal communications
- **Service Certificates**: Individual certificates for each service
- **Automatic Renewal**: Certificates automatically renewed before expiration

#### Istio Integration
- **Strict mTLS**: All service-to-service communication encrypted
- **Authorization Policies**: Fine-grained access control between services
- **Traffic Encryption**: All inter-service traffic automatically encrypted

### 4. Data Encryption

#### Encryption at Rest
- **S3 Buckets**: KMS encryption for all data storage
- **EBS Volumes**: Encrypted EBS volumes for all node storage
- **Kubernetes Secrets**: Envelope encryption using AWS KMS

#### Encryption in Transit
- **TLS 1.2+**: All external communications use TLS 1.2 or higher
- **mTLS**: Internal service communications use mutual TLS
- **HTTPS**: All web interfaces and APIs use HTTPS

#### Key Management
- **AWS KMS**: Centralized key management
- **Key Rotation**: Automatic key rotation enabled
- **Access Control**: IAM policies control key access

### 5. Audit Logging

#### Kubernetes Audit Logging
- **API Server Auditing**: All API server requests logged
- **Resource Changes**: All resource modifications tracked
- **Authentication Events**: All authentication attempts logged
- **Authorization Decisions**: All access control decisions recorded

#### Application Audit Logging
- **Fluent Bit**: Centralized log collection
- **CloudWatch Integration**: Logs forwarded to CloudWatch
- **Structured Logging**: JSON-formatted logs for analysis
- **Retention Policies**: Configurable log retention

#### Monitored Events
- Data access operations
- Model training job submissions
- Inference requests
- Configuration changes
- Security policy violations

### 6. Compliance Controls

#### Pod Security Standards
- **Restricted Profile**: Applied to most workload namespaces
- **Baseline Profile**: Applied to Ray system (due to requirements)
- **Security Context**: Non-root containers, dropped capabilities
- **Resource Limits**: CPU and memory limits enforced

#### Security Policies
- **No Privileged Containers**: Privileged containers prohibited
- **Read-Only Root Filesystem**: Where possible, root filesystem is read-only
- **Security Context Constraints**: Additional security constraints applied
- **Image Security**: Container image scanning and policies

## Compliance Mappings

### SOC 2 Type II
- **CC6.1**: Logical access controls implemented through RBAC
- **CC6.2**: Authentication mechanisms via service accounts and IRSA
- **CC6.3**: Authorization controls through Kubernetes RBAC and Istio policies
- **CC6.6**: Audit logging for all system activities
- **CC6.7**: Data transmission security via mTLS and TLS

### PCI DSS
- **Requirement 2**: Secure configurations and hardened systems
- **Requirement 3**: Data encryption at rest and in transit
- **Requirement 4**: Encryption of cardholder data transmission
- **Requirement 7**: Access control based on business need-to-know
- **Requirement 8**: Unique user identification and authentication
- **Requirement 10**: Audit logging and monitoring

### GDPR
- **Article 25**: Data protection by design and by default
- **Article 32**: Security of processing through encryption and access controls
- **Article 33**: Breach notification through monitoring and alerting
- **Article 35**: Data protection impact assessment documentation

## Security Monitoring

### Metrics and Alerting
- **Failed Authentication Attempts**: Monitor and alert on authentication failures
- **Privilege Escalation**: Detect attempts to gain elevated privileges
- **Network Policy Violations**: Monitor blocked network connections
- **Certificate Expiration**: Alert on upcoming certificate expirations
- **Audit Log Anomalies**: Detect unusual patterns in audit logs

### Security Dashboards
- **Access Control Dashboard**: RBAC and authentication metrics
- **Network Security Dashboard**: Network policy and traffic analysis
- **Encryption Status Dashboard**: Certificate and encryption status
- **Compliance Dashboard**: Security policy compliance metrics

## Incident Response

### Security Event Categories
1. **Authentication Failures**: Failed login attempts, invalid tokens
2. **Authorization Violations**: Unauthorized access attempts
3. **Network Security**: Policy violations, suspicious traffic
4. **Data Access**: Unauthorized data access attempts
5. **Configuration Changes**: Unauthorized security configuration changes

### Response Procedures
1. **Detection**: Automated monitoring and alerting
2. **Assessment**: Evaluate severity and impact
3. **Containment**: Isolate affected systems
4. **Investigation**: Analyze logs and determine root cause
5. **Recovery**: Restore normal operations
6. **Documentation**: Record incident details and lessons learned

## Maintenance and Updates

### Regular Security Tasks
- **Certificate Renewal**: Automated via cert-manager
- **Key Rotation**: Automated via AWS KMS
- **Security Patches**: Regular node and container updates
- **Policy Reviews**: Quarterly review of security policies
- **Access Reviews**: Regular review of service account permissions

### Security Assessments
- **Vulnerability Scanning**: Regular container and infrastructure scans
- **Penetration Testing**: Annual third-party security assessments
- **Compliance Audits**: Regular compliance verification
- **Security Training**: Ongoing security awareness training

## Troubleshooting

### Common Issues

#### RBAC Issues
```bash
# Check service account permissions
kubectl auth can-i --list --as=system:serviceaccount:ml-team-a:emr-spark-driver

# Verify role bindings
kubectl get rolebindings,clusterrolebindings -A | grep emr-spark-driver
```

#### Network Policy Issues
```bash
# Test network connectivity
kubectl run test-pod --image=busybox --rm -it -- wget -qO- http://service.namespace.svc.cluster.local

# Check network policies
kubectl get networkpolicies -A
```

#### Certificate Issues
```bash
# Check certificate status
kubectl get certificates -A

# View certificate details
kubectl describe certificate fraud-detection-ca -n cert-manager
```

#### Audit Logging Issues
```bash
# Check Fluent Bit logs
kubectl logs -n logging -l app=fluent-bit-audit

# Verify CloudWatch log groups
aws logs describe-log-groups --log-group-name-prefix /aws/eks/
```

## Security Best Practices

### Development
- Use non-root containers
- Implement health checks
- Use read-only root filesystems
- Drop unnecessary capabilities
- Set resource limits

### Deployment
- Use image scanning
- Implement admission controllers
- Use network policies
- Enable audit logging
- Regular security updates

### Operations
- Monitor security metrics
- Regular access reviews
- Incident response testing
- Security training
- Compliance verification

## References

- [Kubernetes Security Best Practices](https://kubernetes.io/docs/concepts/security/)
- [AWS EKS Security Best Practices](https://aws.github.io/aws-eks-best-practices/security/docs/)
- [Istio Security](https://istio.io/latest/docs/concepts/security/)
- [cert-manager Documentation](https://cert-manager.io/docs/)
- [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)