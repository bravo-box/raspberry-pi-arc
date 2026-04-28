import io
import json
import logging
import os
import threading
import time
from datetime import datetime, timezone

from flask import Flask, Response, jsonify, render_template_string

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ── Camera initialisation ──────────────────────────────────────────────────────
# Try to import picamera2; fall back gracefully when not running on a Pi
try:
    from picamera2 import Picamera2

    camera = Picamera2()
    camera_config = camera.create_still_configuration(
        main={"size": (1920, 1080)},
        lores={"size": (640, 480)},
        display="lores",
    )
    camera.configure(camera_config)
    camera.start()
    time.sleep(2)  # Allow the camera to warm up
    CAMERA_AVAILABLE = True
    logger.info("Picamera2 initialised successfully.")
except Exception as exc:  # pylint: disable=broad-except
    CAMERA_AVAILABLE = False
    logger.warning("Camera not available: %s", exc)

# ── Temperature sensor initialisation ─────────────────────────────────────────
# Supports DS18B20 via the Linux 1-Wire subsystem.  The sensor is optional;
# the application falls back gracefully when the hardware is absent.
try:
    from w1thermsensor import W1ThermSensor, W1ThermSensorError

    _temp_sensor = W1ThermSensor()
    TEMP_AVAILABLE = True
    logger.info("DS18B20 temperature sensor detected.")
except Exception as exc:  # pylint: disable=broad-except
    _temp_sensor = None
    TEMP_AVAILABLE = False
    logger.warning("Temperature sensor not available: %s", exc)

# Current cached reading (updated by background thread)
_current_temp_celsius: float | None = None
_temp_lock = threading.Lock()

# ── MQTT configuration ─────────────────────────────────────────────────────────
MQTT_BROKER = os.environ.get("MQTT_BROKER", "localhost")
MQTT_PORT = int(os.environ.get("MQTT_PORT", "1883"))
MQTT_TOPIC = os.environ.get("MQTT_TOPIC", "rpi/temperature")
MQTT_CLIENT_ID = os.environ.get("MQTT_CLIENT_ID", "rpi-camera-app")
TEMP_INTERVAL = int(os.environ.get("TEMP_INTERVAL", "30"))

try:
    import paho.mqtt.client as mqtt

    _mqtt_client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id=MQTT_CLIENT_ID)
    _mqtt_client.connect(MQTT_BROKER, MQTT_PORT, keepalive=60)
    _mqtt_client.loop_start()
    MQTT_AVAILABLE = True
    logger.info("MQTT client connected to %s:%d", MQTT_BROKER, MQTT_PORT)
except Exception as exc:  # pylint: disable=broad-except
    _mqtt_client = None
    MQTT_AVAILABLE = False
    logger.warning("MQTT not available (broker=%s:%d): %s", MQTT_BROKER, MQTT_PORT, exc)

