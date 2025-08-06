# EKS Network Architecture

## Subnet Layout

```
VPC: 10.1.0.0/16
├── Public Subnets (10.1.0.x/26)
│   ├── NAT Gateway
│   └── Internet Gateway
├── Private Subnets (10.1.1.0/24, 10.1.2.0/24)
│   ├── EKS Control Plane ENIs
│   ├── EKS Worker Nodes
│   ├── Karpenter Nodes
│   └── Pod Networking (default)
└── Secondary CIDR: 100.64.0.0/16
    └── Intra Subnets (100.64.0.0/17, 100.64.128.0/17)
        └── Available for future custom pod networking
```

## Network Flow

1. **EKS Control Plane**: Deployed in private subnets (10.1.x.x)
2. **EKS Worker Nodes**: Deployed in private subnets (10.1.x.x)
3. **Pod Networking**: Uses same private subnets as nodes (10.1.x.x) by default
4. **Internet Access**: Nodes access internet via NAT Gateway in public subnets
5. **Pod Internet Access**: Pods access internet through their host nodes

## Key Components

- **VPC CNI**: Configured with prefix delegation for efficient IP usage
- **Secondary CIDR**: Available for future custom networking requirements
- **Karpenter**: Uses `karpenter.sh/discovery` tags to find private subnets for nodes
- **Security Groups**: Standard EKS node and cluster security groups

## Future Expansion

The secondary CIDR block (100.64.0.0/16) and intra subnets are available for:
- Custom pod networking via ENIConfig
- Additional workload isolation
- Scaling beyond primary CIDR capacity

This architecture provides flexibility for future networking requirements while maintaining simplicity for initial deployment.