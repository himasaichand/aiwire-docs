# API reference

Every endpoint, with a working example. For the machine-readable version,
see [`openapi/openapi.yaml`](openapi/openapi.yaml).

**Base URL:** `https://aiwire-api.aiwire.workers.dev`
**Auth:** `Authorization: Bearer sk_live_<your-key>` on every `/v1/*` call.

For auth, errors, rate limits, idempotency, pagination, IDs, and
versioning — see [the README](README.md). This file is endpoint
specifications only.

---

## Health

### `GET /health`

Liveness probe. **No auth required.**

```bash
curl https://aiwire-api.aiwire.workers.dev/health
```

```json
{
  "status": "ok",
  "version": "1.0.0",
  "environment": "production",
  "timestamp": "2026-05-12T16:53:52.000Z"
}
```

---

## Resume parsing

### `POST /v1/resumes/parse`

Parse a resume PDF into a 30-field structured profile. ~10–20 sec; ~$0.012.

Send a URL **or** a base64-encoded PDF:

```bash
# URL
curl -X POST https://aiwire-api.aiwire.workers.dev/v1/resumes/parse \
  -H "Authorization: Bearer $AIWIRE_KEY" \
  -H "Content-Type: application/json" \
  -d '{"url": "https://raw.githubusercontent.com/himasaichand/aiwire-docs/main/examples/sample-resume.pdf"}'

# Or base64
curl -X POST https://aiwire-api.aiwire.workers.dev/v1/resumes/parse \
  -H "Authorization: Bearer $AIWIRE_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"base64\": \"$(base64 < resume.pdf | tr -d '\n')\", \"media_type\": \"application/pdf\"}"
```

Returns `{ id, workspace_id, profile, source, confidence }`.

> ⚠️ The `id` returned here is **transient** — call `POST /v1/candidates`
> with the profile to persist.

The `profile` object has ~30 fields. Highlights:

```json
{
  "name": "Alex Doe",
  "country_code": "in",
  "current_title": "Senior ML Engineer",
  "experience_level": "Senior",

  "years_total": 6,
  "years_total_evidence": "First job 2018-07, latest 2024-03 → ~6y",

  "skills": ["Python", "PyTorch", "AWS"],

  "education": [{
    "institution": "IIT Bombay",
    "institution_tier": "tier_1"
  }],

  "ai_ml": {
    "ai_ml_years": 4,
    "ai_ml_years_evidence": "Joined ML team Apr 2022, current → ~4y",
    "domain_specializations": ["NLP", "GenAI/LLMs"],
    "has_llm_experience": true,
    "llm_evidence": ["Built RAG over 5M docs at 100 RPS"]
  },

  "ats": {
    "score": 92,
    "score_rationale": "Strong action verbs + 6 quantified results."
  },

  "compensation": {
    "current_ctc": { "value": 3200000, "currency": "INR", "period": "annual" },
    "notice_period_days": 60,
    "evidence": "Current CTC: ₹32 LPA · Notice: 60 days"
  },

  "strengths": [
    { "strength": "Production LLM systems", "evidence": "Built RAG over 5M docs" }
  ],
  "gaps": [
    { "name": "Distributed training", "severity": "MEDIUM", "time_to_close": "8 weeks" }
  ],

  "confidence": {
    "overall": 0.86, "identity": 0.95, "experience": 0.90,
    "education": 0.92, "ats": 0.80, "ai_ml": 0.88, "compensation": 0.95
  }
}
```

**Anti-hallucination rules baked in:**
- Numeric claims (`years_total`, `ai_ml_years`, `ats.score`, all
  compensation fields) come with an evidence quote. If we can't quote,
  we return `null`.
- `confidence` is per-section, 0–1. Treat as **ordinal** — section ≤ 0.6
  → flag for human review. Don't surface raw percentages.
- **Bias firewall**: we don't extract age, gender, caste, marital
  status, religion, race, disability, sexual orientation, political
  affiliation, or parental status. No fields exist for these.
- **Compensation is extractive only** — never inferred from title.

