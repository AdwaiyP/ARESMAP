-- Run this once in Supabase Dashboard -> SQL Editor to enable Postgres table sync
-- via `python backend/push_to_supabase.py --mode tables`.

create table if not exists public.planet_profiles (
  id text primary key,
  display_name text not null,
  trek_body_id text,
  crs jsonb not null,
  physics jsonb not null,
  clock_model jsonb not null,
  safety_thresholds jsonb not null
);

create table if not exists public.map_layers (
  layer_id text primary key,
  body text not null default 'mars',
  region text,
  category text,
  protocol text,
  url_template text not null,
  tile_size_px integer,
  zoom_range jsonb,
  resolution_m double precision,
  bbox jsonb
);

create table if not exists public.spatial_features (
  feature_id text primary key,
  body text not null default 'mars',
  mission_id text,
  feature_type text not null,
  lon double precision not null,
  lat double precision not null,
  elevation_m double precision,
  geometry jsonb not null,
  properties jsonb not null default '{}'::jsonb,
  provenance jsonb
);

create index if not exists idx_spatial_features_type on public.spatial_features (body, feature_type);
create index if not exists idx_spatial_features_lon_lat on public.spatial_features (lon, lat);

create table if not exists public.telemetry_rollups_lod (
  id text primary key,
  body text not null default 'mars',
  station_id text not null,
  lod text not null,
  bucket_key text not null,
  lmst_bucket text not null,
  ltst_start text,
  sclk_start double precision,
  sclk_end double precision,
  raw_samples_in_bucket integer,
  solar_zenith_deg_mean double precision,
  air_temp_c_mean double precision,
  ground_ir_temp_c_mean double precision,
  pressure_barocap1_pa_mean double precision,
  humidity_a_pct_mean double precision,
  optical_rds_top7_mean double precision,
  safety_state text,
  payload jsonb not null
);

create table if not exists public.raw_images (
  imageid text primary key,
  body text not null default 'mars',
  mission_id text,
  sol integer,
  site integer,
  drive integer,
  instrument text,
  lon double precision,
  lat double precision,
  date_taken_mars text,
  date_taken_utc text,
  image_files jsonb not null,
  camera jsonb,
  extended jsonb
);

create index if not exists idx_raw_images_sol on public.raw_images (sol desc, instrument);
