#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# build-images.sh – Build (and optionally push) container images.
#
# Usage:
#   ./scripts/build-images.sh [OPTIONS] [IMAGE...]
#
# Options:
#   --push              Push built images to the registry after building.
#   --registry REG      Registry host (default: ghcr.io).
#   --repo REPO         Repository path within the registry
#                       (default: bravo-box/raspberry-pi-arc).
#                       Must be lowercase for ghcr.io.
#   --tag TAG           Image tag (default: latest).
#   --platform PLAT     Override the target platform(s) for all images, e.g.
#                       linux/amd64 or linux/amd64,linux/arm64.
#                       When omitted, each image uses its own default platform
#                       (Pi services default to linux/arm64; web-app uses the
#                       host default).
#
# IMAGE is one or more of:
#   web-app  rpi-app  camera-service  file-service
#   all      (build every image – also the default when no IMAGE is given)
#
# Examples:
#   # Build all images locally:
#   ./scripts/build-images.sh
#
#   # Build only the web-app image and push to ghcr.io:
#   ./scripts/build-images.sh --push web-app
#
#   # Build all images and push with a custom tag:
#   ./scripts/build-images.sh --push --tag v1.2.3 all
#
#   # Build all images and push to a custom registry:
#   ./scripts/build-images.sh --push --registry myregistry.azurecr.io --repo myorg/myrepo
#
#   # Override platform for all images:
#   ./scripts/build-images.sh --push --platform linux/amd64
# ---------------------------------------------------------------------------
set -euo pipefail

# ---------------------------------------------------------------------------
# Colour / logging helpers (consistent with other scripts in this directory)
# ---------------------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()   { error "$*"; exit 1; }
step()  { echo -e "\n${CYAN}==> $*${NC}"; }

# ---------------------------------------------------------------------------
# Locate repo root
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
PUSH=false
REGISTRY="ghcr.io"
REPO="bravo-box/raspberry-pi-arc"
TAG="latest"
PLATFORM_OVERRIDE=""   # set by --platform; empty means use per-image default
SELECTED_IMAGES=()

# ---------------------------------------------------------------------------
# Known images: context path, Dockerfile name, and default build platform.
#
# Pi-targeting services (rpi-app, camera-service, file-service) default to
# linux/arm64 to match Raspberry Pi hardware.  The web-app runs on Azure App
# Service (amd64) so it uses the host/runner default (no explicit platform).
# ---------------------------------------------------------------------------
declare -A IMAGE_CONTEXT
declare -A IMAGE_DOCKERFILE
declare -A IMAGE_DEFAULT_PLATFORM

IMAGE_CONTEXT["web-app"]="web-app"
IMAGE_DOCKERFILE["web-app"]="Dockerfile"
IMAGE_DEFAULT_PLATFORM["web-app"]=""

IMAGE_CONTEXT["rpi-app"]="rpi-app"
IMAGE_DOCKERFILE["rpi-app"]="Dockerfile"
IMAGE_DEFAULT_PLATFORM["rpi-app"]="linux/arm64"

IMAGE_CONTEXT["camera-service"]="camera-app/camera-service"
IMAGE_DOCKERFILE["camera-service"]="Dockerfile"
IMAGE_DEFAULT_PLATFORM["camera-service"]="linux/arm64"

IMAGE_CONTEXT["file-service"]="camera-app/file-service"
IMAGE_DOCKERFILE["file-service"]="Dockerfile"
IMAGE_DEFAULT_PLATFORM["file-service"]="linux/arm64"

ALL_IMAGES=("web-app" "rpi-app" "camera-service" "file-service")

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --push)         PUSH=true; shift ;;
    --registry)     REGISTRY="$2"; shift 2 ;;
    --repo)         REPO="$2"; shift 2 ;;
    --tag)          TAG="$2"; shift 2 ;;
    --platform)     PLATFORM_OVERRIDE="$2"; shift 2 ;;
    all)            SELECTED_IMAGES=("${ALL_IMAGES[@]}"); shift ;;
    web-app|rpi-app|camera-service|file-service)
                    SELECTED_IMAGES+=("$1"); shift ;;
    *)              die "Unknown argument: '$1'. Valid images: all ${ALL_IMAGES[*]}" ;;
  esac
done

