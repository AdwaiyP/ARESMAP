FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PORT=8000

WORKDIR /app

# Install system libraries needed by Pillow / rasterio / scientific wheels
RUN apt-get update && apt-get install -y --no-install-recommends \
    libexpat1 \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# Root requirements.txt includes pymongo, pillow, rasterio, fastapi, uvicorn, numpy, scikit-learn, skops
COPY requirements.txt /app/requirements.txt
RUN pip install --upgrade pip && pip install -r /app/requirements.txt

# Copy backend and frontend (backend/app/main.py mounts ../frontend at "/")
COPY backend /app/backend
COPY frontend /app/frontend

WORKDIR /app/backend

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/api/v1/health')" || exit 1

CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
