#!/usr/bin/env bash
set -euo pipefail

: "${RESOURCE_GROUP:?Set RESOURCE_GROUP}"
: "${CLUSTER_NAME:?Set CLUSTER_NAME}"
: "${LOCATION:?Set LOCATION}"
: "${SUBSCRIPTION_ID:?Set SUBSCRIPTION_ID}"

if ! command -v az >/dev/null 2>&1; then
  echo "Azure CLI is required" >&2
  exit 1
fi

az account set --subscription "${SUBSCRIPTION_ID}"
az extension add --name connectedk8s --upgrade --yes
az extension add --name k8s-extension --upgrade --yes
az extension add --name k8s-configuration --upgrade --yes

az connectedk8s connect \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${CLUSTER_NAME}" \
  --location "${LOCATION}"

# Azure Monitor extension for container log collection/aggregation from Arc-enabled K8s.
az k8s-extension create \
  --cluster-type connectedClusters \
  --cluster-name "${CLUSTER_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --name azuremonitor-containers \
  --extension-type Microsoft.AzureMonitor.Containers \
  --auto-upgrade true \
  --release-train stable

echo "Arc onboarding complete for cluster ${CLUSTER_NAME}."