# Default to all images when none specified
if [[ ${#SELECTED_IMAGES[@]} -eq 0 ]]; then
  SELECTED_IMAGES=("${ALL_IMAGES[@]}")
fi

# Normalize repo to lowercase (required by ghcr.io)
REPO="${REPO,,}"

# ---------------------------------------------------------------------------
# Compute OCI annotation values
# ---------------------------------------------------------------------------
GIT_REVISION="$(git -C "${REPO_ROOT}" rev-parse HEAD 2>/dev/null || echo "unknown")"
BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ---------------------------------------------------------------------------
# Verify Docker is available
# ---------------------------------------------------------------------------
step "Verifying Docker is available..."
if ! command -v docker >/dev/null 2>&1; then
  die "Docker is not installed or not in PATH."
fi
info "Docker version: $(docker --version)"

echo ""
echo "========================================================"
echo "  Raspberry Pi Arc – Image Builder"
echo "========================================================"
info "Registry    : ${REGISTRY}"
info "Repository  : ${REPO}"
info "Tag         : ${TAG}"
info "Push        : ${PUSH}"
info "Platform    : ${PLATFORM_OVERRIDE:-<per-image default>}"
info "Git revision: ${GIT_REVISION}"
info "Images      : ${SELECTED_IMAGES[*]}"

# ---------------------------------------------------------------------------
# Build (and optionally push) each image
# ---------------------------------------------------------------------------
BUILT=()
FAILED=()

for img in "${SELECTED_IMAGES[@]}"; do
  context="${REPO_ROOT}/${IMAGE_CONTEXT[$img]}"
  dockerfile="${context}/${IMAGE_DOCKERFILE[$img]}"
  full_image="${REGISTRY}/${REPO}/${img}:${TAG}"

  # Resolve effective platform: explicit override wins; fall back to per-image default
  effective_platform="${PLATFORM_OVERRIDE:-${IMAGE_DEFAULT_PLATFORM[$img]}}"

  step "Building ${full_image} (platform: ${effective_platform:-<host default>})..."

  if [[ ! -f "${dockerfile}" ]]; then
    warn "Dockerfile not found for '${img}': ${dockerfile} – skipping."
    continue
  fi

  # Common build arguments and OCI labels
  common_args=(
    "--file"       "${dockerfile}"
    "--tag"        "${full_image}"
    "--build-arg"  "GIT_REVISION=${GIT_REVISION}"
    "--build-arg"  "BUILD_DATE=${BUILD_DATE}"
    "--build-arg"  "IMAGE_VERSION=${TAG}"
    "--label"      "org.opencontainers.image.source=https://github.com/${REPO}"
    "--label"      "org.opencontainers.image.revision=${GIT_REVISION}"
    "--label"      "org.opencontainers.image.created=${BUILD_DATE}"
    "--label"      "org.opencontainers.image.version=${TAG}"
  )

  if [[ -n "${effective_platform}" ]]; then
    common_args+=("--platform" "${effective_platform}")
  fi

  # Choose the correct Docker invocation:
  #   --push              → docker buildx build --push  (supports multi-platform)
  #   platform (no push)  → docker buildx build --load  (single-platform, local load)
  #   no platform, no push → docker build               (local daemon, fastest)
  build_ok=true
  if [[ "${PUSH}" == true ]]; then
    docker buildx build "${common_args[@]}" --push "${context}" || build_ok=false
  elif [[ -n "${effective_platform}" ]]; then
    docker buildx build "${common_args[@]}" --load "${context}" || build_ok=false
  else
    docker build "${common_args[@]}" "${context}" || build_ok=false
  fi

  if [[ "${build_ok}" == true ]]; then
    BUILT+=("${full_image}")
    info "✅  Built ${full_image}"
  else
    FAILED+=("${img}")
    error "❌  Failed to build ${img}"
  fi
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "========================================================"
if [[ ${#FAILED[@]} -eq 0 ]]; then
  info "✅  All selected images built successfully."
  for img_ref in "${BUILT[@]}"; do
    info "    ${img_ref}"
  done
  if [[ "${PUSH}" == true ]]; then
    info "All images pushed to ${REGISTRY}/${REPO}."
  fi
else
  error "❌  The following images FAILED to build:"
  for name in "${FAILED[@]}"; do
    error "    - ${name}"
  done
  [[ ${#BUILT[@]} -gt 0 ]] && info "Successfully built: ${BUILT[*]}"
  exit 1
fi
echo "========================================================"
