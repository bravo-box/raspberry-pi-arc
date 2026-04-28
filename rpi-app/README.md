# rpi-app — Raspberry Pi Camera & Temperature Sensor Application

A Python/Flask container application that interfaces with the camera module and
a DS18B20 temperature sensor on a Raspberry Pi running Raspberry Pi OS (Raspbian).
Temperature readings are published to an MQTT broker so they can be consumed by
any cloud application.

## Features

| Endpoint       | Description                                      |
|----------------|--------------------------------------------------|
| `/`            | Web UI with live stream and current temperature  |
| `/capture`     | Return a single JPEG snapshot                    |
| `/stream`      | MJPEG live stream                                |
| `/temperature` | JSON with the latest temperature reading         |
| `/health`      | JSON health/readiness probe                      |

## Prerequisites

- Raspberry Pi with an attached Camera Module (v1, v2, or HQ)
- DS18B20 temperature sensor wired to GPIO4 (1-Wire default pin)
- Raspberry Pi OS (64-bit recommended)
- Docker Engine ≥ 24 and Docker Compose v2 (`docker compose`)
- Camera interface enabled:
  ```bash
  sudo raspi-config nonint do_camera 0
  ```
- 1-Wire interface enabled (add to `/boot/config.txt` or use `raspi-config`):
  ```
  dtoverlay=w1-gpio
  ```

## Quick Start

### 1 — Enable the camera and 1-Wire interfaces (if not already done)

```bash
sudo raspi-config
# Interface Options → Camera → Enable
# Interface Options → 1-Wire → Enable
```

### 2 — Install Docker

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
# Log out and back in for the group change to take effect
```

### 3 — Configure MQTT (optional but recommended)

Create a `.env` file in the `rpi-app` directory:

```env
MQTT_BROKER=<your-broker-host>
MQTT_PORT=1883
MQTT_TOPIC=rpi/temperature
MQTT_CLIENT_ID=rpi-camera-app
TEMP_INTERVAL=30
```

Leave the file out (or keep defaults) to disable MQTT publishing while still
exposing the `/temperature` REST endpoint locally.

### 4 — Build and run the container

```bash
cd rpi-app
docker compose up -d
```

The application will be available at `http://<pi-ip-address>:5000`.

### 5 — View logs

```bash
docker compose logs -f rpi-camera-app
```

### 6 — Stop the application

```bash
docker compose down
```

## Running without Docker (development)

```bash
cd rpi-app
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python app.py
```

## Configuration

| Variable        | Default          | Description                                        |
|-----------------|------------------|----------------------------------------------------|
| `FLASK_ENV`     | `production`     | Flask environment                                  |
| `MQTT_BROKER`   | `localhost`      | Hostname or IP of the MQTT broker                  |
| `MQTT_PORT`     | `1883`           | TCP port of the MQTT broker                        |
| `MQTT_TOPIC`    | `rpi/temperature`| MQTT topic used for temperature publications       |
| `MQTT_CLIENT_ID`| `rpi-camera-app` | MQTT client identifier                             |
| `TEMP_INTERVAL` | `30`             | Seconds between temperature reads and publications |

## MQTT Payload

Each published message is a JSON object:

```json
{
  "temperature_c": 22.50,
  "temperature_f": 72.50,
  "unit": "celsius",
  "timestamp": "2024-01-15T12:34:56.789012+00:00"
}
```

## Architecture Notes

- Uses [`picamera2`](https://github.com/raspberrypi/picamera2) (libcamera backend),
  which supports all current Camera Module generations.
- Uses [`w1thermsensor`](https://github.com/timofurrer/w1thermsensor) to read from
  a DS18B20 sensor over the Linux 1-Wire sysfs interface
  (`/sys/bus/w1/devices/28-*/`).
- Uses [`paho-mqtt`](https://github.com/eclipse/paho.mqtt.python) to publish
  temperature readings to any MQTT v3.1.1-compatible broker (Mosquitto, Azure
  IoT Hub, AWS IoT Core, HiveMQ, etc.).
- The container needs access to the `/dev/video0` device and membership of the
  `video` group — both are configured in `docker-compose.yml`.
- The 1-Wire sysfs tree (`/sys/bus/w1`) is bind-mounted read-only into the
  container so sensor files are accessible without running as root.
- Both the camera and the temperature sensor fall back gracefully when the
  hardware is absent, so the `/health` endpoint always responds (useful for
  CI/integration testing).
- A background daemon thread reads the sensor every `TEMP_INTERVAL` seconds and
  publishes results over MQTT; the latest reading is also cached and served via
  the `/temperature` REST endpoint.