**Closed vocabularies:**
- `experience_level`: `Junior | Mid | Senior | Lead | Principal | Director`
- `ai_ml.domain_specializations[*]`: `NLP | Computer Vision | Recommendations | Reinforcement Learning | MLOps | GenAI/LLMs | Speech | Time Series | Tabular ML | Robotics | Search/Retrieval | Fraud/Anomaly | Edge/On-device`
- `education[*].institution_tier`: `tier_1 | tier_2 | tier_3 | unranked` (India-aware: IIT/IISc/IIIT-H/BITS/IIM-A-B-C = tier_1; NITs/other-IIITs = tier_2)
- `gaps[*].severity`: `CRITICAL | HIGH | MEDIUM | LOW`

---

## Candidates

A candidate is a persistent person record, keyed by **your** `external_id`.

### `POST /v1/candidates` — upsert

Idempotent on `(workspace, external_id)`.

```bash
curl -X POST https://aiwire-api.aiwire.workers.dev/v1/candidates \
  -H "Authorization: Bearer $AIWIRE_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "external_id": "applicant_42",
    "email": "alex@example.com",
    "first_name": "Alex",
    "last_name": "Doe",
    "profile": { /* the profile from /v1/resumes/parse */ }
  }'
```

Returns the full `Candidate` object.

### `GET /v1/candidates` — list

Cursor-paginated, newest first.

```bash
curl -H "Authorization: Bearer $AIWIRE_KEY" \
  "https://aiwire-api.aiwire.workers.dev/v1/candidates?limit=50"
# → { "items": [...], "next_cursor": "eyJ...", "has_more": true }
```

### `GET /v1/candidates/{id}` — get one

`404 not_found` if the id isn't in your workspace.

### `PATCH /v1/candidates/{id}` — update feed preferences

Partial update. Today supports `feed_preferences` only. Merge semantics:
keys you omit retain their existing values, so you can flip just `paused`
without re-sending the whole prefs object.

```bash
curl -X PATCH https://aiwire-api.aiwire.workers.dev/v1/candidates/$CAND_ID \
  -H "Authorization: Bearer $AIWIRE_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "feed_preferences": {
      "topics": ["papers", "models"],
      "domains": ["nlp", "genai/llms"],
      "keywords_exclude": ["computer vision"],
      "paused": false
    }
  }'
```

| Field | Type | Notes |
|---|---|---|
| `topics` | `("papers" \| "tools" \| "models" \| "benchmarks")[]` | Empty = all four |
| `domains` | `string[]` | Overrides `profile.ai_ml.domain_specializations` when non-empty |
| `keywords_include` | `string[]` | Extra keywords to boost in ranking |
| `keywords_exclude` | `string[]` | Hard penalty (-5.0 relevance) for items matching any of these |
| `paused` | `boolean` | `true` → feed endpoint returns an empty list |

---

## Jobs

A job is a persistent requisition with an AI-generated scoring rubric.

### `POST /v1/jobs` — upsert (auto-generates rubric)

If you omit `rubric`, we synthesize one from the description (~3–5 sec; ~$0.005).

```bash
curl -X POST https://aiwire-api.aiwire.workers.dev/v1/jobs \
  -H "Authorization: Bearer $AIWIRE_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "external_id": "req_001",
    "title": "Senior ML Engineer",
    "description": "Hiring a Senior ML Engineer. PyTorch, MLOps, 5+ years. Remote India."
  }'
```

The synthesized rubric has 5 competencies whose weights sum to 1.0:

```json
{
  "competencies": [
    {
      "name": "Production ML systems",
      "weight": 0.30,
      "must_have": ["PyTorch in production", "Distributed training"],
      "nice_to_have": ["Kubernetes", "Ray"]
    }
    /* 4 more */
  ]
}
```

Pass your own `rubric` to skip the LLM call.

### `GET /v1/jobs` — list

### `GET /v1/jobs/{id}` — get one

---

## Match scoring

### `POST /v1/jobs/{id}/match`

Score a candidate against this job. 5 dimensions with evidence quotes per
dimension. ~3–5 sec; ~$0.005.

```bash
curl -X POST https://aiwire-api.aiwire.workers.dev/v1/jobs/$JOB_ID/match \
  -H "Authorization: Bearer $AIWIRE_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"candidate_id\": \"$CAND_ID\"}"
```

