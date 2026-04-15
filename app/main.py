import json
import os
import signal
import socket
import time
from datetime import datetime, timezone
from pathlib import Path
from threading import Event

LOG_DIR = Path(os.getenv("LOG_DIR", "/app/logs"))
LOG_FILE = LOG_DIR / os.getenv("LOG_FILE", "demo.log")
LOG_INTERVAL_SECONDS = float(os.getenv("LOG_INTERVAL_SECONDS", "2"))
APP_NAME = os.getenv("APP_NAME", "raspberry-pi-arc-demo")
STOP_EVENT = Event()


def emit_log_line() -> str:
    payload = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "app": APP_NAME,
        "hostname": socket.gethostname(),
        "message": "heartbeat",
    }
    return json.dumps(payload)


def main() -> None:
    LOG_DIR.mkdir(parents=True, exist_ok=True)

    def _shutdown_handler(_signum: int, _frame: object) -> None:
        STOP_EVENT.set()

    signal.signal(signal.SIGTERM, _shutdown_handler)
    signal.signal(signal.SIGINT, _shutdown_handler)

    with LOG_FILE.open("a", encoding="utf-8") as log_file:
        while not STOP_EVENT.is_set():
            line = emit_log_line()
            log_file.write(f"{line}\n")
            log_file.flush()
            print(line, flush=True)
            STOP_EVENT.wait(LOG_INTERVAL_SECONDS)


if __name__ == "__main__":
    main()
