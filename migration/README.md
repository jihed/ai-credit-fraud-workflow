# EMR to EKS Migration Scripts and Documentation

This directory contains migration scripts, utilities, and documentation for migrating fraud detection workloads from Amazon EMR to Amazon EKS using the existing EMR Spark RAPIDS infrastructure.

## Directory Structure

```
migration/
├── scripts/
│   ├── data-migration/          # Data migration scripts from EMR to EMR on EKS
│   ├── model-migration/         # Model migration utilities from SageMaker to EKS
│   └── validation/              # Migration validation scripts
├── docs/
│   ├── runbooks/               # Operational runbooks
│   └── user-guides/            # User documentation
└── templates/                  # Configuration templates
```

## Quick Start

1. **Infrastructure Setup**: Deploy EKS platform with `../emr-spark-rapids/terraform-deploy.sh`
2. **Data Upload**: Use `../emr-spark-rapids/upload-sample-data.sh` for sample datasets
3. **Data Migration**: See [Data Migration Guide](docs/user-guides/data-migration-guide.md)
4. **Model Migration**: See [Model Migration Guide](docs/user-guides/model-migration-guide.md)
5. **Operational Runbooks**: See [runbooks/](docs/runbooks/)
6. **Development Workflow**: See [Development Workflow Guide](docs/user-guides/development-workflow-guide.md)

## Prerequisites

- AWS CLI configured with appropriate permissions
- kubectl configured for target EKS cluster
- Docker installed for container operations
- Python 3.8+ with required dependencies

## Support

For issues and questions, refer to the troubleshooting runbooks in `docs/runbooks/`.