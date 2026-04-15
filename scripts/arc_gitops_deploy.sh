#!/usr/bin/env bash
set -euo pipefail

: "${RESOURCE_GROUP:?Set RESOURCE_GROUP}"
: "${CLUSTER_NAME:?Set CLUSTER_NAME}"
: "${CONFIG_NAME:=raspberry-pi-arc-demo-config}"
: "${GIT_REPO_URL:?Set GIT_REPO_URL}"
: "${GIT_BRANCH:=main}"
: "${MANIFEST_PATH:=./k8s}"

if ! command -v az >/dev/null 2>&1; then
  echo "Azure CLI is required" >&2
  exit 1
fi

az k8s-configuration flux create \
  --cluster-type connectedClusters \
  --cluster-name "${CLUSTER_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${CONFIG_NAME}" \
  --namespace flux-system \
  --scope cluster \
  --url "${GIT_REPO_URL}" \
  --branch "${GIT_BRANCH}" \
  --kustomization name=raspberry-pi-arc-demo path="${MANIFEST_PATH}" prune=true interval=3m

echo "Arc GitOps deployment configuration created/updated."
