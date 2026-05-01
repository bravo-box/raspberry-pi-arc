# azure-infra — Terraform for Azure Government Fleet Infrastructure

Terraform templates that provision all Azure Government resources required to
support the Raspberry Pi fleet back-end.

## Pre-requisites

| Tool | Minimum version |
|------|----------------|
| [Terraform](https://developer.hashicorp.com/terraform/install) | 1.5.0 |
| [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) | 2.50 |

## Resources provisioned

| Resource | Purpose |
|---|---|
| Resource Group | Logical container for all fleet resources |
| Azure Container Registry | Stores Docker images for the web app and function app |
| Azure Key Vault | Stores bearer tokens, connection strings, and secrets for Pi devices |
| Azure Cosmos DB (SQL API) | Tracks registered devices (`devices` container) and uploaded images (`images` container) |
| Azure Service Bus | Message broker with `TaskCamera`, `photo-upload`, and `photo-processed` topics |
| Azure Storage Account | Hosts photo blobs and backing storage for the Function App |
| Azure App Service (Linux container) | Runs the C# fleet dashboard web application |
| Azure Function App (Linux, isolated .NET 8) | Processes Service Bus messages from the Pi fleet |
| Application Insights | Shared telemetry for web app and function app |

### Service Bus topics and subscriptions

| Topic | Subscription | Consumer |
|---|---|---|
| `TaskCamera` | `camera-service` | Pi camera-service container |
| `photo-upload` | `cloud-processor` | Azure Function App |
| `photo-processed` | `file-service` | Pi file-service container |

## Deploying

### 1 — Authenticate to Azure Government

```bash
az cloud set --name AzureUSGovernment
az login
```

### 2 — Configure variables (optional)

Copy the example file and adjust as needed:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Key variables:

| Variable | Default | Description |
|---|---|---|
| `resource_group_name` | `rpi-fleet-rg` | Resource group name |
| `location` | `usgovarizona` | Azure Government region |
| `prefix` | `rpifleet` | Short prefix for resource names |
| `acr_sku` | `Basic` | Container Registry SKU |
| `web_app_sku` | `B1` | App Service Plan SKU for the web app |
| `cosmos_serverless` | `true` | Use Cosmos DB serverless capacity mode |
| `servicebus_sku` | `Standard` | Service Bus SKU (must be Standard or Premium for topics) |

### 3 — Deploy

```bash
cd azure-infra
terraform init
terraform plan -out tfplan
terraform apply tfplan
```

### 4 — Retrieve sensitive outputs

```bash
terraform output -json | jq '{
  acrPassword:                   .acr_admin_password.value,
  cosmosKey:                     .cosmos_db_primary_key.value,
  serviceBusConnectionString:    .servicebus_connection_string.value,
  storageKey:                    .storage_account_key.value
}'
```

### 5 — Build and push the web app image

After the registry is provisioned:

```bash
ACR=$(terraform output -raw acr_login_server)
ACR_USER=$(terraform output -raw acr_admin_username)
ACR_PASS=$(terraform output -raw acr_admin_password)

docker login "$ACR" -u "$ACR_USER" -p "$ACR_PASS"

# Build and push from the web-app directory
cd ../web-app
docker build -t "${ACR}/fleet-web:latest" .
docker push "${ACR}/fleet-web:latest"
```

Then update the web app to use the new image:

```bash
az webapp config container set \
  --resource-group rpi-fleet-rg \
  --name <web-app-name> \
  --docker-custom-image-name "${ACR}/fleet-web:latest"
```

## Tear down

```bash
terraform destroy
```
