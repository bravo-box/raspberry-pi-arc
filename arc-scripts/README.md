# arc-scripts — Azure Arc Configuration for Raspberry Pi

Scripts for onboarding a Raspberry Pi (running Raspberry Pi OS / Raspbian) as an
**Azure Arc-enabled server** connected to the **Azure Government** cloud.

## Script overview

| Script              | Description                                                  |
|---------------------|--------------------------------------------------------------|
| `configure-arc.sh`  | Installs the Azure Connected Machine agent and connects the Pi to Azure Arc (Azure Government) |

## Prerequisites

### On Azure Government

1. **Subscription** in Azure Government ([portal.azure.us](https://portal.azure.us)).
2. **Resource Group** in a supported Government region:
   - `usgovvirginia`
   - `usgovarizona`
   - `usgovtexas`
3. **Service Principal** with the *Azure Connected Machine Onboarding* role:

```bash
# Using Azure CLI pointed at the Government cloud
az cloud set --name AzureUSGovernment
az login

az ad sp create-for-rbac \
  --name "arc-rpi-onboarding" \
  --role "Azure Connected Machine Onboarding" \
  --scopes "/subscriptions/<SUBSCRIPTION_ID>/resourceGroups/<RESOURCE_GROUP>"
```

Save the `appId` (client ID) and `password` (client secret) returned — you will
need them when running the script.

### On the Raspberry Pi

- Raspberry Pi OS (bookworm or bullseye, 64-bit or 32-bit armhf)
- Internet access (outbound HTTPS to `*.gov` Azure endpoints)
- `sudo` / root access

## Usage

### 1 — Copy the script to the Pi

```bash
scp arc-scripts/configure-arc.sh pi@<pi-ip-address>:~/
```

### 2 — Run the script

```bash
ssh pi@<pi-ip-address>

sudo ./configure-arc.sh \
  --subscription-id          <AZURE_GOV_SUBSCRIPTION_ID>  \
  --resource-group           <RESOURCE_GROUP_NAME>         \
  --location                 usgovvirginia                  \
  --tenant-id                <AZURE_AD_TENANT_ID>          \
  --service-principal-id     <SP_APP_ID>                   \
  --service-principal-secret <SP_PASSWORD>
```

Optional flags:

| Flag              | Description                                  | Default         |
|-------------------|----------------------------------------------|-----------------|
| `--resource-name` | Azure resource name for this Pi              | System hostname |
| `--tags`          | Comma-separated `key=value` resource tags    | _(none)_        |

### 3 — Verify in the portal

After a successful run, navigate to **Azure Government Portal → Azure Arc → Machines**
and confirm the device appears with status **Connected**.

## What the script does

1. Checks it is running as `root` on a Debian-based OS.
2. Installs prerequisite packages (`curl`, `gnupg`, `ca-certificates`, …).
3. Downloads and installs the **Azure Connected Machine agent** (`azcmagent`) from
   the official Microsoft install script — the script auto-detects `arm64` / `armhf`
   architectures used by Raspberry Pi hardware.
4. Runs `azcmagent connect` targeting `--cloud AzureUSGovernment`.
5. Runs `azcmagent show` to verify the connection.

## Disconnecting / offboarding

```bash
sudo azcmagent disconnect
```

## Troubleshooting

| Symptom                       | Resolution                                                      |
|-------------------------------|-----------------------------------------------------------------|
| Agent install fails           | Ensure the Pi has internet access to `aka.ms`                   |
| `azcmagent connect` 401 error | Verify the service principal credentials and role assignment    |
| Status shows *Disconnected*   | Check outbound connectivity to `*management.usgovcloudapi.net`  |
| Wrong region error            | Use a Government region: `usgovvirginia`, `usgovarizona`, etc.  |

### Agent logs

```bash
sudo azcmagent logs        # collect a support bundle
journalctl -u himds -f     # follow the agent service log
```