# ── HTML template ──────────────────────────────────────────────────────────────
INDEX_HTML = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Raspberry Pi Camera</title>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; background: #1a1a2e; color: #eee; margin: 0; padding: 20px; }
        h1 { color: #e94560; }
        img { max-width: 100%; border: 3px solid #e94560; border-radius: 8px; margin: 20px auto; display: block; }
        .btn { display: inline-block; margin: 10px; padding: 12px 24px; background: #e94560;
               color: #fff; text-decoration: none; border-radius: 6px; font-size: 1rem; }
        .btn:hover { background: #c73652; }
        .status { padding: 8px 16px; border-radius: 4px; display: inline-block; margin: 8px; }
        .ok { background: #2ecc71; color: #000; }
        .error { background: #e74c3c; }
        .temp-box { display: inline-block; margin: 16px; padding: 16px 32px;
                    background: #16213e; border: 2px solid #e94560; border-radius: 8px; }
        .temp-value { font-size: 2rem; font-weight: bold; color: #e94560; }
    </style>
</head>
<body>
    <h1>&#127909; Raspberry Pi Camera</h1>
    <span class="status {{ 'ok' if camera_available else 'error' }}">
        Camera: {{ 'Online' if camera_available else 'Unavailable' }}
    </span>
    <span class="status {{ 'ok' if temp_available else 'error' }}">
        Temperature Sensor: {{ 'Online' if temp_available else 'Unavailable' }}
    </span>
    {% if temp_available and temperature is not none %}
    <div class="temp-box">
        <div>&#127777; Current Temperature</div>
        <div class="temp-value">{{ "%.1f"|format(temperature) }}&nbsp;&deg;C</div>
    </div>
    {% endif %}
    {% if camera_available %}
    <br/>
    <a class="btn" href="/capture">&#128247; Capture Snapshot</a>
    <a class="btn" href="/stream">&#9654; Live Stream</a>
    {% endif %}
    <a class="btn" href="/temperature">&#127777; Temperature</a>
    <a class="btn" href="/health">&#10004; Health Check</a>
    {% if camera_available %}
    <div>
        <img src="/stream" alt="Live camera feed" />
    </div>
    {% endif %}
</body>
</html>
"""


# ── Helper functions ───────────────────────────────────────────────────────────

def _read_temperature() -> float | None:
    """Read current temperature in Celsius from the DS18B20 sensor."""
    if not TEMP_AVAILABLE or _temp_sensor is None:
        return None
    try:
        return _temp_sensor.get_temperature()
    except Exception as exc:  # pylint: disable=broad-except
        logger.warning("Temperature read error: %s", exc)
        return None


def _publish_temperature(temp_celsius: float) -> None:
    """Publish a temperature reading to the MQTT broker."""
    if not MQTT_AVAILABLE or _mqtt_client is None:
        return
    payload = json.dumps(
        {
            "temperature_c": round(temp_celsius, 2),
            "temperature_f": round(temp_celsius * 9 / 5 + 32, 2),
            "unit": "celsius",
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
    )
    try:
        _mqtt_client.publish(MQTT_TOPIC, payload, qos=1)
        logger.debug("Published temperature %.2f°C to %s", temp_celsius, MQTT_TOPIC)
    except Exception as exc:  # pylint: disable=broad-except
        logger.warning("MQTT publish error: %s", exc)


def _temperature_loop() -> None:
    """Background thread: read temperature and publish on a fixed interval."""
    global _current_temp_celsius  # pylint: disable=global-statement
    while True:
        temp = _read_temperature()
        if temp is not None:
            with _temp_lock:
                _current_temp_celsius = temp
            _publish_temperature(temp)
            logger.info("Temperature: %.2f°C", temp)
        time.sleep(TEMP_INTERVAL)


def _capture_jpeg() -> bytes:
    """Capture a JPEG image from the camera and return raw bytes."""
    stream = io.BytesIO()
    camera.capture_file(stream, format="jpeg")
    stream.seek(0)
    return stream.read()


def _generate_mjpeg():
    """Yield MJPEG frames for a continuous stream."""
    while True:
        frame = _capture_jpeg()
        yield (
            b"--frame\r\n"
            b"Content-Type: image/jpeg\r\n\r\n" + frame + b"\r\n"
        )
        time.sleep(0.1)  # ~10 fps


# ── Background threads ─────────────────────────────────────────────────────────

if TEMP_AVAILABLE:
    _temp_thread = threading.Thread(target=_temperature_loop, daemon=True, name="temp-publisher")
    _temp_thread.start()
    logger.info("Temperature publisher started (interval=%ds, topic=%s)", TEMP_INTERVAL, MQTT_TOPIC)

# ── Routes ─────────────────────────────────────────────────────────────────────

@app.route("/")
def index():
    with _temp_lock:
        temp = _current_temp_celsius
    return render_template_string(
        INDEX_HTML,
        camera_available=CAMERA_AVAILABLE,
        temp_available=TEMP_AVAILABLE,
        temperature=temp,
    )


@app.route("/capture")
def capture():
    """Return a single JPEG snapshot."""
    if not CAMERA_AVAILABLE:
        return jsonify({"error": "Camera not available"}), 503
    frame = _capture_jpeg()
    return Response(frame, mimetype="image/jpeg")


@app.route("/stream")
def stream():
    """Return an MJPEG stream."""
    if not CAMERA_AVAILABLE:
        return jsonify({"error": "Camera not available"}), 503
    return Response(
        _generate_mjpeg(),
        mimetype="multipart/x-mixed-replace; boundary=frame",
    )


@app.route("/temperature")
def temperature():
    """Return the latest temperature reading as JSON."""
    with _temp_lock:
        temp = _current_temp_celsius
    if not TEMP_AVAILABLE:
        return jsonify({"error": "Temperature sensor not available"}), 503
    if temp is None:
        return jsonify({"error": "Temperature reading not yet available"}), 503
    return jsonify(
        {
            "temperature_c": round(temp, 2),
            "temperature_f": round(temp * 9 / 5 + 32, 2),
            "unit": "celsius",
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
    )


@app.route("/health")
def health():
    """Liveness / readiness probe endpoint."""
    with _temp_lock:
        temp = _current_temp_celsius
    return jsonify(
        {
            "status": "ok",
            "camera_available": CAMERA_AVAILABLE,
            "temp_sensor_available": TEMP_AVAILABLE,
            "mqtt_available": MQTT_AVAILABLE,
            "temperature_c": round(temp, 2) if temp is not None else None,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=False)
