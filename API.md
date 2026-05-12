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
  -d '{"url": "https://example.com/resume.pdf"}'

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
- `gaps[*].severity`: `CRITICAL | HIGH | MEDIUM`

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
