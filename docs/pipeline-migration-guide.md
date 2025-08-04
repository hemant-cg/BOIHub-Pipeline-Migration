# BOIHub Pipeline Migration Guide

## Overview

This guide provides comprehensive instructions for migrating BOIHub Classic Pipelines to modern YAML-based pipelines for Azure Function Apps, with full In Control compliance.

## Migration Strategy

### Phase 1: Assessment and Planning
1. **Inventory Classic Pipelines**: Document all existing classic pipelines for Function Apps
2. **Analyze Dependencies**: Identify build steps, deployment targets, and approval processes
3. **Map Variables and Secrets**: Catalog all pipeline variables and secret references

### Phase 2: Infrastructure as Code
1. **Bicep Template Development**: Create compliant infrastructure templates
2. **Environment Configuration**: Set up parameter files for dev/test/prod
3. **Security Implementation**: Implement In Control compliance requirements

### Phase 3: YAML Pipeline Creation
1. **Pipeline Structure**: Build multi-stage YAML pipelines
2. **Template Reusability**: Create reusable templates for common tasks
3. **Integration Testing**: Validate pipeline functionality in non-production

### Phase 4: Migration Execution
1. **Parallel Running**: Run both classic and YAML pipelines during transition
2. **Validation**: Ensure feature parity between old and new pipelines
3. **Cutover**: Switch to YAML pipelines and decommission classic ones

## Pipeline Architecture

### Multi-Stage Pipeline Structure

```yaml
Stages:
├── Validate
│   ├── Code Analysis (SonarCloud, CredScan)
│   ├── Unit Tests
│   └── Bicep Validation
├── Build & Package
│   ├── .NET Build
│   ├── Function App Packaging
│   └── Artifact Publishing
├── Deploy Dev
│   ├── Infrastructure Deployment
│   ├── Function App Deployment
│   └── Compliance Validation
├── Deploy Test
│   ├── Infrastructure Deployment
│   ├── Function App Deployment
│   └── Integration Testing
└── Deploy Production
    ├── Manual Approval
    ├── Infrastructure Deployment
    ├── Function App Deployment
    └── Post-Deployment Validation
```

## Key Features

### 1. In Control Compliance
- **TLS 1.2 Enforcement**: All services configured with minimum TLS 1.2
- **HTTPS Only**: All web services enforce HTTPS-only traffic
- **Network Security**: Proper NSG rules and VNet integration
- **Encryption**: Storage and Key Vault encryption enabled
- **Access Control**: Managed identities and RBAC implementation

### 2. Infrastructure as Code
- **Bicep Templates**: All Azure resources defined in Bicep
- **Modular Design**: Reusable modules for different resource types
- **Parameter Files**: Environment-specific configuration
- **Validation**: Template validation and linting in pipeline

### 3. Security and Quality
- **Code Analysis**: SonarCloud integration for code quality
- **Security Scanning**: Credential scanning and vulnerability assessment
- **Compliance Validation**: Automated compliance checking
- **Secret Management**: Azure Key Vault integration

### 4. Monitoring and Observability
- **Application Insights**: Comprehensive application monitoring
- **Log Analytics**: Centralized logging and analytics
- **Alerting**: Automated alert rules for key metrics
- **Health Checks**: Endpoint monitoring and validation

## Environment Configuration

### Development Environment
- **Purpose**: Development and feature testing
- **Deployment Trigger**: Commits to `develop` branch
- **Approval**: No manual approval required
- **Resources**: Shared development resources

### Test Environment
- **Purpose**: Integration testing and UAT
- **Deployment Trigger**: Commits to `main` branch
- **Approval**: Automatic after dev deployment
- **Resources**: Production-like configuration

### Production Environment
- **Purpose**: Live production workloads
- **Deployment Trigger**: Commits to `main` branch
- **Approval**: Manual approval required
- **Resources**: High availability configuration

## Variable Groups

### Required Variable Groups
1. **BOIHub-Dev-Variables**
   - `azureLocation`: Azure region for resources
   - `subscriptionId`: Azure subscription ID
   - `storageAccountSku`: Storage account SKU

2. **BOIHub-Test-Variables**
   - Same as dev with test-specific values

3. **BOIHub-Prod-Variables**
   - Same as dev with production-specific values

### Service Connections
- **BOIHub-ServiceConnection**: Azure Resource Manager connection
- **SonarCloud-ServiceConnection**: SonarCloud service connection

## Migration Checklist

### Pre-Migration
- [ ] Document all classic pipeline configurations
- [ ] Identify all variables and secrets used
- [ ] Map approval processes and gates
- [ ] Set up Azure DevOps variable groups
- [ ] Configure service connections
- [ ] Create Azure environments for approvals

### During Migration
- [ ] Deploy Bicep templates to development
- [ ] Test YAML pipeline in development
- [ ] Validate compliance requirements
- [ ] Run parallel deployments (classic vs YAML)
- [ ] Perform integration testing
- [ ] Update documentation and runbooks

### Post-Migration
- [ ] Monitor new pipeline performance
- [ ] Validate all functionality works as expected
- [ ] Train team on new pipeline processes
- [ ] Decommission classic pipelines
- [ ] Update operational procedures

## Troubleshooting

### Common Issues

#### 1. Bicep Validation Failures
```bash
# Check Bicep syntax
az bicep build --file bicep/main.bicep

# Validate against Azure
az deployment group validate \
  --resource-group rg-boihub-dev \
  --template-file bicep/main.bicep \
  --parameters environment=dev
```

#### 2. Function App Deployment Issues
- Verify package path in pipeline
- Check Function App configuration
- Validate managed identity permissions

#### 3. Compliance Validation Failures
- Review compliance script output
- Check resource configurations
- Validate security settings

### Support Contacts
- **DevOps Team**: devops@boihub.com
- **Security Team**: security@boihub.com
- **Platform Team**: platform@boihub.com

## Best Practices

### 1. Pipeline Design
- Use templates for reusable components
- Implement proper error handling
- Add comprehensive logging
- Use conditional deployments

### 2. Security
- Never hardcode secrets in pipelines
- Use managed identities where possible
- Implement least privilege access
- Regular security reviews

### 3. Monitoring
- Set up comprehensive alerting
- Monitor pipeline performance
- Track deployment success rates
- Regular compliance audits

### 4. Documentation
- Keep documentation up to date
- Document all customizations
- Maintain troubleshooting guides
- Regular knowledge sharing sessions
