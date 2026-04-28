#!/usr/bin/env bash
# Bootstrap script for Terraform remote state in Azure Government.
# Creates a resource group, storage account, and blob container for tfstate,
# then assigns the deploying user Contributor + Storage Blob Data Owner roles.
#
# Usage:
#   export SUBSCRIPTION_ID="<your-subscription-id>"
#   export RESOURCE_GROUP="rpi-arc-tfstate-rg"          # optional
#   export LOCATION="usgovarizona"                       # optional
#   export STORAGE_ACCOUNT_NAME="rpiarctfstate<suffix>"  # optional
#   ./bootstrap.sh

set -euo pipefail

RESOURCE_GROUP="${RESOURCE_GROUP:-rpi-arc-tfstate-rg}"
LOCATION="${LOCATION:-usgovarizona}"
SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-}"
CONTAINER_NAME="tfstate"

# Derive a default storage account name if not provided (must be globally unique,
# lowercase, alphanumeric, 3-24 chars).
if [[ -z "${STORAGE_ACCOUNT_NAME:-}" ]]; then
  SUFFIX=$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom 2>/dev/null | head -c 8 || echo "00000000")
  STORAGE_ACCOUNT_NAME="rpiarctf${SUFFIX}"
fi

# ── Validation ────────────────────────────────────────────────────────────────
if [[ -z "${SUBSCRIPTION_ID}" ]]; then
  echo "ERROR: SUBSCRIPTION_ID must be set." >&2
  exit 1
fi

if ! command -v az &>/dev/null; then
  echo "ERROR: Azure CLI (az) is not installed or not in PATH." >&2
  exit 1
fi

# ── Azure CLI context ─────────────────────────────────────────────────────────
echo "==> Setting active subscription: ${SUBSCRIPTION_ID}"
az account set --subscription "${SUBSCRIPTION_ID}"

DEPLOYER_ID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null || \
              az account show --query user.name -o tsv)

echo "==> Deploying as: ${DEPLOYER_ID}"

# ── Resource Group ────────────────────────────────────────────────────────────
echo "==> Ensuring resource group '${RESOURCE_GROUP}' in '${LOCATION}'"
az group create \
  --name "${RESOURCE_GROUP}" \
  --location "${LOCATION}" \
  --output none

# ── Storage Account ───────────────────────────────────────────────────────────
echo "==> Ensuring storage account '${STORAGE_ACCOUNT_NAME}'"
az storage account create \
  --name "${STORAGE_ACCOUNT_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --location "${LOCATION}" \
  --sku Standard_LRS \
  --kind StorageV2 \
  --allow-blob-public-access false \
  --min-tls-version TLS1_2 \
  --output none

STORAGE_ACCOUNT_ID=$(az storage account show \
  --name "${STORAGE_ACCOUNT_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query id -o tsv)

# ── Blob Container ────────────────────────────────────────────────────────────
echo "==> Ensuring blob container '${CONTAINER_NAME}'"
az storage container create \
  --name "${CONTAINER_NAME}" \
  --account-name "${STORAGE_ACCOUNT_NAME}" \
  --auth-mode login \
  --output none

# ── RBAC ──────────────────────────────────────────────────────────────────────
SCOPE_RG="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}"

assign_role() {
  local role="$1"
  local scope="$2"
  local assignee="$3"

  local existing
  existing=$(az role assignment list \
    --assignee "${assignee}" \
    --role "${role}" \
    --scope "${scope}" \
    --query "[].id" -o tsv 2>/dev/null || true)

  if [[ -z "${existing}" ]]; then
    echo "  Assigning '${role}' to '${assignee}' on scope '${scope}'"
    az role assignment create \
      --assignee "${assignee}" \
      --role "${role}" \
      --scope "${scope}" \
      --output none
  else
    echo "  Role '${role}' already assigned — skipping"
  fi
}

echo "==> Assigning RBAC roles to deployer"
assign_role "Contributor"               "${SCOPE_RG}"           "${DEPLOYER_ID}"
assign_role "Storage Blob Data Owner"   "${STORAGE_ACCOUNT_ID}" "${DEPLOYER_ID}"

# ── Output backend config ─────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════════════"
echo " Terraform backend configuration"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "Add the following to backend.tf (or pass as -backend-config flags):"
echo ""
echo "  resource_group_name  = \"${RESOURCE_GROUP}\""
echo "  storage_account_name = \"${STORAGE_ACCOUNT_NAME}\""
echo "  container_name       = \"${CONTAINER_NAME}\""
echo "  key                  = \"terraform.tfstate\""
echo ""
echo "Or run:"
echo "  terraform init \\"
echo "    -backend-config=\"resource_group_name=${RESOURCE_GROUP}\" \\"
echo "    -backend-config=\"storage_account_name=${STORAGE_ACCOUNT_NAME}\" \\"
echo "    -backend-config=\"container_name=${CONTAINER_NAME}\" \\"
echo "    -backend-config=\"key=terraform.tfstate\""
echo ""
echo "════════════════════════════════════════════════════════════════"
