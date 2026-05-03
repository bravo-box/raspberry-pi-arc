FROM python:3.11-slim-bookworm

LABEL maintainer="raspberry-pi-arc"
LABEL description="Registration service – registers device on first boot and publishes periodic health-check messages"

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

# Run as a non-root user for better security
RUN useradd -m -u 1000 appuser
USER appuser

CMD ["python", "app.py"]
