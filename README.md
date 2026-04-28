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
./scripts/bootstrap_k3s_and_deploy.sh
```

This will:

1. Install k3s (if missing)
2. Build container image `raspberry-pi-arc-demo:latest`
3. Import image into k3s containerd
4. Deploy manifests from `k8s/`

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
export RESOURCE_GROUP="<rg>"
export CLUSTER_NAME="<arc-cluster-name>"
export GIT_REPO_URL="https://github.com/bravo-box/raspberry-pi-arc.git"
export GIT_BRANCH="main"
export MANIFEST_PATH="./k8s"

./scripts/arc_gitops_deploy.sh
```

This configures Arc Flux GitOps so future manifest updates are deployed automatically to the Raspberry Pi cluster.

## GitHub Actions automation

Workflow: `.github/workflows/arc-gitops-deploy.yml`

Required repository secrets:

- `AZURE_CREDENTIALS`
- `AZURE_SUBSCRIPTION_ID`
- `ARC_RESOURCE_GROUP`
- `ARC_CLUSTER_NAME`
- `ARC_LOCATION`

Trigger via **Actions** → **arc-gitops-deploy** → **Run workflow**.
