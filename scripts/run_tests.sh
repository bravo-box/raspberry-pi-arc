#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# run_tests.sh — Build and run the .NET xUnit test suites.
#
# Runs tests for:
#   - function-app.tests  (Azure Functions)
#   - web-app.tests       (ASP.NET Core MVC)
#
# Usage:
#   ./scripts/run_tests.sh [--coverage]
#
#   --coverage   Collect code-coverage data with coverlet and write a Cobertura
#                report to /tmp/coverage/.  Requires no extra tools beyond the
#                coverlet.collector NuGet package that is already in the test
#                projects.
#
# The script exits with a non-zero code if any test project fails.
# ---------------------------------------------------------------------------
set -euo pipefail

# ---------------------------------------------------------------------------
# Colour / logging helpers  (consistent with other scripts in this directory)
# ---------------------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()   { error "$*"; exit 1; }
step()  { echo -e "\n${CYAN}==> $*${NC}"; }

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
COVERAGE=false
for arg in "$@"; do
  case "$arg" in
    --coverage) COVERAGE=true ;;
    *) die "Unknown argument: $arg" ;;
  esac
done

# ---------------------------------------------------------------------------
# Locate repo root (the directory that contains this script's parent)
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "========================================================"
echo "  Raspberry Pi Arc — .NET Test Runner"
echo "========================================================"
info "Repository root : ${REPO_ROOT}"
info "Coverage        : ${COVERAGE}"

# ---------------------------------------------------------------------------
# Verify .NET SDK is available
# ---------------------------------------------------------------------------
step "Checking for .NET SDK..."
if ! command -v dotnet >/dev/null 2>&1; then
  die ".NET SDK not found. Install it from https://dot.net/download and try again."
fi
DOTNET_VERSION="$(dotnet --version)"
info "dotnet ${DOTNET_VERSION} found."

# ---------------------------------------------------------------------------
# Test projects to run
# ---------------------------------------------------------------------------
TEST_PROJECTS=(
  "function-app.tests/FunctionApp.Tests.csproj"
  "web-app.tests/WebApp.Tests.csproj"
)

# ---------------------------------------------------------------------------
# Build all test projects first so failures surface early
# ---------------------------------------------------------------------------
step "Restoring and building all test projects..."
for proj in "${TEST_PROJECTS[@]}"; do
  proj_path="${REPO_ROOT}/${proj}"
  if [ ! -f "${proj_path}" ]; then
    die "Test project not found: ${proj_path}"
  fi
  info "Building ${proj}..."
  dotnet build "${proj_path}" --configuration Release --nologo --verbosity quiet
done
info "All test projects built successfully."

# ---------------------------------------------------------------------------
# Run tests
# ---------------------------------------------------------------------------
FAILED_PROJECTS=()

COVERAGE_DIR="/tmp/coverage"
if [ "${COVERAGE}" = true ]; then
  rm -rf "${COVERAGE_DIR}"
  mkdir -p "${COVERAGE_DIR}"
  info "Coverage reports will be written to ${COVERAGE_DIR}."
fi

for proj in "${TEST_PROJECTS[@]}"; do
  proj_path="${REPO_ROOT}/${proj}"
  proj_name="$(basename "$(dirname "${proj_path}")")"

  step "Running tests: ${proj_name}..."

  if [ "${COVERAGE}" = true ]; then
    dotnet test "${proj_path}" \
      --configuration Release \
      --no-build \
      --nologo \
      --logger "console;verbosity=normal" \
      --collect:"XPlat Code Coverage" \
      --results-directory "${COVERAGE_DIR}/${proj_name}" \
      || FAILED_PROJECTS+=("${proj_name}")
  else
    dotnet test "${proj_path}" \
      --configuration Release \
      --no-build \
      --nologo \
      --logger "console;verbosity=normal" \
      || FAILED_PROJECTS+=("${proj_name}")
  fi
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "========================================================"
if [ "${#FAILED_PROJECTS[@]}" -eq 0 ]; then
  info "✅  All test suites passed."
else
  error "❌  The following test suites FAILED:"
  for name in "${FAILED_PROJECTS[@]}"; do
    error "    - ${name}"
  done
  exit 1
fi
echo "========================================================"
