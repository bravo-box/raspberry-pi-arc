# camera-app

A two-container Kubernetes pod that integrates with the Raspberry Pi camera and
Azure services.  It is deployed alongside the existing `log-writer` workload in
the `raspberry-pi-arc-demo` namespace.

---

## Architecture

```
┌──────────────────────────────────────────────────────┐
│  Pod: camera-app                                     │
│                                                      │
│  ┌─────────────────────┐  ┌─────────────────────┐  │
│  │  camera-service     │  │  file-service        │  │
│  │                     │  │                      │  │
│  │  Subscribes to      │  │  Polls /outbox for   │  │
│  │  'TaskCamera'       │  │  complete files,     │  │
│  │  Service Bus topic  │  │  uploads to Azure    │  │
│  │                     │  │  Blob Storage, and   │  │
│  │  Captures JPEG via  │  │  publishes to        │  │
│  │  picamera2 →        │  │  'photo-upload'      │  │
│  │  saves to /outbox   │  │  Service Bus topic.  │  │
│  └─────────┬───────────┘  └──────────┬───────────┘  │
│            │   shared emptyDir        │              │
│            └──────── /outbox ─────────┘              │
│                                                      │
│  Both containers mount /config (read-only Secret)    │
└──────────────────────────────────────────────────────┘
```

### Service Bus topics

| Topic             | Direction       | Description                                        |
|-------------------|-----------------|----------------------------------------------------|
| `TaskCamera`      | → camera-service | Triggers a photo capture                           |
| `photo-upload`    | file-service →   | Notification containing upload metadata            |
| `photo-processed` | → file-service   | Acknowledgement that triggers local file deletion  |

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
```

---

## Configuration

Both services read `/config/config.json` which is mounted from a Kubernetes
Secret.  Use `config.json.template` as a starting point:

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

---

## Building the images

Build and import both images into k3s on the Raspberry Pi:

```bash
# camera-service
docker build -t camera-service:latest camera-app/camera-service/
docker save camera-service:latest | sudo k3s ctr images import -

# file-service
docker build -t file-service:latest  camera-app/file-service/
docker save file-service:latest  | sudo k3s ctr images import -
```

---

## Deploying

```bash
# Apply all manifests (log-writer + camera-app) via kustomize
sudo kubectl apply -k k8s/

# Watch the camera-app pod come up
sudo kubectl -n raspberry-pi-arc-demo get pods -w

# Follow logs for each container
sudo kubectl -n raspberry-pi-arc-demo logs -f deployment/camera-app -c camera-service
sudo kubectl -n raspberry-pi-arc-demo logs -f deployment/camera-app -c file-service
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

## Camera device notes

The `camera-app-deployment.yaml` mounts `/dev/video0` and `/dev/media0` from
the host.  If your Raspberry Pi hardware exposes additional device nodes
(e.g. `/dev/media1`, `/dev/video1`) you may need to add corresponding
`hostPath` volumes and `volumeMounts` entries.

The container runs with supplemental GID `44` (the `video` group on most
Raspberry Pi OS / Ubuntu ARM images) so that libcamera can open the device
files without requiring a privileged container.