```json
{
  "overall": 0.78,
  "dimensions": {
    "skill_fit":       { "score": 0.85, "evidence": ["..."] },
    "level":           { "score": 0.90, "evidence": ["..."] },
    "location":        { "score": 0.95, "evidence": ["..."] },
    "salary":          { "score": 0.50, "evidence": ["..."] },
    "company_quality": { "score": 0.70, "evidence": ["..."] }
  },
  "recommendation": "yes",
  "confidence": 0.82
}
```

`recommendation` is one of `strong_yes | yes | mixed | no | strong_no`.

Optionally override rubric weights for this scoring call only:

```json
{
  "candidate_id": "cand_...",
  "weights": {
    "skill_fit": 0.4, "level": 0.2, "location": 0.1,
    "salary": 0.15, "company_quality": 0.15
  }
}
```

---

## Stateless rubric generation

### `POST /v1/rubrics`

Same LLM call as `POST /v1/jobs` (with auto-rubric), but **nothing is
persisted** — no job row, no rubric stored. Caller composes with
`POST /v1/match_scores` to score a candidate against the returned rubric.

```bash
curl -X POST https://aiwire-api.aiwire.workers.dev/v1/rubrics \
  -H "Authorization: Bearer $AIWIRE_KEY" \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: $(uuidgen)" \
  -d '{
    "title": "Senior ML Engineer",
    "description": "5+ years building production ML systems, PyTorch, MLOps, distributed training. Remote India."
  }'
```

Returns:

```json
{
  "rubric": {
    "competencies": [
      { "name": "Production ML Systems Design", "weight": 0.28, "must_have": [...], "nice_to_have": [...] },
      { "name": "Deep Learning Frameworks & Implementation", "weight": 0.25, ... }
    ]
  },
  "model_version": "claude-haiku-4-5-20251001"
}
```

~3–5 sec; ~$0.005 per call.

---

## Stateless match scoring

### `POST /v1/match_scores`

Same 5-dim scoring as `POST /v1/jobs/{id}/match`, but **nothing is
persisted**. Pass the candidate profile + rubric inline.

```bash
curl -X POST https://aiwire-api.aiwire.workers.dev/v1/match_scores \
  -H "Authorization: Bearer $AIWIRE_KEY" \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: $(uuidgen)" \
  -d '{
    "candidate": {
      "profile": { /* the full profile from /v1/resumes/parse, or any subset */ }
    },
    "job": {
      "title": "Senior ML Engineer",
      "description": "...",
      "rubric": { /* from /v1/rubrics */ }
    },
    "weights": {
      "skill_fit": 0.4, "level": 0.2,
      "location": 0.1, "salary": 0.15, "company_quality": 0.15
    }
  }'
```

Returns the standard `MatchScore` (overall, dimensions, recommendation,
confidence) **plus** the echo block:

```json
{
  "overall": 0.78,
  "dimensions": { /* 5 dims with evidence */ },
  "recommendation": "yes",
  "confidence": 0.82,
  "rubric_used": { /* the exact rubric the LLM scored against */ },
  "weights_used": { "skill_fit": 0.4, ... },
  "model_version": "claude-haiku-4-5-20251001"
}
```

**Why the echo?** When you pass a `weights` override, you can't tell
from `overall` alone whether the shift came from the candidate's
profile or your weight choice. The echoed `rubric_used` +
`weights_used` let you diff what you sent against what was scored.

~3–5 sec; ~$0.005 per call.

---

## Applications

An application links a candidate to a job, with optional `match_score`,
`stage`, and `status`.

### `POST /v1/applications` — create

Idempotent on the `(candidate_id, job_id)` pairing.

```bash
curl -X POST https://aiwire-api.aiwire.workers.dev/v1/applications \
  -H "Authorization: Bearer $AIWIRE_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"candidate_id\": \"$CAND_ID\", \"job_id\": \"$JOB_ID\", \"source\": \"career_page\"}"
```

| Field | Default | Values |
|---|---|---|
| `stage` | `applied` | Free-form (`applied`, `screened`, `phone_screen`, `onsite`, `offer`, `hired`) |
| `status` | `active` | `active | hired | rejected` |

### `GET /v1/applications` — list

---

## News feed

Personalised AI/ML news stream per candidate. Returns recent items from a
**cron-pulled cache** of five free sources: arxiv preprints (cs.CL / cs.LG /
cs.AI / cs.CV), HuggingFace Daily Papers, trending HuggingFace models,
HackerNews AI tool stories, and the Open LLM Leaderboard. No LLM call
per request — ranking is deterministic + cheap.

