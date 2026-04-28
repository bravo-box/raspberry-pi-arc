# ── Stage 1: dependency layer ─────────────────────────────────────────────────
FROM python:3.11-slim-bookworm AS deps

WORKDIR /app

# Install build tools and system packages required by picamera2 and its dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        libcap-dev \
        libjpeg62-turbo-dev \
        zlib1g-dev \
        libatlas-base-dev \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Clean up build tools to reduce image size
RUN apt-get update && apt-get remove -y --auto-remove \
        build-essential \
        libcap-dev \
        libjpeg62-turbo-dev \
        zlib1g-dev \
        libatlas-base-dev \
    && rm -rf /var/lib/apt/lists/*

# ── Stage 2: runtime image ────────────────────────────────────────────────────
FROM python:3.11-slim-bookworm AS runtime

LABEL maintainer="raspberry-pi-arc"
LABEL description="Raspberry Pi camera application"

WORKDIR /app

# Install runtime system libraries needed by picamera2
RUN apt-get update && apt-get install -y --no-install-recommends \
        libcap2 \
        libjpeg62-turbo \
        zlib1g \
        libatlas3-base \
    && rm -rf /var/lib/apt/lists/*

# Copy installed Python packages from the build stage
COPY --from=deps /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY --from=deps /usr/local/bin /usr/local/bin

# Copy the Flask camera application source
COPY app.py .

# The camera device (/dev/video0) is passed in at runtime via --device
EXPOSE 5000

# Run as a non-root user for better security
RUN useradd -m -u 1000 appuser && usermod -aG video appuser
USER appuser

CMD ["python", "app.py"]
