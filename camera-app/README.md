# camera-app

A three-container Kubernetes pod that integrates with the Raspberry Pi camera and
Azure services.  It is deployed alongside the existing `log-writer` workload in
the `raspberry-pi-arc-demo` namespace.

---

## Architecture

```
┌────────────────────────────────────────────────────────────────┐
│  Pod: camera-app                                               │
│                                                                │
│  ┌─────────────────────┐  ┌─────────────────────┐            │
│  │  camera-service     │  │  file-service        │            │
│  │                     │  │                      │            │
│  │  Subscribes to      │  │  Polls /outbox for   │            │
│  │  'TaskCamera'       │  │  complete files,     │            │
│  │  Service Bus topic  │  │  uploads to Azure    │            │
│  │                     │  │  Blob Storage, and   │            │
│  │  Captures JPEG via  │  │  publishes to        │            │
│  │  picamera2 →        │  │  'photo-upload'      │            │
│  │  saves to /outbox   │  │  Service Bus topic.  │            │
│  └─────────┬───────────┘  └──────────┬───────────┘            │
│            │   shared emptyDir        │                        │
│            └──────── /outbox ─────────┘                        │
│                                                                │
│  ┌──────────────────────────────────────────┐                 │
│  │  registration-service                    │                 │
│  │                                          │                 │
│  │  On first boot: publishes hostname to    │                 │
│  │  'register-device' topic, receives back  │                 │
│  │  an assigned GUID and saves it to        │                 │
│  │  /config/device-registration.json.       │                 │
│  │                                          │                 │
│  │  Every 30 s: publishes a health-check    │                 │
│  │  heartbeat to the 'health-check' topic   │                 │
│  │  with network status, disk space, and    │                 │
│  │  an overall Green / Yellow / Red status. │                 │
│  └──────────────────────────────────────────┘                 │
│                                                                │
│  All containers mount /config (writable emptyDir seeded by    │
│  an initContainer from the camera-app-config Secret).         │
└────────────────────────────────────────────────────────────────┘
```

### Service Bus topics

| Topic               | Direction                  | Description                                                   |
|---------------------|----------------------------|---------------------------------------------------------------|
| `TaskCamera`        | → camera-service           | Triggers a photo capture                                      |
| `photo-upload`      | file-service →             | Notification containing upload metadata                       |
| `photo-processed`   | → file-service             | Acknowledgement that triggers local file deletion             |
| `register-device`   | registration-service →     | First-boot registration request containing the hostname       |
| `device-registered` | → registration-service     | Cloud response containing hostname and assigned device GUID   |
| `health-check`      | registration-service →     | 30-second heartbeat with network/disk/status telemetry        |

You must create these topics **and** the required subscriptions in your Azure
Service Bus namespace before deploying:

```bash
# TaskCamera topic + subscription for camera-service
az servicebus topic create  --name TaskCamera         --namespace-name <ns> --resource-group <rg>
az servicebus topic subscription create \
    --name camera-service --topic-name TaskCamera     --namespace-name <ns> --resource-group <rg>

# photo-upload topic (no subscription needed – file-service is the sender)
az servicebus topic create  --name photo-upload       --namespace-name <ns> --resource-group <rg>

# photo-processed topic + subscription for file-service ack listener
az servicebus topic create  --name photo-processed    --namespace-name <ns> --resource-group <rg>
az servicebus topic subscription create \
    --name file-service --topic-name photo-processed  --namespace-name <ns> --resource-group <rg>

# register-device topic + subscription for the cloud RegisterDeviceFunction
az servicebus topic create  --name register-device    --namespace-name <ns> --resource-group <rg>
az servicebus topic subscription create \
    --name registration-function --topic-name register-device --namespace-name <ns> --resource-group <rg>

# device-registered topic + subscription for the Pi's registration-service
az servicebus topic create  --name device-registered  --namespace-name <ns> --resource-group <rg>
az servicebus topic subscription create \
    --name registration-service --topic-name device-registered --namespace-name <ns> --resource-group <rg>

# health-check topic + subscription for the cloud HealthCheckFunction
az servicebus topic create  --name health-check       --namespace-name <ns> --resource-group <rg>
az servicebus topic subscription create \
    --name health-function --topic-name health-check  --namespace-name <ns> --resource-group <rg>
```

---

## Configuration

All services read `/config/config.json` which is populated at pod start from a
Kubernetes Secret.  Use `config.json.template` as a starting point:

