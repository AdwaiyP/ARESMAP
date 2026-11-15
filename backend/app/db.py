"""MongoDB connection helper for ARES FastAPI backend."""

from __future__ import annotations

import os
from functools import lru_cache
from pathlib import Path

from pymongo import MongoClient
from pymongo.database import Database

REPO_ROOT = Path(__file__).resolve().parents[2]


def _load_env_file(path: Path) -> None:
    if not path.exists():
        return
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, val = line.split("=", 1)
        os.environ.setdefault(key.strip(), val.strip().strip('"').strip("'"))


@lru_cache(maxsize=1)
def get_mongo_client() -> MongoClient:
    _load_env_file(REPO_ROOT / ".env")
    uri = os.getenv("MONGO_URI", "").strip()
    if not uri:
        raise RuntimeError("MONGO_URI is not configured in .env or environment.")
    return MongoClient(uri, serverSelectionTimeoutMS=10000)


def get_db() -> Database:
    _load_env_file(REPO_ROOT / ".env")
    db_name = os.getenv("MONGO_DB", "ares_base").strip() or "ares_base"
    return get_mongo_client()[db_name]
