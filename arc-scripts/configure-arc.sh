#!/usr/bin/env bash
# =============================================================================
# configure-arc.sh
#
# Configures a Raspberry Pi (running Raspberry Pi OS / Raspbian) as an
# Azure Arc-enabled server connected to the Azure Government cloud.
#
# Usage:
#   sudo ./configure-arc.sh \
#     --subscription-id  <AZURE_GOV_SUBSCRIPTION_ID>  \
#     --resource-group   <RESOURCE_GROUP_NAME>         \
#     --location         <AZURE_GOV_REGION>            \
#     --tenant-id        <AZURE_AD_TENANT_ID>          \
#     --service-principal-id     <SP_APP_ID>           \
#     --service-principal-secret <SP_PASSWORD>
#
# Supported Azure Government regions (as of 2024):
#   usgovvirginia | usgovarizona | usgovtexas
#
# References:
#   https://learn.microsoft.com/en-us/azure/azure-arc/servers/onboard-service-principal
#   https://learn.microsoft.com/en-us/azure/azure-government/documentation-government-get-started-connect-with-cli
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Colour helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()     { error "$*"; exit 1; }

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
AZCMAGENT_VERSION="latest"
CLOUD="AzureUSGovernment"           # Azure Government cloud name used by azcmagent
CORRELATION_ID=""                   # Optional: used for tracking onboarding source

SUBSCRIPTION_ID=""
RESOURCE_GROUP=""
LOCATION=""
TENANT_ID=""
SP_ID=""
SP_SECRET=""
RESOURCE_NAME=""                    # Defaults to the hostname when empty
TAGS=""                             # Optional: comma-separated key=value pairs

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
usage() {
  cat <<EOF
Usage: sudo $0 [OPTIONS]

Required:
  --subscription-id          <id>      Azure Government subscription ID
  --resource-group           <name>    Azure resource group name
  --location                 <region>  Azure Government region (e.g. usgovvirginia)
  --tenant-id                <id>      Azure AD (Entra ID) tenant ID
  --service-principal-id     <id>      Service principal application (client) ID
  --service-principal-secret <secret>  Service principal client secret

Optional:
  --resource-name  <name>   Arc resource name (default: hostname)
  --tags           <tags>   Comma-separated key=value tags
  --help                    Show this help message

EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --subscription-id)          SUBSCRIPTION_ID="$2";  shift 2 ;;
    --resource-group)           RESOURCE_GROUP="$2";   shift 2 ;;
    --location)                 LOCATION="$2";          shift 2 ;;
    --tenant-id)                TENANT_ID="$2";         shift 2 ;;
    --service-principal-id)     SP_ID="$2";             shift 2 ;;
    --service-principal-secret) SP_SECRET="$2";         shift 2 ;;
    --resource-name)            RESOURCE_NAME="$2";     shift 2 ;;
    --tags)                     TAGS="$2";              shift 2 ;;
    --help|-h)                  usage ;;
    *) die "Unknown option: $1. Run with --help for usage." ;;
  esac
done