### `POST /v1/recommendations` — stateless

> Renamed from `POST /v1/feed/recommend` on 2026-05-15. The old URL
> still works through 2026-06-15 but returns the standard
> `Deprecation: true` / `Sunset` / `Link` headers. Update integrations
> to the new URL.

Same ranked feed, but with the personalisation signals passed inline.
**We do not persist any part of the request body.** Use this when you
want to serve a feed to every user on your platform without creating
candidate records (no PII upload, no data duplication).

```bash
curl -X POST https://aiwire-api.aiwire.workers.dev/v1/feed/recommend \
  -H "Authorization: Bearer $AIWIRE_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "profile": {
      "skills": ["pytorch", "rag", "vllm"],
      "ai_ml": { "domain_specializations": ["nlp", "genai/llms"] },
      "experience_level": "Senior",
      "years_total": 6
    },
    "preferences": {
      "topics": ["papers", "models"],
      "keywords_exclude": ["computer vision"]
    },
    "limit": 20
  }'
```

Every body field is **optional**. Pass as little or as much as you have:

| Body | Result |
|---|---|
| `{}` | Recency-only feed across all sources |
| `{"preferences": {"topics": ["papers"]}}` | Papers boosted to the top |
| `{"profile": {"ai_ml": {"domain_specializations": ["nlp"]}}}` | NLP-aligned items boosted |
| Full body (above) | Maximum personalisation |

Response is identical to the candidate-scoped endpoint **minus** the
`candidate_id` field (since none was provided). `personalisation` still
echoes back what the ranker actually used so you can debug.

### `GET /v1/candidates/{id}/feed`

```bash
curl -H "Authorization: Bearer $AIWIRE_KEY" \
  "https://aiwire-api.aiwire.workers.dev/v1/candidates/$CAND_ID/feed?limit=20"
```

Query params:

| Param | Default | Notes |
|---|---|---|
| `limit` | 20 | Max 50 |
| `cursor` | — | ISO timestamp; returns items strictly older than this |
| `topic` | — | Filter to one of `papers`, `tools`, `models`, `benchmarks` |

Response:

```json
{
  "candidate_id": "cand_01K...",
  "count": 20,
  "has_more": true,
  "next_cursor": "2026-05-13T08:15:00.000Z",
  "personalisation": {
    "topics": ["papers", "models"],
    "domains": ["nlp", "genai/llms"],
    "experience_level": "Senior",
    "years_total": 6
  },
  "items": [
    {
      "id": "feed_...",
      "source": "arxiv",
      "url": "https://arxiv.org/abs/2405.12345",
      "title": "Chain-of-Thought with Tool Use",
      "summary": "We show that letting an LLM call tools during reasoning improves benchmark performance",
      "topics": ["papers", "benchmarks"],
      "keywords": ["genai/llms"],
      "published_at": "2026-05-13T10:14:00.000Z",
      "relevance": 4.30,
      "image_url": "https://paper-assets.alphaxiv.org/image/2405.12345v1.png",
      "meta": { "categories": ["cs.CL"] }
    }
  ]
}
```

### Thumbnails (`image_url`)

Every item carries a thumbnail URL set deterministically at ingest:

| Source | Thumbnail source | Format |
|---|---|---|
| `arxiv` | `paper-assets.alphaxiv.org/image/<id>v1.png` (alphaXiv first-figure) | PNG |
| `hf_papers` | `paper.mediaUrls[0]` when present, else HF social-thumbnails CDN | PNG |
| `hf_models` | `cdn-thumbnails.huggingface.co/social-thumbnails/models/<id>.png` | PNG |
| `hn` | Real og:image / twitter:image extracted from the linked page | varies |
| `hn` (fallback) | Generated SVG card with title + favicon (when no og:image) | `data:image/svg+xml` |
| `leaderboard` | Generated SVG sparkline of MMLU / IFEval / GPQA / Avg scores | `data:image/svg+xml` |

Render with an `onerror` fallback — a remote URL can 404 (rare for HF /
alphaXiv, more common for HN-linked sites). Example:

