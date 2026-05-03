"""
registration-service: Registers the device with the cloud on first startup and
sends periodic health-check heartbeats every 30 seconds.

## First-startup registration flow
1. Load config from /config/config.json.
2. If /config/device-registration.json does not exist, publish the device
   hostname to the 'register-device' Service Bus topic and wait for a
   response on the 'device-registered' topic (subscription:
   'registration-service') that carries the assigned device GUID.
3. Persist the GUID to /config/device-registration.json.

## Health-check loop (runs after successful registration)
Every 30 seconds publish a message to the 'health-check' topic containing:
  - device_id        – GUID from device-registration.json
  - hostname         – system hostname
  - network_status   – "connected", "degraded", or "disabled"
  - disk_total_gb    – total disk size of /
  - disk_used_gb     – used disk space of /
  - disk_free_gb     – free disk space of /
  - disk_free_percent – free disk as a percentage of total
  - status           – "Green", "Yellow", or "Red"
  - timestamp        – ISO-8601 UTC timestamp

Status rules:
  Red    – network disabled  OR  free disk < 25 %
  Yellow – free disk < 50 %  OR  network degraded  (and not already Red)
  Green  – network connected AND free disk >= 50 %

Network states:
  connected – TCP connect to 1.1.1.1:443 within 1 s
  degraded  – TCP connect succeeds within 5 s but not within 1 s
  disabled  – no TCP connection possible within 5 s

Configuration is read from /config/config.json (mounted as a Kubernetes volume).

Expected config.json fields:
    service_bus_namespace  – Service Bus namespace name (without .servicebus.windows.net)
    tenant_id              – Azure AD tenant ID
    client_id              – Service principal client ID
    client_secret          – Service principal client secret

Environment variable overrides:
    CONFIG_FILE               – Path to config JSON  (default: /config/config.json)
    REGISTRATION_FILE         – Path to registration JSON
                                (default: /config/device-registration.json)
    HEALTH_CHECK_INTERVAL     – Seconds between health-check messages (default: 30)
    REGISTRATION_SUBSCRIPTION – Subscription name on the 'device-registered' topic
                                (default: registration-service)
"""

import json
import logging
import os
import shutil
import signal
import socket
import time
from datetime import datetime, timezone
from pathlib import Path
from threading import Event

from azure.identity import ClientSecretCredential
from azure.servicebus import ServiceBusClient, ServiceBusMessage

# ---------------------------------------------------------------------------
# Constants / environment configuration
# ---------------------------------------------------------------------------

REGISTER_TOPIC = "register-device"
REGISTERED_TOPIC = "device-registered"
HEALTH_TOPIC = "health-check"

CONFIG_FILE = Path(os.environ.get("CONFIG_FILE", "/config/config.json"))
REGISTRATION_FILE = Path(
    os.environ.get("REGISTRATION_FILE", "/config/device-registration.json")
)
HEALTH_CHECK_INTERVAL = float(os.environ.get("HEALTH_CHECK_INTERVAL", "30"))
REGISTRATION_SUBSCRIPTION = os.environ.get(
    "REGISTRATION_SUBSCRIPTION", "registration-service"
)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("registration-service")

STOP_EVENT = Event()


# ---------------------------------------------------------------------------
# Configuration helpers
# ---------------------------------------------------------------------------


def load_config(config_file: Path) -> dict:
    """Load and return the JSON configuration file."""
    with config_file.open() as fh:
        return json.load(fh)


def load_registration(registration_file: Path) -> dict:
    """Return the device registration data, or an empty dict if not present."""
    if registration_file.exists():
        with registration_file.open() as fh:
            return json.load(fh)
    return {}


def save_registration(registration_file: Path, data: dict) -> None:
    """Persist device registration data to *registration_file*."""
    registration_file.parent.mkdir(parents=True, exist_ok=True)
    with registration_file.open("w") as fh:
        json.dump(data, fh, indent=2)
    logger.info("Saved device registration to '%s'.", registration_file)


# ---------------------------------------------------------------------------
# Network helpers
# ---------------------------------------------------------------------------


def _try_connect(host: str = "1.1.1.1", port: int = 443, timeout: float = 1.0) -> bool:
    """Return True if a TCP connection to *host:port* succeeds within *timeout*."""
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except OSError:
        return False


def check_network_status() -> str:
    """
    Return one of "connected", "degraded", or "disabled".

    connected – reachable within 1 second
    degraded  – reachable within 5 seconds but not within 1 second
    disabled  – not reachable within 5 seconds
    """
    if _try_connect(timeout=1.0):
        return "connected"
    if _try_connect(timeout=5.0):
        return "degraded"
    return "disabled"


# ---------------------------------------------------------------------------
# Disk helpers
# ---------------------------------------------------------------------------


def get_disk_stats(path: str = "/") -> dict:
    """Return a dict with total, used, free (GB) and free_percent for *path*."""
    usage = shutil.disk_usage(path)
    total_gb = usage.total / (1024 ** 3)
    used_gb = usage.used / (1024 ** 3)
    free_gb = usage.free / (1024 ** 3)
    free_percent = (usage.free / usage.total * 100) if usage.total > 0 else 0.0
    return {
        "disk_total_gb": round(total_gb, 2),
        "disk_used_gb": round(used_gb, 2),
        "disk_free_gb": round(free_gb, 2),
        "disk_free_percent": round(free_percent, 2),
    }


