FROM python:3.11-slim-bookworm

ARG GIT_REVISION
ARG BUILD_DATE
ARG IMAGE_VERSION

LABEL maintainer="raspberry-pi-arc" \
      description="File service – uploads outbox images to Azure Blob Storage and manages acknowledgements" \
      org.opencontainers.image.source="https://github.com/bravo-box/raspberry-pi-arc" \
      org.opencontainers.image.revision="${GIT_REVISION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.version="${IMAGE_VERSION}"

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

# Run as a non-root user for better security
RUN useradd -m -u 1000 appuser
USER appuser

CMD ["python", "app.py"]