```html
<img src="${item.image_url}" onerror="this.style.display='none'" />
```

### How ranking works

The formula is straightforward and printed in the response so you can debug
surprising results:

```
relevance =
   2.0 * (item.topics  ∩ preferences.topics)             explicit pref wins
 + 1.0 * (item.keywords ∩ candidate.domains)             resume signal
 + 0.5 * (item.keywords ∩ candidate.skills)              technical alignment
 + 1.0 * (item.keywords ∩ preferences.keywords_include)
 - 5.0 * (item.keywords ∩ preferences.keywords_exclude)  hard penalty
 + recency_boost(published_at)                            <1d=+1.0, <7d=+0.3, older=0
```

Items with negative relevance are filtered out. Final sort: relevance DESC,
then `published_at` DESC.

### How personalisation is derived

In order of precedence:

1. **Explicit preferences** (`PATCH /v1/candidates/{id}` — see [Candidates](#candidates)).
2. **Resume signals** — `profile.ai_ml.domain_specializations`, `profile.skills`,
   `profile.experience_level`, `profile.years_total`.

> **Note on age.** The parser deliberately doesn't extract age or date of
> birth (bias firewall). Career-stage personalisation uses `experience_level`
> and `years_total` instead — this is strictly more useful than age and
> doesn't introduce protected-attribute exposure.

### Pausing the feed

```bash
curl -X PATCH .../v1/candidates/$CAND_ID \
  -d '{"feed_preferences":{"paused":true}}'
```

The feed endpoint then returns `{ count: 0, items: [], paused: true }`.

### Source cadence

The cron-pulled cache refreshes on this schedule:

| Source | Cadence | Why |
|---|---|---|
| HN AI tool stories | hourly | News is fast-moving |
| HuggingFace trending models | hourly | Releases happen any time |
| arxiv preprints (cs.CL / cs.LG / cs.AI / cs.CV) | every 6h | Papers don't churn faster than that |
| HuggingFace Daily Papers | every 6h | Daily set, low frequency |
| Open LLM Leaderboard | daily 06:00 UTC | Snapshot of the day's leaderboard |

A new item shows up in the feed within one cadence window of being posted at
source. You don't need to do anything to refresh — just call the endpoint.

---

## Usage

Your workspace's own observability. Source of truth for billing.

### `GET /v1/usage/summary?days=N`

Aggregated over the last N days (1–90, default 30).

```bash
curl -H "Authorization: Bearer $AIWIRE_KEY" \
  "https://aiwire-api.aiwire.workers.dev/v1/usage/summary?days=7"
```

```json
{
  "window_days": 7,
  "workspace_id": "ws_yours",
  "totals": {
    "calls": 234, "cost_usd": 0.612,
    "tokens_in": 187204, "tokens_out": 84310,
    "errors": 3, "error_rate": 0.0128
  },
  "by_endpoint": [
    {
      "endpoint": "v1.resumes.parse",
      "calls": 12, "cost_usd": 0.137,
      "errors": 1, "avg_latency_ms": 19822
    }
  ],
  "by_day": [
    { "day": "2026-05-12", "calls": 45, "cost_usd": 0.087, "errors": 0 }
  ],
  "by_status": [
    { "bucket": "2xx", "count": 231 },
    { "bucket": "5xx", "count": 2 }
  ]
}
```

### `GET /v1/usage/recent`

Per-request log. Use this when summary shows errors and you need to find
which specific requests failed.

```bash
# Last 50 requests
curl -H "Authorization: Bearer $AIWIRE_KEY" \
  "https://aiwire-api.aiwire.workers.dev/v1/usage/recent?limit=50"

# Only failures
curl -H "Authorization: Bearer $AIWIRE_KEY" \
  "https://aiwire-api.aiwire.workers.dev/v1/usage/recent?status=errors"

# Filter by endpoint substring
curl -H "Authorization: Bearer $AIWIRE_KEY" \
  "https://aiwire-api.aiwire.workers.dev/v1/usage/recent?endpoint=parse"
```

Each row carries `timestamp`, `endpoint`, `status_code`, `latency_ms`,
`cost_usd`, `tokens_in`, `tokens_out`, `request_id`.

> Note: we deliberately don't store request/response bodies (PII).
> Email us with a `request_id` if you need a full trace.
