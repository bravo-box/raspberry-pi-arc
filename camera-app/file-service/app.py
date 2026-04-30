"""
file-service: Monitors /outbox for completed image files, uploads them to
Azure Blob Storage using a service principal, publishes an upload notification
to the 'photo-upload' Azure Service Bus topic, and deletes the local file once
an acknowledgement is received on the 'photo-processed' topic.

Configuration is read from /config/config.json (mounted as a Kubernetes Secret).

Expected config.json fields:
    service_bus_namespace  – Service Bus namespace name (without .servicebus.windows.net)
    tenant_id              – Azure AD tenant ID
    client_id              – Service principal client ID
    client_secret          – Service principal client secret
    storage_account_name   – Azure Storage account name
    storage_container_name – Blob container name for uploaded photos

Environment variable overrides:
    CONFIG_FILE            – Path to the config JSON file (default: /config/config.json)
    OUTBOX_DIR             – Directory to monitor for new files  (default: /outbox)
    POLL_INTERVAL_SECONDS  – Seconds between outbox scans        (default: 5)
    FILE_STABLE_SECONDS    – Seconds a file must be unchanged before it is
                             considered complete and safe to upload (default: 2)
    ACK_SUBSCRIPTION_NAME  – Subscription name on the 'photo-processed' topic
                             where acknowledgements arrive        (default: file-service)
"""

import json
import logging
import os
import signal
import socket
import threading
import time
from pathlib import Path
from threading import Event, Thread
from typing import Dict

from azure.identity import ClientSecretCredential
from azure.servicebus import ServiceBusClient, ServiceBusMessage
from azure.storage.blob import BlobServiceClient

UPLOAD_TOPIC_NAME = "photo-upload"
ACK_TOPIC_NAME = "photo-processed"

CONFIG_FILE = Path(os.environ.get("CONFIG_FILE", "/config/config.json"))
OUTBOX_DIR = Path(os.environ.get("OUTBOX_DIR", "/outbox"))
POLL_INTERVAL_SECONDS = float(os.environ.get("POLL_INTERVAL_SECONDS", "5"))
FILE_STABLE_SECONDS = float(os.environ.get("FILE_STABLE_SECONDS", "2"))
ACK_SUBSCRIPTION_NAME = os.environ.get("ACK_SUBSCRIPTION_NAME", "file-service")

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("file-service")

STOP_EVENT = Event()

# Maps blob_name -> local Path for files awaiting an acknowledgement.
_pending_lock = threading.Lock()
PENDING_DELETE: Dict[str, Path] = {}


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------


def load_config(config_file: Path) -> dict:
    """Load and return the JSON configuration file."""
    with config_file.open() as fh:
        return json.load(fh)


# ---------------------------------------------------------------------------
# Connectivity check
# ---------------------------------------------------------------------------


def check_connectivity(hostname: str = "1.1.1.1", port: int = 443, timeout: int = 5) -> bool:
    """Return True if a TCP connection to *hostname:port* succeeds."""
    import socket as _socket

    try:
        with _socket.create_connection((hostname, port), timeout=timeout):
            return True
    except OSError:
        return False


def wait_for_connectivity() -> None:
    """Block until internet connectivity is available or a shutdown is requested."""
    while not STOP_EVENT.is_set():
        if check_connectivity():
            return
        logger.warning("No internet connectivity – retrying in 10 s…")
        time.sleep(10)


# ---------------------------------------------------------------------------
# File stability check
# ---------------------------------------------------------------------------


def is_file_stable(path: Path, stable_seconds: float) -> bool:
    """Return True if *path* has not been modified for *stable_seconds*."""
    try:
        return (time.time() - path.stat().st_mtime) >= stable_seconds
    except FileNotFoundError:
        return False


# ---------------------------------------------------------------------------
# Azure Blob Storage upload
# ---------------------------------------------------------------------------


def upload_file(path: Path, config: dict) -> tuple:
    """
    Upload *path* to Azure Blob Storage.

    Returns a (account_name, container_name, blob_name) tuple.
    """
    credential = ClientSecretCredential(
        tenant_id=config["tenant_id"],
        client_id=config["client_id"],
        client_secret=config["client_secret"],
    )
    account_name: str = config["storage_account_name"]
    container_name: str = config["storage_container_name"]
    blob_name: str = path.name

    account_url = f"https://{account_name}.blob.core.windows.net"
    blob_service = BlobServiceClient(account_url=account_url, credential=credential)
    blob_client = blob_service.get_blob_client(container=container_name, blob=blob_name)

    with path.open("rb") as data:
        blob_client.upload_blob(data, overwrite=True)

    logger.info(
        "Uploaded '%s' to storage account '%s', container '%s'.",
        blob_name,
        account_name,
        container_name,
    )
    return account_name, container_name, blob_name


