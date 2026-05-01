# web-app — Fleet Dashboard (C# ASP.NET Core 8 MVC)

An ASP.NET Core 8 MVC web application that provides a dashboard for viewing all
registered Raspberry Pi devices and the images they have uploaded.

## Features

* **Device list** — Shows all registered devices, their total image count, and
  first/last-seen timestamps.
* **Device detail** — Shows a responsive image grid for a selected device.
  Images are served via short-lived Azure Blob Storage SAS URLs so they render
  directly in the browser without exposing storage credentials.

## Prerequisites

* [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0)
* A deployed `azure-infra/` stack (Cosmos DB + Azure Blob Storage)
* (Production) A running `function-app/` that populates Cosmos DB

## Configuration

The application reads configuration from `appsettings.json` / environment variables.

| Key | Description |
|-----|-------------|
| `CosmosDb:Endpoint`     | Cosmos DB account endpoint (e.g. `https://<account>.documents.azure.us:443/`) |
| `CosmosDb:AccountKey`   | Cosmos DB primary key |
| `CosmosDb:DatabaseName` | Cosmos DB database name (default: `fleet`) |
| `Storage:AccountName`   | Azure Storage account name |
| `Storage:AccountKey`    | Azure Storage primary key |
| `Storage:PhotoContainer`| Blob container for photos (default: `photos`) |

Retrieve values from the Terraform deployment:

```bash
cd ../azure-infra
terraform output cosmos_db_endpoint
terraform output -raw cosmos_db_primary_key
terraform output storage_account_name
terraform output -raw storage_account_key
```

## Running locally

```bash
cd web-app

# Set secrets as environment variables (or use dotnet user-secrets)
export CosmosDb__Endpoint="https://<account>.documents.azure.us:443/"
export CosmosDb__AccountKey="<key>"
export Storage__AccountName="<storage-account>"
export Storage__AccountKey="<key>"

dotnet run
```

Browse to `http://localhost:5000`.

## Building the Docker image

```bash
docker build -t fleet-web:latest .
```

## Pushing to Azure Container Registry

```bash
cd ../azure-infra
ACR=$(terraform output -raw acr_login_server)

docker tag fleet-web:latest "${ACR}/fleet-web:latest"
docker push "${ACR}/fleet-web:latest"
```

Then update the App Service to use the new image:

```bash
az webapp config container set \
  --resource-group rpi-fleet-rg \
  --name <web-app-name> \
  --docker-custom-image-name "${ACR}/fleet-web:latest"
```