```json
{
  "service_bus_namespace": "<your-servicebus-namespace>",
  "tenant_id":             "<your-azure-tenant-id>",
  "client_id":             "<your-service-principal-client-id>",
  "client_secret":         "<your-service-principal-client-secret>",
  "storage_account_name":  "<your-storage-account-name>",
  "storage_container_name":"<your-blob-container-name>"
}
```

Create the Kubernetes Secret from your filled-in config file:

```bash
kubectl create secret generic camera-app-config \
  --from-file=config.json=/path/to/your/config.json \
  -n raspberry-pi-arc-demo
```

### Device registration file

After successful first-boot registration the `registration-service` writes
`/config/device-registration.json`:

```json
{
  "device_id": "<uuid-assigned-by-cloud>",
  "hostname":  "<device-hostname>"
}
```

This file is used by subsequent health-check messages.  It persists across
container restarts as long as the pod is not deleted (emptyDir lifetime).

---

## Building the images

Build and import all three images into k3s on the Raspberry Pi:

```bash
# camera-service
docker build -t camera-service:latest camera-app/camera-service/
docker save camera-service:latest | sudo k3s ctr images import -

# file-service
docker build -t file-service:latest  camera-app/file-service/
docker save file-service:latest  | sudo k3s ctr images import -

# registration-service
docker build -t registration-service:latest camera-app/registration-service/
docker save registration-service:latest | sudo k3s ctr images import -
```

---

## Deploying with kubectl

```bash
# Apply all manifests (log-writer + camera-app) via kustomize
sudo kubectl apply -k k8s/

# Watch the camera-app pod come up
sudo kubectl -n raspberry-pi-arc-demo get pods -w

# Follow logs for each container
sudo kubectl -n raspberry-pi-arc-demo logs -f deployment/camera-app -c camera-service
sudo kubectl -n raspberry-pi-arc-demo logs -f deployment/camera-app -c file-service
sudo kubectl -n raspberry-pi-arc-demo logs -f deployment/camera-app -c registration-service
```

## Deploying with Helm

A Helm chart is provided under `camera-app/helm/`:

```bash
# Render and apply with defaults
helm upgrade --install camera-app camera-app/helm/ \
  --namespace raspberry-pi-arc-demo \
  --create-namespace

# Override image repositories (e.g. for a private registry)
helm upgrade --install camera-app camera-app/helm/ \
  --set images.cameraService.repository=myregistry.azurecr.io/camera-service \
  --set images.fileService.repository=myregistry.azurecr.io/file-service \
  --set images.registrationService.repository=myregistry.azurecr.io/registration-service \
  --namespace raspberry-pi-arc-demo
```

---

## Triggering a capture

Send a message to the `TaskCamera` topic (the body content is ignored – the
presence of a message is the trigger):

```bash
az servicebus topic message send \
  --namespace-name <ns> \
  --resource-group <rg> \
  --topic-name TaskCamera \
  --body '{"action":"capture"}'
```

The camera-service will capture a JPEG, save it to `/outbox`, and the
file-service will pick it up, upload it to Blob Storage, and publish a
notification to the `photo-upload` topic.

---

## Acknowledging an upload

To trigger local file deletion, publish a message to the `photo-processed`
topic with the `file_name` field matching the uploaded blob name:

```bash
az servicebus topic message send \
  --namespace-name <ns> \
  --resource-group <rg> \
  --topic-name photo-processed \
  --body '{"file_name":"<hostname>_<timestamp>.jpg"}'
```

---

## Health-check message schema

The registration-service publishes the following JSON payload to the
`health-check` topic every 30 seconds:

```json
{
  "device_id":        "<uuid>",
  "hostname":         "<hostname>",
  "network_status":   "connected | degraded | disabled",
  "disk_total_gb":    32.0,
  "disk_used_gb":     10.5,
  "disk_free_gb":     21.5,
  "disk_free_percent": 67.19,
  "status":           "Green | Yellow | Red",
  "timestamp":        "2024-01-01T12:00:00.000000+00:00"
}
```

| Status   | Condition                                                        |
|----------|------------------------------------------------------------------|
| `Green`  | Network connected **and** free disk ≥ 50 %                      |
| `Yellow` | Free disk < 50 % **or** network degraded (but not already Red)  |
| `Red`    | Network disabled **or** free disk < 25 %                        |

---

## Camera device notes

The `camera-app-deployment.yaml` mounts `/dev/video0` and `/dev/media0` from
the host.  If your Raspberry Pi hardware exposes additional device nodes
(e.g. `/dev/media1`, `/dev/video1`) you may need to add corresponding
`hostPath` volumes and `volumeMounts` entries.
