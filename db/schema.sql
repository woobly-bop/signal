-- News KG — Postgres schema (system of record)
-- Apply with: psql $POSTGRES_URL -f db/schema.sql
-- Safe to re-run; uses IF NOT EXISTS where possible.

-- ─── Extensions ──────────────────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS pgcrypto;          -- gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS vector;            -- pgvector
CREATE EXTENSION IF NOT EXISTS pg_trgm;           -- trigram search on names

-- ─── Enums ───────────────────────────────────────────────────────────────────
DO $$ BEGIN
  CREATE TYPE entity_type AS ENUM (
    'person', 'organization', 'location', 'product', 'event', 'other'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE event_type AS ENUM (
    'fundraise',
    'acquisition',
    'exec_change',
    'product_launch',
    'partnership',
    'other'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ─── Sources ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS source (
  id              BIGSERIAL PRIMARY KEY,
  name            TEXT NOT NULL UNIQUE,           -- 'TechCrunch', 'Reuters', 'GDELT'
  kind            TEXT NOT NULL,                  -- 'rss' | 'gdelt' | 'api'
  url             TEXT,
  quality_score   REAL DEFAULT 0.5,               -- 0..1, tunable
  created_at      TIMESTAMPTZ DEFAULT now()
);

-- ─── Entities (canonical) ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS entity (
  id              BIGSERIAL PRIMARY KEY,
  type            entity_type NOT NULL,
  canonical_name  TEXT NOT NULL,
  wikidata_qid    TEXT UNIQUE,                    -- e.g. 'Q312' for Apple Inc.
  description     TEXT,
  metadata        JSONB DEFAULT '{}'::jsonb,      -- domain, tickers, industry, etc.
  embedding       vector(384),                    -- all-MiniLM-L6-v2
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS entity_canonical_name_trgm
  ON entity USING gin (canonical_name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS entity_type_idx ON entity (type);
CREATE INDEX IF NOT EXISTS entity_embedding_idx
  ON entity USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);

-- Aliases — every surface form we've seen that resolves to this entity
CREATE TABLE IF NOT EXISTS entity_alias (
  entity_id   BIGINT NOT NULL REFERENCES entity(id) ON DELETE CASCADE,
  alias       TEXT NOT NULL,
  alias_lower TEXT GENERATED ALWAYS AS (lower(alias)) STORED,
  source      TEXT,                               -- 'wikidata' | 'user' | 'extracted'
  PRIMARY KEY (entity_id, alias_lower)
);
CREATE INDEX IF NOT EXISTS entity_alias_lower_idx ON entity_alias (alias_lower);

-- ─── Articles ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS article (
  id              BIGSERIAL PRIMARY KEY,
  url             TEXT NOT NULL UNIQUE,
  canonical_url   TEXT,
  source_id       BIGINT REFERENCES source(id),
  title           TEXT NOT NULL,
  snippet         TEXT,                           -- ≤ 50 words, paraphrased
  language        TEXT DEFAULT 'en',
  published_at    TIMESTAMPTZ,
  ingested_at     TIMESTAMPTZ DEFAULT now(),
  simhash         BIGINT,                         -- for near-dup detection
  embedding       vector(384)
);
CREATE INDEX IF NOT EXISTS article_published_idx ON article (published_at DESC);
CREATE INDEX IF NOT EXISTS article_source_idx ON article (source_id);
CREATE INDEX IF NOT EXISTS article_embedding_idx
  ON article USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);

-- ─── Mentions (entity ↔ article) ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS mention (
  id          BIGSERIAL PRIMARY KEY,
  article_id  BIGINT NOT NULL REFERENCES article(id) ON DELETE CASCADE,
  entity_id   BIGINT NOT NULL REFERENCES entity(id) ON DELETE CASCADE,
  surface     TEXT NOT NULL,                     -- the exact text matched
  confidence  REAL NOT NULL,
  start_char  INT,
  end_char    INT,
  UNIQUE (article_id, entity_id, start_char)
);
CREATE INDEX IF NOT EXISTS mention_article_idx ON mention (article_id);
CREATE INDEX IF NOT EXISTS mention_entity_idx ON mention (entity_id);

-- ─── Events ──────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS event (
  id              BIGSERIAL PRIMARY KEY,
  type            event_type NOT NULL,
  article_id      BIGINT REFERENCES article(id) ON DELETE SET NULL,
  occurred_at     DATE,
  detected_at     TIMESTAMPTZ DEFAULT now(),
  monetary_value  NUMERIC,
  currency        TEXT,
  summary         TEXT,
  confidence      REAL NOT NULL,
  raw             JSONB                          -- the LLM's full structured output
);
CREATE INDEX IF NOT EXISTS event_type_idx ON event (type, occurred_at DESC);

CREATE TABLE IF NOT EXISTS event_entity (
  event_id    BIGINT NOT NULL REFERENCES event(id) ON DELETE CASCADE,
  entity_id   BIGINT NOT NULL REFERENCES entity(id) ON DELETE CASCADE,
  role        TEXT NOT NULL,                     -- 'actor', 'target', 'investor', ...
  PRIMARY KEY (event_id, entity_id, role)
);

-- ─── Pipeline run log (for debugging + freshness display) ────────────────────
CREATE TABLE IF NOT EXISTS pipeline_run (
  id              BIGSERIAL PRIMARY KEY,
  started_at      TIMESTAMPTZ DEFAULT now(),
  finished_at     TIMESTAMPTZ,
  status          TEXT,                          -- 'running' | 'success' | 'failed'
  articles_in     INT DEFAULT 0,
  articles_kept   INT DEFAULT 0,
  entities_new    INT DEFAULT 0,
  events_detected INT DEFAULT 0,
  notes           TEXT
);

-- ─── Seed sources ────────────────────────────────────────────────────────────
INSERT INTO source (name, kind, url, quality_score) VALUES
  ('GDELT',       'gdelt', 'https://www.gdeltproject.org/', 0.6),
  ('Reuters',     'rss',   'https://www.reuters.com/',       0.9),
  ('BBC News',    'rss',   'https://www.bbc.com/news',       0.9),
  ('TechCrunch',  'rss',   'https://techcrunch.com/',        0.7),
  ('Hacker News', 'rss',   'https://news.ycombinator.com/',  0.6)
ON CONFLICT (name) DO NOTHING;
