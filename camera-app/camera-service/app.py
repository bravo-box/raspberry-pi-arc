"""
camera-service: Subscribes to the 'TaskCamera' Azure Service Bus topic and
captures a JPEG image whenever a message is received, saving it to /outbox.

Configuration is read from /config/config.json (mounted as a Kubernetes Secret).

Expected config.json fields used by this service:
    service_bus_namespace  – Service Bus namespace name (without .servicebus.windows.net)
    tenant_id              – Azure AD tenant ID
    client_id              – Service principal client ID
    client_secret          – Service principal client secret

Environment variable overrides:
    CONFIG_FILE            – Path to the config JSON file (default: /config/config.json)
    OUTBOX_DIR             – Directory where captured images are saved (default: /outbox)
    SUBSCRIPTION_NAME      – Service Bus subscription name on the TaskCamera topic
                             (default: camera-service)
"""

import json
import logging
import os
import signal
import socket
import time
from datetime import datetime, timezone
from pathlib import Path
from threading import Event

from azure.identity import ClientSecretCredential
from azure.servicebus import ServiceBusClient

TOPIC_NAME = "TaskCamera"
CONFIG_FILE = Path(os.environ.get("CONFIG_FILE", "/config/config.json"))
OUTBOX_DIR = Path(os.environ.get("OUTBOX_DIR", "/outbox"))
SUBSCRIPTION_NAME = os.environ.get("SUBSCRIPTION_NAME", "camera-service")

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("camera-service")

STOP_EVENT = Event()

# ---------------------------------------------------------------------------
# Camera initialisation – falls back gracefully when not running on a Pi.
# ---------------------------------------------------------------------------
try:
    from picamera2 import Picamera2  # type: ignore[import]

    _camera = Picamera2()
    _camera_config = _camera.create_still_configuration(main={"size": (1920, 1080)})
    _camera.configure(_camera_config)
    _camera.start()
    time.sleep(2)  # Allow the camera to warm up
    CAMERA_AVAILABLE = True
    logger.info("Picamera2 initialised successfully.")
except Exception as exc:  # pylint: disable=broad-except
    CAMERA_AVAILABLE = False
    logger.warning("Camera not available: %s. Placeholder images will be used.", exc)


def load_config(config_file: Path) -> dict:
    """Load and return the JSON configuration file."""
    with config_file.open() as fh:
        return json.load(fh)


def capture_image(outbox: Path) -> Path:
    """
    Capture a JPEG image and save it to *outbox*.

    Returns the path of the saved file.
    When the camera hardware is unavailable (e.g. during local development),
    a small placeholder file is written instead so the rest of the pipeline
    can still be exercised.
    """
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S_%f")
    hostname = socket.gethostname()
    filename = f"{hostname}_{timestamp}.jpg"
    output_path = outbox / filename

    if CAMERA_AVAILABLE:
        _camera.capture_file(str(output_path))
        logger.info("Captured image: %s", output_path)
    else:
        output_path.write_bytes(b"PLACEHOLDER_IMAGE_DATA")
        logger.warning(
            "Camera unavailable; placeholder written to %s", output_path
        )

    return output_path


def main() -> None:
    OUTBOX_DIR.mkdir(parents=True, exist_ok=True)

    def _shutdown(signum, frame):  # noqa: ANN001
        logger.info("Shutdown signal received.")
        STOP_EVENT.set()

    signal.signal(signal.SIGTERM, _shutdown)
    signal.signal(signal.SIGINT, _shutdown)

    logger.info("Loading config from '%s'.", CONFIG_FILE)
    config = load_config(CONFIG_FILE)

    credential = ClientSecretCredential(
        tenant_id=config["tenant_id"],
        client_id=config["client_id"],
        client_secret=config["client_secret"],
    )
    fully_qualified_namespace = (
        f"{config['service_bus_namespace']}.servicebus.windows.net"
    )

    logger.info(
        "Connecting to Service Bus namespace '%s', topic '%s', subscription '%s'.",
        config["service_bus_namespace"],
        TOPIC_NAME,
        SUBSCRIPTION_NAME,
    )

    with ServiceBusClient(fully_qualified_namespace, credential) as client:
        with client.get_subscription_receiver(
            topic_name=TOPIC_NAME,
            subscription_name=SUBSCRIPTION_NAME,
        ) as receiver:
            logger.info("Listening for messages on topic '%s'…", TOPIC_NAME)
            while not STOP_EVENT.is_set():
                messages = receiver.receive_messages(
                    max_message_count=1, max_wait_time=5
                )
                for message in messages:
                    logger.info(
                        "Received message on '%s': %s", TOPIC_NAME, str(message)
                    )
                    try:
                        capture_image(OUTBOX_DIR)
                        receiver.complete_message(message)
                    except Exception as exc:  # pylint: disable=broad-except
                        logger.error("Failed to capture image: %s", exc)
                        receiver.abandon_message(message)


if __name__ == "__main__":
    main()
