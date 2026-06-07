# Web

Next.js 15 (App Router) frontend for the News KG.

## Setup

```bash
cd web
npm install
npx shadcn@latest init        # accept defaults; pick "Slate" or "Zinc"
npx shadcn@latest add button card input badge skeleton
cp ../.env.example .env.local # then edit DATABASE_URL etc.
npm run dev
```

Open http://localhost:3000.

## Routes

| Path | What it shows |
|---|---|
| `/` | Search box, "latest activity" entity list, "today's events" list |
| `/entity/[id]` | Entity profile: header, timeline, related entities, graph view |
| `/event/[id]` | Event detail: type, summary, entities involved, source article |
| `/api/search?q=...` | Entity search (autocomplete) |
| `/api/graph/[id]` | 1-hop neighborhood as JSON for the force-graph |

## Conventions

- **Server components by default.** Add `'use client'` only when you need state, effects, or browser APIs (the force graph is the main case).
- Query Postgres directly from server components via `lib/db.ts`. No `/api` route needed unless the client also calls it.
- Query Neo4j only for traversal-heavy reads (graph view, "shortest path between X and Y"). Everything else is Postgres.
- Components in `components/` are app-specific. Pure shadcn primitives stay in `components/ui/` (where `shadcn add` puts them).
- Use Zod schemas to validate any data crossing a server/client boundary or coming from a query string.

## Folders

```
web/
├── app/
│   ├── layout.tsx
│   ├── page.tsx                    home / search
│   ├── entity/[id]/page.tsx
│   ├── event/[id]/page.tsx
│   ├── api/
│   │   ├── search/route.ts
│   │   └── graph/[id]/route.ts
│   └── globals.css
├── components/
│   ├── ui/                         shadcn primitives (generated)
│   ├── entity-card.tsx
│   ├── event-list.tsx
│   ├── graph-view.tsx              ← 'use client'
│   └── search-input.tsx            ← 'use client'
├── lib/
│   ├── db.ts                       pg pool
│   ├── graph.ts                    neo4j driver
│   ├── queries.ts                  typed query helpers
│   └── utils.ts                    cn(), formatters
└── public/
```

## Deploy

Push to GitHub. Connect the repo on Vercel — root directory `web/`. Add the env vars in the Vercel dashboard. Auto-deploys on every push to `main`; PR previews on every branch.