# ---------------------------------------------------------------------------
# Status computation
# ---------------------------------------------------------------------------


def compute_status(network_status: str, disk_free_percent: float) -> str:
    """
    Compute the overall health status.

    Red    – network is disabled OR free disk < 25 %
    Yellow – free disk < 50 % OR network is degraded  (and not already Red)
    Green  – network connected AND free disk >= 50 %
    """
    if network_status == "disabled" or disk_free_percent < 25.0:
        return "Red"
    if disk_free_percent < 50.0 or network_status == "degraded":
        return "Yellow"
    return "Green"


# ---------------------------------------------------------------------------
# Service Bus: device registration
# ---------------------------------------------------------------------------


def register_device(config: dict, sb_client: ServiceBusClient) -> str:
    """
    Publish a registration request and block until the cloud sends back a
    device GUID on the 'device-registered' topic.

    Returns the assigned device ID (GUID string).
    """
    hostname = socket.gethostname()
    payload = json.dumps({"hostname": hostname})

    logger.info(
        "Publishing registration request for hostname '%s' to topic '%s'.",
        hostname,
        REGISTER_TOPIC,
    )
    with sb_client.get_topic_sender(topic_name=REGISTER_TOPIC) as sender:
        sender.send_messages(ServiceBusMessage(payload))

    logger.info(
        "Waiting for device-registered response on topic '%s', subscription '%s'.",
        REGISTERED_TOPIC,
        REGISTRATION_SUBSCRIPTION,
    )
    with sb_client.get_subscription_receiver(
        topic_name=REGISTERED_TOPIC,
        subscription_name=REGISTRATION_SUBSCRIPTION,
    ) as receiver:
        while not STOP_EVENT.is_set():
            messages = receiver.receive_messages(max_message_count=1, max_wait_time=10)
            for message in messages:
                try:
                    body = json.loads(str(message))
                    device_id = body.get("device_id") or body.get("deviceId")
                    msg_hostname = body.get("hostname")
                    if device_id and msg_hostname == hostname:
                        receiver.complete_message(message)
                        logger.info(
                            "Received device_id '%s' for hostname '%s'.",
                            device_id,
                            hostname,
                        )
                        return device_id
                    # Message is for a different device; leave it for re-delivery.
                    receiver.abandon_message(message)
                except Exception as exc:  # pylint: disable=broad-except
                    logger.error("Error processing device-registered message: %s", exc)
                    receiver.abandon_message(message)

    raise RuntimeError("Shutdown requested before device registration completed.")


# ---------------------------------------------------------------------------
# Service Bus: health check
# ---------------------------------------------------------------------------


def publish_health_check(
    sb_client: ServiceBusClient,
    device_id: str,
    hostname: str,
) -> None:
    """Build and publish a health-check message."""
    network_status = check_network_status()
    disk_stats = get_disk_stats("/")
    status = compute_status(network_status, disk_stats["disk_free_percent"])

    payload = json.dumps(
        {
            "device_id": device_id,
            "hostname": hostname,
            "network_status": network_status,
            **disk_stats,
            "status": status,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
    )

    with sb_client.get_topic_sender(topic_name=HEALTH_TOPIC) as sender:
        sender.send_messages(ServiceBusMessage(payload))

    logger.info(
        "Published health-check for device '%s': status=%s network=%s disk_free=%.1f%%",
        device_id,
        status,
        network_status,
        disk_stats["disk_free_percent"],
    )


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def main() -> None:
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

    with ServiceBusClient(fully_qualified_namespace, credential) as sb_client:
        # ------------------------------------------------------------------
        # Step 1: Ensure the device is registered.
        # ------------------------------------------------------------------
        registration = load_registration(REGISTRATION_FILE)
        device_id = registration.get("device_id")

        if not device_id:
            logger.info(
                "No device registration found at '%s'. Starting registration.",
                REGISTRATION_FILE,
            )
            device_id = register_device(config, sb_client)
            save_registration(
                REGISTRATION_FILE,
                {
                    "device_id": device_id,
                    "hostname": socket.gethostname(),
                },
            )
        else:
            logger.info(
                "Device already registered. device_id='%s'.", device_id
            )

        hostname = socket.gethostname()

        # ------------------------------------------------------------------
        # Step 2: Health-check loop.
        # ------------------------------------------------------------------
        logger.info(
            "Starting health-check loop (interval=%s s).", HEALTH_CHECK_INTERVAL
        )
        while not STOP_EVENT.is_set():
            try:
                publish_health_check(sb_client, device_id, hostname)
            except Exception as exc:  # pylint: disable=broad-except
                logger.error("Failed to publish health-check: %s", exc)
            STOP_EVENT.wait(HEALTH_CHECK_INTERVAL)

    logger.info("registration-service stopped.")


if __name__ == "__main__":
    main()
