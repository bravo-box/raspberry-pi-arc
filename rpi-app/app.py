import io
import logging
import time
from datetime import datetime, timezone

from flask import Flask, Response, jsonify, render_template_string

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

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
    </style>
</head>
<body>
    <h1>&#127909; Raspberry Pi Camera</h1>
    <span class="status {{ 'ok' if camera_available else 'error' }}">
        Camera: {{ 'Online' if camera_available else 'Unavailable' }}
    </span>
    {% if camera_available %}
    <br/>
    <a class="btn" href="/capture">&#128247; Capture Snapshot</a>
    <a class="btn" href="/stream">&#9654; Live Stream</a>
    {% endif %}
    <a class="btn" href="/health">&#10004; Health Check</a>
    {% if camera_available %}
    <div>
        <img src="/stream" alt="Live camera feed" />
    </div>
    {% endif %}
</body>
</html>
"""


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


@app.route("/")
def index():
    return render_template_string(INDEX_HTML, camera_available=CAMERA_AVAILABLE)


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


@app.route("/health")
def health():
    """Liveness / readiness probe endpoint."""
    return jsonify(
        {
            "status": "ok",
            "camera_available": CAMERA_AVAILABLE,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=False)
