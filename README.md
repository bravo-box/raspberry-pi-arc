# raspberry-pi-arc

Demo project for deploying a Python log generator to a Raspberry Pi (Raspbian) on k3s, and managing/log-aggregating it through Azure Arc-enabled Kubernetes.

## What this repository provides

- Python app that continuously writes JSON logs to:
  - stdout (for container logs)
  - `/app/logs/demo.log` inside the container
- Container image suitable for Raspberry Pi platforms (build on Pi, or build multi-arch externally)
- k3s Kubernetes deployment with a hostPath mount:
  - Container path: `/app/logs`
  - Host path: `/var/lib/raspberry-pi-arc/logs`
- Script to install/bootstrap k3s and deploy the containerized app
- Script to onboard k3s to Azure Arc and install Azure Monitor containers extension
- Script to configure Arc GitOps (Flux) automated deployments from this repository
- Script to setup registry replication between k3s local registry and Azure Container Registry (ACR)
- GitHub Actions workflow to automate Arc onboarding + GitOps deployment

## Prerequisites (Raspbian)

- Raspberry Pi running Raspbian (64-bit recommended)
- `curl`, `docker`, `sudo`
- Azure CLI (`az`) for Arc onboarding scripts
- Azure subscription with permissions to create/manage Arc resources

## Local cluster bootstrap + deployment

From repo root on the Raspberry Pi:

```bash
chmod +x scripts/*.sh

# Install Docker
./scripts/install_docker_01_setup_repository.sh
./scripts/install_docker_02_install.sh
./scripts/install_docker_03_verify.sh

# Bootstrap k3s and deploy the app
./scripts/bootstrap_k3s_and_deploy.sh
```

This will:

1. Set up Docker repository
2. Install Docker
3. Verify Docker installation
4. Install k3s (if missing)
5. Build container image `raspberry-pi-arc-demo:latest`
6. Import image into k3s containerd
7. Deploy manifests from `k8s/`

Verify logs on host:

```bash
sudo tail -f /var/lib/raspberry-pi-arc/logs/demo.log
```

## Azure Arc onboarding + log aggregation

Set environment variables and run:

```bash
export RESOURCE_GROUP="<rg>"
export CLUSTER_NAME="<arc-cluster-name>"
export LOCATION="<azure-region>"
export SUBSCRIPTION_ID="<subscription-id>"

./scripts/setup_arc_k8s.sh
```

The script connects k3s as an Arc-enabled Kubernetes cluster and installs `Microsoft.AzureMonitor.Containers` extension so logs can be aggregated in Azure Monitor.

## Arc-based automated deployment (GitOps)

```bash
export CLOUD=AzureUSGovernment
export RESOURCE_GROUP="<rg>"
export CLUSTER_NAME="<arc-cluster-name>"
export GIT_REPO_URL="https://github.com/bravo-box/raspberry-pi-arc.git"
export GIT_BRANCH="main"
export MANIFEST_PATH="./k8s"

./scripts/arc_gitops_deploy.sh
```

This configures Arc Flux GitOps so future manifest updates are deployed automatically to the Raspberry Pi cluster.

## Container Registry replication (k3s to Azure Container Registry)

Registry replication enables automatic synchronization of container images between the local k3s registry and Azure Container Registry (ACR). This is useful for:

- **Air-gapped environments**: Push images to the local k3s registry; replication handles pushing to ACR
- **Bandwidth optimization**: Build images locally, replicate only what's needed
- **Centralized image management**: Maintain a central ACR repository for governance and scanning
- **Multi-cluster deployments**: Share images across multiple Arc-enabled clusters via ACR

### Setup registry replication

First, ensure your cluster is Arc-enabled by running `setup_arc_k8s.sh` (see above).

Then, set environment variables and run:

```bash
export RESOURCE_GROUP="<rg>"
export CLUSTER_NAME="<arc-cluster-name>"
export LOCATION="<azure-region>"  # e.g., usgovvirginia, usgoviowa
export ACR_NAME="<acr-name>"      # e.g., myacr (DNS-safe, lowercase only)
export SUBSCRIPTION_ID="<subscription-id>"
export CLOUD=AzureUSGovernment

./scripts/setup-registry-replication.sh
```

The script will:

1. Create Azure Container Registry (ACR) if it doesn't exist
2. Create a service principal with push/pull permissions
3. Configure k3s registry mirroring to ACR
4. Create Kubernetes secrets for authentication
5. Validate connectivity to ACR

### Using registry replication

**Push an image to the local k3s registry:**

```bash
docker build -t localhost:5000/my-app:latest .
docker push localhost:5000/my-app:latest
```

**Verify image appears in ACR:**

```bash
# List repositories in ACR
az acr repository list --name <ACR_NAME>

# List tags for a repository
az acr repository show-tags --name <ACR_NAME> --repository my-app
```

**View k3s replication logs:**

```bash
kubectl logs -f -n arc-registry-replication -l app=registry
```

**Pull images from ACR in your cluster:**

```bash
# Update deployment to pull from ACR
kubectl set image deployment/my-app my-app=<ACR_LOGIN_SERVER>/my-app:latest
```

## GitHub Actions automation

Workflow: `.github/workflows/arc-gitops-deploy.yml`

Required repository secrets:

- `AZURE_CREDENTIALS`
- `AZURE_SUBSCRIPTION_ID`
- `ARC_RESOURCE_GROUP`
- `ARC_CLUSTER_NAME`
- `ARC_LOCATION`

Trigger via **Actions** → **arc-gitops-deploy** → **Run workflow**.
