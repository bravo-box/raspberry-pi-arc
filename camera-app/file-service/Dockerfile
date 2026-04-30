FROM python:3.11-slim-bookworm

LABEL maintainer="raspberry-pi-arc"
LABEL description="File service – uploads outbox images to Azure Blob Storage and manages acknowledgements"

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

# Run as a non-root user for better security
RUN useradd -m -u 1000 appuser
USER appuser

CMD ["python", "app.py"]
