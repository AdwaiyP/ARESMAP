# 08 — Database Setup & Seeding Guide (New User)

If you are setting up ARES from scratch without access to the team's hosted MongoDB Atlas or Supabase instances, follow this guide to provision and populate your own databases.

---

## 1. Configure Environment Variables

Copy `.env.example` to `.env` at the repository root:

```bash
cp .env.example .env
```

Set your MongoDB connection string and database name:

```env
MONGO_URI="mongodb+srv://<username>:<password>@<cluster-url>/?retryWrites=true&w=majority"
MONGO_DB="ares_base"
```

> **Local MongoDB option (Docker):**
> ```bash
> docker run -d --name ares-mongo -p 27017:27017 mongo:7
> ```
> Then use `MONGO_URI="mongodb://localhost:27017"` and `MONGO_DB="ares_base"` in `.env`.

---

## 2. Seed MongoDB (`backend/push_to_mongo.py`)

`backend/push_to_mongo.py` is **idempotent** (safe to re-run). It automatically:
- Creates all required `2dsphere` geospatial and uniqueness indexes (`ensure_indexes()`).
- Seeds `planet_profiles`, `source_register`, `map_layers`, `mars_landmarks`, and `mineral_signatures`.
- Fetches live NASA datasets directly from NASA MMGIS / Mars 2020 RSS APIs (`perseverance_waypoints`, `msl_waypoints`, and geotagged `perseverance_images`).
- Imports `themis_stamps` and `telemetry_rollups` from `sample_data/` if present (and skips gracefully if `sample_data/` is absent).

### Step A — Dry Run (no DB writes)

```bash
python backend/push_to_mongo.py --dry-run
```

### Step B — Populate All Collections

```bash
python backend/push_to_mongo.py --datasets all
```

### Step C — Optional: Seed Only Specific Datasets

```bash
python backend/push_to_mongo.py --datasets planet_profiles,map_layers,mars_landmarks,mineral_signatures,perseverance_waypoints,msl_waypoints
```

---

## 3. Optional: Set Up Supabase (Postgres + Storage)

If you also want to host compressed dataset bundles and relational telemetry tables in your own Supabase project:

1. Add your Supabase credentials to `.env`:
   ```env
   SUPABASE_URL="https://your-project.supabase.co"
   SUPABASE_PUBLISHABLE_KEY="sb_publishable_..."
   SUPABASE_SECRET_KEY="sb_secret_..."
   SUPABASE_JWKS_URL="https://your-project.supabase.co/auth/v1/.well-known/jwks.json"
   ```
2. Open the **Supabase SQL Editor** and run `backend/supabase_schema.sql` to create the tables and indexes.
3. Upload storage bundles and populate Postgres rows:
   ```bash
   python backend/push_to_supabase.py --mode storage
   python backend/push_to_supabase.py --mode tables
   ```

---

## 4. Verify Your Database

Start the server (or `docker compose up --build`) and verify:

```bash
curl http://127.0.0.1:8000/api/v1/health
curl http://127.0.0.1:8000/api/v1/layers
curl "http://127.0.0.1:8000/api/v1/map/features?slim=true&limit=10"
```

If `/api/v1/layers` returns `"status": "active"` and `/api/v1/map/features` returns GeoJSON features, your database is ready.
