# News Knowledge Graph (student project)

A nightly pipeline that ingests ~500 news articles a day, extracts named entities, resolves them against Wikidata, builds a knowledge graph in Neo4j, and serves a Next.js web app where you can search entities and explore their connections.

**Status:** in active development. See [`docs/ROADMAP.md`](docs/ROADMAP.md).

## Stack at a glance

- **Pipeline:** Python 3.11, spaCy (NER), Gemini Flash (event extraction), `feedparser`, GDELT
- **Storage:** Postgres on Neon (system of record + pgvector embeddings), Neo4j AuraDB Free (graph)
- **Web:** Next.js 15 (App Router), TypeScript, Tailwind, shadcn/ui, `react-force-graph`
- **Orchestration:** GitHub Actions scheduled workflow (nightly cron)
- **Hosting:** Vercel (web), GitHub Actions (pipeline)
- **Cost:** $0/month on free tiers

## Repo layout

```
news-kg/
├── README.md              ← you are here
├── CLAUDE.md              ← rules for AI coding agents (read this first if you're an agent)
├── docs/                  ← deep-dive design docs
│   ├── ARCHITECTURE.md
│   ├── DATA_MODEL.md
│   ├── ROADMAP.md
│   ├── ENTITY_RESOLUTION.md
│   └── PROMPTS.md
├── db/
│   └── schema.sql         ← Postgres schema (canonical)
├── pipeline/              ← Python ingestion + enrichment
├── web/                   ← Next.js app
└── .github/workflows/     ← cron job
```

## Getting started

1. Copy `.env.example` to `.env` and fill in credentials (Neon, Neo4j Aura, Gemini).
2. `cd pipeline && pip install -r requirements.txt && python -m spacy download en_core_web_trf`
3. Apply the schema: `psql $POSTGRES_URL -f db/schema.sql`
4. Run a one-off ingest: `python -m pipeline.run --since 24h`
5. `cd web && npm install && npm run dev`

Full setup details in [`pipeline/README.md`](pipeline/README.md) and [`web/README.md`](web/README.md).

## License

MIT (code). News article text is **never** stored or displayed in full — only headlines, snippets, and extracted structured data. See [`CLAUDE.md`](CLAUDE.md) for the legal rules every contributor must follow.
