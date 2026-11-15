# ARES — Astronaut Route & Exploration System

A Mars exploration planning application developed for
NASA Space Apps Challenge 2026.

## Proposed Technology Stack

- Backend: Python, FastAPI, Pydantic
- Route Planning: A*, NumPy, NetworkX
- Frontend: Flutter
- Geospatial Processing: Rasterio, GDAL, QGIS
- Testing: pytest

## Current Status

Backend API foundation and local development setup.

NASA dataset integration and terrain-aware routing
are pending implementation and validation.

## Run Locally

cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python -m uvicorn app.main:app --reload --port 8005

API documentation:
http://127.0.0.1:8005/docs

## Testing

cd backend
python -m pytest -v