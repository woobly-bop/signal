# Pipeline

The nightly batch that turns news articles into knowledge graph data.

## Setup

```bash
cd pipeline
python3.11 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python -m spacy download en_core_web_trf
```

Make sure `../.env` is filled in (see top-level `.env.example`).

## Run

```bash
# Full ingest of last 24 hours (~500 articles, ~10 minutes)
python -m pipeline.run --since 24h

# Only RSS sources
python -m pipeline.run --since 24h --sources rss

# Limit for testing
python -m pipeline.run --since 6h --limit 20

# Dry run (parse + enrich, but don't write to DB)
python -m pipeline.run --since 1h --dry-run

# Rebuild Neo4j from Postgres
python -m pipeline.sync_graph --full

# Evaluate entity resolution
python -m pipeline.eval.entity_resolution
```

## Module layout

```
pipeline/
├── pipeline/
│   ├── run.py                      ← CLI entry point
│   ├── sync_graph.py               ← Postgres → Neo4j sync
│   ├── config.py                   ← loads .env, exposes settings
│   ├── prompts.py                  ← loads prompts from docs/PROMPTS.md
│   ├── ingest/
│   │   ├── __init__.py             ← Source protocol + registry
│   │   ├── gdelt.py
│   │   ├── rss.py
│   │   └── rss_feeds.yaml          ← list of RSS feed URLs
│   ├── enrich/
│   │   ├── ner.py                  ← spaCy NER
│   │   ├── embed.py                ← MiniLM embeddings
│   │   └── event_extract.py        ← Gemini structured output
│   ├── resolve/
│   │   ├── wikidata.py             ← search API + cache
│   │   └── reranker.py             ← Stage 2 scoring
│   ├── store/
│   │   ├── postgres.py             ← all SQL lives here
│   │   └── neo4j.py                ← Cypher upserts
│   └── eval/
│       └── entity_resolution.py
├── tests/
│   ├── data/
│   │   └── gold_entities.jsonl     ← hand-labeled gold set
│   └── test_*.py
└── requirements.txt
```

## Conventions

- Every public function has type hints.
- Format before committing: `ruff format pipeline tests && ruff check pipeline tests --fix`.
- Logging: `structlog.get_logger(__name__)`. No `print`.
- DB writes go through `pipeline.store.postgres`. Don't put SQL in business logic.
- Idempotency: `INSERT ... ON CONFLICT DO NOTHING` or `... DO UPDATE`. The pipeline must be safe to re-run on the same time window.

## Where to add things

| Task | File |
|---|---|
| New RSS feed | `ingest/rss_feeds.yaml` |
| New source kind (e.g. an API) | New file in `ingest/`, register in `ingest/__init__.py` |
| Different NER model | `enrich/ner.py` |
| Tune resolution scoring | `resolve/reranker.py` |
| New event type | `enrich/event_extract.py` + add to Postgres enum + update `docs/PROMPTS.md` |
| New table | Edit `db/schema.sql`, add a migration in `db/migrations/`, update `store/postgres.py` |
