import json
import os
import socket
import time
from datetime import datetime, timezone
from pathlib import Path

LOG_DIR = Path(os.getenv("LOG_DIR", "/app/logs"))
LOG_FILE = LOG_DIR / os.getenv("LOG_FILE", "demo.log")
LOG_INTERVAL_SECONDS = float(os.getenv("LOG_INTERVAL_SECONDS", "2"))
APP_NAME = os.getenv("APP_NAME", "raspberry-pi-arc-demo")


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

    while True:
        line = emit_log_line()
        with LOG_FILE.open("a", encoding="utf-8") as log_file:
            log_file.write(f"{line}\n")
        print(line, flush=True)
        time.sleep(LOG_INTERVAL_SECONDS)


if __name__ == "__main__":
    main()
