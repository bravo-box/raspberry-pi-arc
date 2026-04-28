# rpi-app — Raspberry Pi Camera Application

A Python/Flask container application that interfaces with the camera module on a
Raspberry Pi running Raspberry Pi OS (Raspbian).

## Features

| Endpoint    | Description                          |
|-------------|--------------------------------------|
| `/`         | Web UI with live stream              |
| `/capture`  | Return a single JPEG snapshot        |
| `/stream`   | MJPEG live stream                    |
| `/health`   | JSON health/readiness probe          |

## Prerequisites

- Raspberry Pi with an attached Camera Module (v1, v2, or HQ)
- Raspberry Pi OS (64-bit recommended)
- Docker Engine ≥ 24 and Docker Compose v2 (`docker compose`)
- Camera interface enabled:
  ```bash
  sudo raspi-config nonint do_camera 0
  ```

## Quick Start

### 1 — Enable the camera interface (if not already done)

```bash
sudo raspi-config
# Interface Options → Camera → Enable
```

### 2 — Install Docker

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
# Log out and back in for the group change to take effect
```

### 3 — Build and run the container

```bash
cd rpi-app
docker compose up -d
```

The application will be available at `http://<pi-ip-address>:5000`.

### 4 — View logs

```bash
docker compose logs -f rpi-camera-app
```

### 5 — Stop the application

```bash
docker compose down
```

## Accessing the web UI from Kubernetes

When deployed to a Kubernetes cluster, the application is exposed via a NodePort service on port `30500`.

### Get the cluster node IP

```bash
# Get the node IP of your cluster
kubectl get nodes -o wide

# Get the InternalIP address directly (most common for local clusters)
kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}'
```

### Access the web UI

Once you have the node IP, access the application at:

```
http://<node-ip>:30500
```

For example, if your node IP is `192.168.1.100`:

```
http://192.168.1.100:30500
```

You can now view the live camera stream, capture snapshots, and check the health status from outside the cluster.

## Running without Docker (development)

```bash
cd rpi-app
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python app.py
```

## Configuration

| Variable     | Default      | Description              |
|--------------|--------------|--------------------------|
| `FLASK_ENV`  | `production` | Flask environment        |

## Architecture Notes

- Uses [`picamera2`](https://github.com/raspberrypi/picamera2) (libcamera backend),
  which supports all current Camera Module generations.
- The container needs access to the `/dev/video0` device and membership of the
  `video` group — both are configured in `docker-compose.yml`.
- The application falls back gracefully when no camera hardware is detected so
  the `/health` endpoint always responds (useful for CI/integration testing).