# ---------------------------------------------------------------------------
# Service Bus notification
# ---------------------------------------------------------------------------


def publish_upload_notification(
    sb_client: ServiceBusClient,
    account_name: str,
    container_name: str,
    blob_name: str,
    hostname: str,
) -> None:
    """Publish an upload notification to the 'photo-upload' topic."""
    payload = json.dumps(
        {
            "storage_account": account_name,
            "container": container_name,
            "file_name": blob_name,
            "host_name": hostname,
        }
    )
    with sb_client.get_topic_sender(topic_name=UPLOAD_TOPIC_NAME) as sender:
        sender.send_messages(ServiceBusMessage(payload))
    logger.info("Published upload notification for '%s' to '%s'.", blob_name, UPLOAD_TOPIC_NAME)


# ---------------------------------------------------------------------------
# Background threads
# ---------------------------------------------------------------------------


def file_watcher_thread(config: dict, sb_client: ServiceBusClient) -> None:
    """Poll OUTBOX_DIR for stable files, upload them, then publish notifications."""
    hostname = socket.gethostname()

    while not STOP_EVENT.is_set():
        try:
            for path in sorted(OUTBOX_DIR.glob("*")):
                if not path.is_file():
                    continue
                with _pending_lock:
                    if path.name in PENDING_DELETE:
                        continue
                if not is_file_stable(path, FILE_STABLE_SECONDS):
                    continue

                # Block until connectivity is available before uploading.
                wait_for_connectivity()
                if STOP_EVENT.is_set():
                    break

                try:
                    account_name, container_name, blob_name = upload_file(path, config)
                    with _pending_lock:
                        PENDING_DELETE[blob_name] = path
                    publish_upload_notification(
                        sb_client, account_name, container_name, blob_name, hostname
                    )
                except Exception as exc:  # pylint: disable=broad-except
                    logger.error("Failed to process '%s': %s", path.name, exc)

        except Exception as exc:  # pylint: disable=broad-except
            logger.error("Unexpected error in file watcher: %s", exc)

        STOP_EVENT.wait(POLL_INTERVAL_SECONDS)


def ack_listener_thread(sb_client: ServiceBusClient) -> None:
    """
    Listen for acknowledgement messages on the 'photo-processed' topic and
    delete the corresponding local files.

    An acknowledgement message is expected to be a JSON object containing at
    least a ``file_name`` field matching the blob name published in the
    'photo-upload' notification.
    """
    with sb_client.get_subscription_receiver(
        topic_name=ACK_TOPIC_NAME,
        subscription_name=ACK_SUBSCRIPTION_NAME,
    ) as receiver:
        logger.info(
            "Listening for acknowledgements on topic '%s' (subscription '%s').",
            ACK_TOPIC_NAME,
            ACK_SUBSCRIPTION_NAME,
        )
        while not STOP_EVENT.is_set():
            messages = receiver.receive_messages(max_message_count=10, max_wait_time=5)
            for message in messages:
                try:
                    body = json.loads(str(message))
                    file_name = body.get("file_name")
                    if file_name:
                        with _pending_lock:
                            local_path = PENDING_DELETE.pop(file_name, None)
                        if local_path is not None and local_path.exists():
                            local_path.unlink()
                            logger.info(
                                "Deleted local file '%s' after acknowledgement.",
                                local_path,
                            )
                        else:
                            logger.debug(
                                "Ack received for '%s' but file not in pending list or already removed.",
                                file_name,
                            )
                    receiver.complete_message(message)
                except Exception as exc:  # pylint: disable=broad-except
                    logger.error("Error processing ack message: %s", exc)
                    receiver.abandon_message(message)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


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
        "Connecting to Service Bus namespace '%s'.",
        config["service_bus_namespace"],
    )

    with ServiceBusClient(fully_qualified_namespace, credential) as sb_client:
        watcher = Thread(
            target=file_watcher_thread,
            args=(config, sb_client),
            daemon=True,
            name="file-watcher",
        )
        ack_listener = Thread(
            target=ack_listener_thread,
            args=(sb_client,),
            daemon=True,
            name="ack-listener",
        )

        watcher.start()
        ack_listener.start()

        STOP_EVENT.wait()

        watcher.join(timeout=10)
        ack_listener.join(timeout=10)


if __name__ == "__main__":
    main()