# ---------------------------------------------------------------------------
# Validate required parameters
# ---------------------------------------------------------------------------
validate_params() {
  local missing=()
  [[ -z "$SUBSCRIPTION_ID" ]] && missing+=("--subscription-id")
  [[ -z "$RESOURCE_GROUP"  ]] && missing+=("--resource-group")
  [[ -z "$LOCATION"        ]] && missing+=("--location")
  [[ -z "$TENANT_ID"       ]] && missing+=("--tenant-id")
  [[ -z "$SP_ID"           ]] && missing+=("--service-principal-id")
  [[ -z "$SP_SECRET"       ]] && missing+=("--service-principal-secret")

  if [[ ${#missing[@]} -gt 0 ]]; then
    error "Missing required parameters: ${missing[*]}"
    error "Run with --help for usage."
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# Verify the script is running as root
# ---------------------------------------------------------------------------
check_root() {
  if [[ "$EUID" -ne 0 ]]; then
    die "This script must be run as root (sudo)."
  fi
}

# ---------------------------------------------------------------------------
# Verify the OS is Raspberry Pi OS / Debian-based
# ---------------------------------------------------------------------------
check_os() {
  if ! command -v apt-get &>/dev/null; then
    die "This script requires a Debian/Raspberry Pi OS based system (apt-get not found)."
  fi
  info "OS check passed."
}

# ---------------------------------------------------------------------------
# Install prerequisite packages
# ---------------------------------------------------------------------------
install_prerequisites() {
  info "Updating package lists and installing prerequisites..."
  apt-get update -qq
  apt-get install -y --no-install-recommends \
    curl \
    gnupg \
    ca-certificates \
    lsb-release \
    apt-transport-https
  info "Prerequisites installed."
}

# ---------------------------------------------------------------------------
# Download and install the Azure Connected Machine agent (azcmagent)
# ---------------------------------------------------------------------------
install_azcmagent() {
  if command -v azcmagent &>/dev/null; then
    info "azcmagent is already installed ($(azcmagent version 2>/dev/null || echo 'unknown version'))."
    return
  fi

  info "Downloading Azure Connected Machine agent install script..."

  local install_script
  install_script=$(mktemp /tmp/install_arc_agent.XXXXXX.sh)

  # The official install script auto-detects architecture (arm64 / armhf / x86_64)
  curl -fsSL "https://aka.ms/azcmagent" -o "$install_script"
  chmod +x "$install_script"

  info "Installing Azure Connected Machine agent..."
  bash "$install_script"
  rm -f "$install_script"

  if ! command -v azcmagent &>/dev/null; then
    die "azcmagent installation failed — binary not found after install."
  fi
  info "azcmagent installed successfully: $(azcmagent version 2>/dev/null)"
}

# ---------------------------------------------------------------------------
# Connect the machine to Azure Arc (Azure Government)
# ---------------------------------------------------------------------------
connect_arc() {
  # Default the resource name to the system hostname
  local resource_name="${RESOURCE_NAME:-$(hostname)}"

  info "Connecting this machine to Azure Arc..."
  info "  Cloud             : $CLOUD"
  info "  Subscription ID   : $SUBSCRIPTION_ID"
  info "  Resource Group    : $RESOURCE_GROUP"
  info "  Location          : $LOCATION"
  info "  Tenant ID         : $TENANT_ID"
  info "  Resource Name     : $resource_name"

  local connect_args=(
    --cloud               "$CLOUD"
    --subscription-id     "$SUBSCRIPTION_ID"
    --resource-group      "$RESOURCE_GROUP"
    --location            "$LOCATION"
    --tenant-id           "$TENANT_ID"
    --service-principal-id     "$SP_ID"
    --service-principal-secret "$SP_SECRET"
    --resource-name       "$resource_name"
  )

  # Append optional tags if provided
  if [[ -n "$TAGS" ]]; then
    connect_args+=(--tags "$TAGS")
  fi

  # Append optional correlation ID if set
  if [[ -n "$CORRELATION_ID" ]]; then
    connect_args+=(--correlation-id "$CORRELATION_ID")
  fi

  azcmagent connect "${connect_args[@]}"

  info "Arc connection successful."
}

# ---------------------------------------------------------------------------
# Verify the connection status
# ---------------------------------------------------------------------------
verify_connection() {
  info "Verifying Azure Arc connection status..."
  azcmagent show
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  echo "========================================================"
  echo "  Azure Arc for Raspberry Pi — Azure Government Setup"
  echo "========================================================"

  check_root
  validate_params
  check_os
  install_prerequisites
  install_azcmagent
  connect_arc
  verify_connection

  echo ""
  info "✅  Raspberry Pi is now managed via Azure Arc (Azure Government)."
  echo ""
}

main "$@"
