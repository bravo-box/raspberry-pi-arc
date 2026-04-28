"""Azure Service Bus and Blob Storage client for the rpi-app."""
import json
import logging
import os
import socket
import uuid
from datetime import datetime, timezone
from pathlib import Path
from threading import Thread
from typing import Callable, Optional

from azure.identity import DefaultAzureCredential
from azure.messaging.servicebus import ServiceBusClient, ServiceBusMessage
from azure.storage.blob import BlobServiceClient

logger = logging.getLogger(__name__)

SERVICEBUS_NAMESPACE = os.getenv("SERVICEBUS_NAMESPACE", "")
REGISTRATION_TOPIC = os.getenv("REGISTRATION_TOPIC", "device-registration")
TELEMETRY_TOPIC = os.getenv("TELEMETRY_TOPIC", "device-telemetry")
COMMANDS_TOPIC = os.getenv("COMMANDS_TOPIC", "device-commands")
COMMANDS_SUBSCRIPTION = os.getenv("COMMANDS_SUBSCRIPTION", "backend-sub")
IMAGES_TOPIC = os.getenv("IMAGES_TOPIC", "device-images")
STORAGE_ACCOUNT_URL = os.getenv("STORAGE_ACCOUNT_URL", "")
IMAGES_CONTAINER = os.getenv("IMAGES_CONTAINER", "device-images")
ASSET_ID_FILE = Path(os.getenv("ASSET_ID_FILE", "/app/data/asset_id.txt"))

_REGISTRATION_RESPONSE_TOPIC = "device-registration-response"
_REGISTRATION_RESPONSE_SUB = "rpi-sub"
_REGISTRATION_TIMEOUT = 30


def _get_credential():
    """Return an Azure credential, preferring ManagedIdentityCredential."""
    try:
        from azure.identity import ManagedIdentityCredential  # noqa: PLC0415

        return ManagedIdentityCredential()
    except Exception:
        return DefaultAzureCredential()


def _decode_body(msg) -> str:
    """Decode a ServiceBusReceivedMessage body to a UTF-8 string."""
    body = msg.body
    if isinstance(body, bytes):
        return body.decode("utf-8")
    return b"".join(body).decode("utf-8")


def get_or_register_device() -> Optional[str]:
    """Return the persisted asset ID, registering the device if necessary.

    On first run sends a registration message to REGISTRATION_TOPIC with a
    correlation ID, then waits up to 30 s for a matching response on the
    device-registration-response topic.  The resulting asset ID is saved to
    ASSET_ID_FILE so subsequent calls return immediately.

    Returns the asset ID string, or None when registration is not possible.
    """
    if ASSET_ID_FILE.exists():
        asset_id = ASSET_ID_FILE.read_text().strip()
        if asset_id:
            logger.info("Loaded asset ID from file: %s", asset_id)
            return asset_id

    if not SERVICEBUS_NAMESPACE:
        logger.warning("SERVICEBUS_NAMESPACE not set; skipping device registration")
        return None

    try:
        credential = _get_credential()
        correlation_id = str(uuid.uuid4())
        hostname = socket.gethostname()

        payload = json.dumps({"action": "register", "hostname": hostname})
        reg_message = ServiceBusMessage(
            payload,
            correlation_id=correlation_id,
            content_type="application/json",
        )

        with ServiceBusClient(SERVICEBUS_NAMESPACE, credential) as sb_client:
            with sb_client.get_topic_sender(REGISTRATION_TOPIC) as sender:
                sender.send_messages(reg_message)
            logger.info("Registration message sent (correlationId=%s)", correlation_id)

            with sb_client.get_subscription_receiver(
                _REGISTRATION_RESPONSE_TOPIC,
                _REGISTRATION_RESPONSE_SUB,
                max_wait_time=_REGISTRATION_TIMEOUT,
            ) as receiver:
                for msg in receiver:
                    if msg.correlation_id != correlation_id:
                        receiver.abandon_message(msg)
                        continue
                    try:
                        data = json.loads(_decode_body(msg))
                        asset_id = data.get("assetId") or data.get("asset_id")
                        if asset_id:
                            ASSET_ID_FILE.parent.mkdir(parents=True, exist_ok=True)
                            ASSET_ID_FILE.write_text(asset_id)
                            receiver.complete_message(msg)
                            logger.info("Device registered with asset ID: %s", asset_id)
                            return asset_id
                        receiver.abandon_message(msg)
                    except Exception as exc:  # pylint: disable=broad-except
                        logger.error("Error parsing registration response: %s", exc)
                        receiver.abandon_message(msg)

        logger.warning("Registration timed out after %s seconds", _REGISTRATION_TIMEOUT)
    except Exception as exc:  # pylint: disable=broad-except
        logger.error("Device registration failed: %s", exc)

    return None


