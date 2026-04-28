#!/usr/bin/env bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
APP_DIR="$PROJECT_ROOT/rpi-app"
# Use timestamp-based tag to force image pull
TIMESTAMP=$(date +%s)
IMAGE_NAME="raspberry-pi-arc-demo:${TIMESTAMP}"
IMAGE_LATEST="raspberry-pi-arc-demo:latest"
DEPLOYMENT_NAME="rpi-camera-app"
NAMESPACE="raspberry-pi-arc-demo"

# Functions
log_info() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

# Main script
main() {
  log_info "Building and deploying Raspberry Pi app to k3s..."

  # Check if required tools are available
  if ! command -v docker &> /dev/null; then
    log_error "Docker is not installed or not in PATH"
    exit 1
  fi

  if ! command -v kubectl &> /dev/null; then
    log_error "kubectl is not installed or not in PATH"
    exit 1
  fi

  # Check if connected to k3s cluster
  if ! kubectl cluster-info &> /dev/null; then
    log_error "Not connected to a Kubernetes cluster"
    exit 1
  fi

  log_info "Building Docker image: $IMAGE_NAME"
  if docker build --file "$APP_DIR/Dockerfile" -t "$IMAGE_NAME" "$APP_DIR"; then
    log_info "✓ Docker image built successfully"
  else
    log_error "Failed to build Docker image"
    exit 1
  fi

  log_info "Checking if namespace exists: $NAMESPACE"
  if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
    log_warn "Namespace $NAMESPACE does not exist, creating it..."
    kubectl create namespace "$NAMESPACE"
  fi

  log_info "Applying Kubernetes manifests..."
  # Use kustomize to build and apply the manifests
  kubectl apply -k "$PROJECT_ROOT/k8s/"
  log_info "✓ Manifests applied"

  log_info "Restarting deployment: $DEPLOYMENT_NAME"
  kubectl rollout restart deployment/"$DEPLOYMENT_NAME" -n "$NAMESPACE"
  log_info "✓ Deployment restarted"

  log_info "Waiting for rollout to complete..."
  if kubectl rollout status deployment/"$DEPLOYMENT_NAME" -n "$NAMESPACE" --timeout=5m; then
    log_info "✓ Rollout completed successfully"
  else
    log_warn "Rollout status check timed out or failed, but deployment may still be progressing"
  fi

  log_info ""
  log_info "✓ Build and deployment complete!"
  log_info ""
  log_info "To access the web UI:"
  
  # Try to get the node IP - extract the first InternalIP address (usually IPv4)
  NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null | awk '{print $1}' || echo "<node-ip>")
  
  if [ -n "$NODE_IP" ] && [ "$NODE_IP" != "<node-ip>" ]; then
    log_info "  http://$NODE_IP:30500"
  else
    log_info "  http://<node-ip>:30500"
    log_info ""
    log_info "Get your node IP with:"
    log_info "  kubectl get nodes -o wide"
  fi

  log_info ""
  log_info "To view logs:"
  log_info "  kubectl logs -f deployment/$DEPLOYMENT_NAME -n $NAMESPACE"
}

main "$@"
