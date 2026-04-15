FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    LOG_DIR=/app/logs \
    LOG_FILE=demo.log \
    LOG_INTERVAL_SECONDS=2

WORKDIR /app
COPY app/main.py /app/main.py

RUN useradd -m appuser && mkdir -p /app/logs && chown -R appuser:appuser /app
USER appuser

ENTRYPOINT ["python", "/app/main.py"]
