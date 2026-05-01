# function-app — Fleet Azure Function App (C# / .NET 8 Isolated)

An Azure Functions v4 project (isolated worker model, .NET 8) that processes
Service Bus messages sent by the Raspberry Pi fleet and persists data to Cosmos DB.

## Functions

| Function | Trigger | Description |
|---|---|---|
| `PhotoUploadFunction` | Service Bus `photo-upload / cloud-processor` | Saves image metadata to Cosmos DB, upserts the device record, sends a `photo-processed` acknowledgement |
| `TaskCameraFunction` | Service Bus `TaskCamera / cloud-monitor` | Cloud-side audit log for camera-capture commands |
| `PhotoProcessedFunction` | Service Bus `photo-processed / cloud-audit` | Cloud-side audit log for acknowledgement messages |

## Data model (Cosmos DB)

### `devices` container (partition key: `/id`)

```json
{
  "id": "rpi-node-01",
  "hostname": "rpi-node-01",
  "firstSeen": "2024-01-15T10:00:00Z",
  "lastSeen":  "2024-01-20T14:35:00Z",
  "imageCount": 42
}
```

### `images` container (partition key: `/hostName`)

```json
{
  "id": "rpi-node-01_20240120T143500_000000.jpg",
  "hostName": "rpi-node-01",
  "fileName": "rpi-node-01_20240120T143500_000000.jpg",
  "storageAccount": "rpifleetstxxxxxx",
  "container": "photos",
  "uploadedAt": "2024-01-20T14:35:02Z"
}
```

## Local development

### Prerequisites

* [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0)
* [Azure Functions Core Tools v4](https://learn.microsoft.com/en-us/azure/azure-functions/functions-run-local)
* [Azurite](https://learn.microsoft.com/en-us/azure/storage/common/storage-use-azurite) (local storage emulator)

### Configure `local.settings.json`

Copy and fill in the required values:

```json
{
  "IsEncrypted": false,
  "Values": {
    "AzureWebJobsStorage": "UseDevelopmentStorage=true",
    "FUNCTIONS_WORKER_RUNTIME": "dotnet-isolated",
    "ServiceBusConnection": "<service-bus-connection-string>",
    "CosmosDb__Endpoint": "https://<account>.documents.azure.us:443/",
    "CosmosDb__AccountKey": "<primary-key>",
    "CosmosDb__DatabaseName": "fleet"
  }
}
```

Use the Terraform outputs from `azure-infra/`:

```bash
cd ../azure-infra
terraform output -raw servicebus_connection_string
terraform output -raw cosmos_db_endpoint
terraform output -raw cosmos_db_primary_key
```

### Run locally

```bash
cd function-app
dotnet build
func start
```

## Build and deploy

```bash
dotnet publish -c Release -o ./publish

# Deploy to the Azure Function App provisioned by Terraform
func azure functionapp publish <function-app-name> --dotnet-isolated
```

Retrieve the function app name from Terraform:

```bash
cd ../azure-infra
terraform output function_app_hostname
```
