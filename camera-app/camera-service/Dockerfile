# ── Stage 1: dependency layer ─────────────────────────────────────────────────
FROM python:3.11-slim-bookworm AS deps

WORKDIR /app

# System packages required by picamera2 / libcamera and Azure SDK
RUN apt-get update && apt-get install -y --no-install-recommends \
        libcamera-dev \
        libcap-dev \
        libjpeg-dev \
        zlib1g-dev \
        libatlas-base-dev \
        python3-libcamera \
        python3-kms++ \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# ── Stage 2: runtime image ────────────────────────────────────────────────────
FROM python:3.11-slim-bookworm AS runtime

ARG GIT_REVISION
ARG BUILD_DATE
ARG IMAGE_VERSION

LABEL maintainer="raspberry-pi-arc" \
      description="Camera service – captures images triggered by Service Bus messages" \
      org.opencontainers.image.source="https://github.com/bravo-box/raspberry-pi-arc" \
      org.opencontainers.image.revision="${GIT_REVISION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.version="${IMAGE_VERSION}"

WORKDIR /app

# Runtime system libraries needed by libcamera / picamera2
RUN apt-get update && apt-get install -y --no-install-recommends \
        libcamera0 \
        python3-libcamera \
        python3-kms++ \
    && rm -rf /var/lib/apt/lists/*

# Copy installed Python packages from the build stage
COPY --from=deps /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY --from=deps /usr/local/bin /usr/local/bin

# Copy application source
COPY app.py .

# Run as a non-root user; add to video group (GID 44) for camera device access
RUN useradd -m -u 1000 appuser && usermod -aG video appuser
USER appuser

CMD ["python", "app.py"]
