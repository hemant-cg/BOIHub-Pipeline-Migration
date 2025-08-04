# BOIHub Azure Function App Pipeline Migration

This project contains the migration from Classic Pipelines to YAML Pipelines for BOIHub Azure Function Apps, including compliant Bicep templates.

## Project Structure

```
├── bicep/                          # Bicep infrastructure templates
│   ├── modules/                    # Reusable Bicep modules
│   │   ├── function-app.bicep     # Function App module
│   │   ├── storage.bicep          # Storage Account module
│   │   ├── app-insights.bicep     # Application Insights module
│   │   └── networking.bicep       # VNet and subnet configuration
│   ├── main.bicep                 # Main deployment template
│   └── parameters/                # Parameter files for environments
├── pipelines/                     # YAML pipeline templates
│   ├── azure-function-app.yml     # Main Function App pipeline template
│   ├── templates/                 # Pipeline template fragments
│   └── variables/                 # Variable templates
├── docs/                          # Documentation
│   ├── pipeline-migration-guide.md
│   ├── bicep-templates-guide.md
│   └── migration-report.md
└── scripts/                       # Helper scripts
    └── validate-compliance.ps1    # Compliance validation script
```

## Key Features

- **Compliant Infrastructure**: All Azure resources created using Bicep with In Control compliance
- **YAML Pipelines**: Modern, version-controlled pipeline definitions
- **Reusable Templates**: Modular approach for multiple Function Apps
- **Security First**: TLS v1.2 minimum, proper networking, and secret management
- **Documentation**: Comprehensive guides and migration reports

## Quick Start

1. Review the Bicep templates in the `bicep/` directory
2. Customize the YAML pipeline template in `pipelines/azure-function-app.yml`
3. Update parameter files for your environments
4. Test in non-production environment first

## Compliance Requirements

- TLS v1.2 minimum for all connections
- Proper VNet integration with individual subnets per Function App
- Secure storage of secrets and connection strings
- Application Insights integration for monitoring
- Front Door configuration for traffic management