def send_telemetry(asset_id: str, temperature: float, unit: str = "C") -> None:
    """Send a temperature telemetry message to TELEMETRY_TOPIC."""
    if not SERVICEBUS_NAMESPACE:
        return
    try:
        credential = _get_credential()
        payload = json.dumps(
            {
                "assetId": asset_id,
                "temperature": temperature,
                "unit": unit,
                "timestamp": datetime.now(timezone.utc).isoformat(),
            }
        )
        with ServiceBusClient(SERVICEBUS_NAMESPACE, credential) as sb_client:
            with sb_client.get_topic_sender(TELEMETRY_TOPIC) as sender:
                sender.send_messages(
                    ServiceBusMessage(payload, content_type="application/json")
                )
        logger.debug("Telemetry sent: %.2f°%s for asset %s", temperature, unit, asset_id)
    except Exception as exc:  # pylint: disable=broad-except
        logger.error("Failed to send telemetry: %s", exc)


def upload_image(asset_id: str, image_path: Path) -> Optional[str]:
    """Upload a JPEG image to Blob Storage and publish a notification message.

    The blob is stored as ``{asset_id}/{timestamp}_{uuid}.jpg``.  After a
    successful upload the local file is deleted and a message is sent to
    IMAGES_TOPIC.  Returns the blob URL on success, None on failure.
    """
    if not STORAGE_ACCOUNT_URL:
        logger.warning("STORAGE_ACCOUNT_URL not set; skipping image upload")
        return None
    try:
        credential = _get_credential()
        timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        blob_name = f"{asset_id}/{timestamp}_{uuid.uuid4().hex[:8]}.jpg"

        blob_service = BlobServiceClient(STORAGE_ACCOUNT_URL, credential=credential)
        blob_client = blob_service.get_blob_client(container=IMAGES_CONTAINER, blob=blob_name)

        with open(image_path, "rb") as image_file:
            blob_client.upload_blob(image_file, overwrite=True)

        blob_url = blob_client.url
        logger.info("Image uploaded: %s", blob_url)

        if SERVICEBUS_NAMESPACE:
            sb_payload = json.dumps(
                {
                    "assetId": asset_id,
                    "blobName": blob_name,
                    "blobUrl": blob_url,
                    "capturedAt": datetime.now(timezone.utc).isoformat(),
                }
            )
            with ServiceBusClient(SERVICEBUS_NAMESPACE, credential) as sb_client:
                with sb_client.get_topic_sender(IMAGES_TOPIC) as sender:
                    sender.send_messages(
                        ServiceBusMessage(sb_payload, content_type="application/json")
                    )
            logger.info("Image notification sent to topic '%s'", IMAGES_TOPIC)

        image_path.unlink(missing_ok=True)
        return blob_url
    except Exception as exc:  # pylint: disable=broad-except
        logger.error("Image upload failed: %s", exc)
        return None


def start_command_listener(
    asset_id: str, on_take_picture: Callable[[], None]
) -> Thread:
    """Start a daemon thread that processes device commands from Service Bus.

    Listens on COMMANDS_TOPIC / COMMANDS_SUBSCRIPTION and calls
    *on_take_picture* whenever a ``take-picture`` command addressed to this
    device is received.
    """

    def _listen() -> None:
        if not SERVICEBUS_NAMESPACE:
            logger.warning("SERVICEBUS_NAMESPACE not set; command listener disabled")
            return
        try:
            credential = _get_credential()
            with ServiceBusClient(SERVICEBUS_NAMESPACE, credential) as sb_client:
                with sb_client.get_subscription_receiver(
                    COMMANDS_TOPIC, COMMANDS_SUBSCRIPTION
                ) as receiver:
                    logger.info("Command listener active for asset %s", asset_id)
                    for msg in receiver:
                        try:
                            data = json.loads(_decode_body(msg))
                            if (
                                data.get("assetId") == asset_id
                                and data.get("command") == "take-picture"
                            ):
                                logger.info(
                                    "take-picture command received for asset %s", asset_id
                                )
                                on_take_picture()
                            receiver.complete_message(msg)
                        except Exception as inner_exc:  # pylint: disable=broad-except
                            logger.error("Error processing command message: %s", inner_exc)
                            receiver.abandon_message(msg)
        except Exception as exc:  # pylint: disable=broad-except
            logger.error("Command listener encountered a fatal error: %s", exc)

    thread = Thread(target=_listen, daemon=True, name="command-listener")
    thread.start()
    return thread
