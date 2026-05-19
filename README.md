# AIWire

> A B2B API for AI-powered hiring. Resume PDFs → structured profiles,
> job descriptions → scoring rubrics, candidate × job → matches with
> evidence. One HTTP API.

```
Base URL    https://aiwire-api.aiwire.workers.dev
Auth        Authorization: Bearer sk_live_<your-key>
Support     chandugopisetty123@gmail.com
```

[**API reference →**](API.md) &nbsp;·&nbsp;
[**OpenAPI spec →**](openapi/openapi.yaml) &nbsp;·&nbsp;
[**Postman collection →**](openapi/postman_collection.json) &nbsp;·&nbsp;
[**Code examples →**](examples/)

---

## Concepts (1-min read)

New here? This is the vocabulary AIWire uses everywhere. Skim this once and the rest of the docs will read smoothly.

### Profile

The structured version of a resume. Instead of a PDF you have to read line-by-line, you get a JSON object — name, location, skills, years of experience, education, AI/ML specializations, ATS score, three strengths, three gaps. Every important fact is backed by an exact quote from the resume so you can verify it didn't come from thin air.

### Rubric

A rubric is what a hiring manager would normally scribble on a sticky note before interviews:
> *"For this role, I'll grade candidates on these 5 things, and here's how much each matters."*

AIWire writes the rubric for you from a plain-English job description, or you can pass your own.

For a "Senior ML Engineer" role, a generated rubric looks like:

| # | Competency | Weight | Must have | Nice to have |
|---|---|---|---|---|
| 1 | Production ML systems | 30% | PyTorch in production, distributed training | Kubernetes, Ray |
| 2 | ML breadth | 20% | NLP or CV experience | Recommender systems |
| 3 | Leadership | 20% | Led a team or owned a system | Mentored engineers |
| 4 | Engineering fundamentals | 15% | Distributed systems, on-call | Open-source contributions |
| 5 | Data fluency | 15% | SQL, experimentation | A/B testing platform |

Each row is one **competency**. Weights always sum to 1.0.

### The 5 match dimensions

A rubric tells you what matters *for that specific job*. But every match score we return uses the **same 5 universal dimensions** so you can compare candidates across jobs:

| Dimension | What it answers |
|---|---|
| `skill_fit` | Does the candidate's tech stack match what the rubric demands? |
| `level` | Is their seniority right? (e.g., Junior vs Senior vs Principal) |
| `location` | Do they live where the job is, or is the job remote? |
| `salary` | Do their comp expectations fit the band? (when known) |
| `company_quality` | Where have they worked? Top-tier companies signal capability. |

You get a 0–1 score per dimension, an `overall` weighted average, a `recommendation` enum (`strong_yes` / `yes` / `mixed` / `no` / `strong_no`), and an evidence quote explaining each score.

### ATS score

"ATS" = **Applicant Tracking System** — the resume-parsing software big companies use to filter resumes *before* a human ever sees them (Workday, Greenhouse, Lever, etc.). Resumes with clean structure, action verbs, and keyword density score well; resumes with fancy graphics or non-standard headings often get auto-rejected.

Every parsed resume gets a 0–100 ATS score so you (or the candidate) know whether it'll survive that automated layer. Higher is better.

### Evidence quote

Every numeric or categorical claim AIWire makes comes with a verbatim quote from the source. If we say someone has 7 years of experience, you'll see `years_total_evidence: "Engineer at Flipkart, Jan 2018 – present"`. If we can't cite, the field is `null` — never a guess. This is the anti-hallucination guarantee.

### Stateless vs. stateful

Two ways to call the same AI features. The result is identical; the difference is **who stores the data**.

**Stateful** — AIWire is the system of record. You create candidates and jobs in our database, then reference them by ID:
```
POST /v1/jobs/job_123/match
{ "candidate_id": "cand_456" }
```
Best when you're building a product on top of AIWire and want us to handle persistence.

**Stateless** — *your* database is the system of record. You pass the candidate profile and job inline; AIWire processes and returns; nothing is written to our DB:
```
POST /v1/match_scores
{ "candidate": { "profile": {...} }, "job": { "title": "...", "description": "...", "rubric": {...} } }
```
Best when your data must stay in your system (compliance, customer trust, simplicity).

Both produce the same response shape. Pick whichever fits your architecture.

### Gap

A skill / experience the candidate is missing for a given role. Each gap has a `severity` (`CRITICAL` / `HIGH` / `MEDIUM` / `LOW`) plus an optional `resource` recommendation (Coursera, fast.ai, etc.) so the candidate has a path forward. AIWire returns exactly 3 gaps per profile, ranked by impact.

### Strength

The mirror of a gap — a skill / pattern the candidate clearly demonstrates, backed by an evidence quote. Also exactly 3 per profile.

---

## What you can do

**Resume parsing.** Upload a PDF, get a 30-field structured profile —
skills, experience, education, AI/ML specializations, ATS score, three
strengths, three gaps. Every numeric claim comes with an evidence quote
from the resume. ~10–20 sec; ~$0.012 per call.

**Job rubric generation.** Send a plain-English job description, get a
weighted 5-competency scoring rubric. Or bring your own rubric.
~3–5 sec; ~$0.005 per call.

**Match scoring.** Score any (candidate, job) pair on five dimensions
— skill fit, level, location, salary, company quality — with evidence
quotes per dimension and a recommendation enum.
~3–5 sec; ~$0.005 per call.

**Persistence.** `/v1/candidates`, `/v1/jobs`, `/v1/applications` —
idempotent CRUD with cursor pagination. Free.

**Self-monitoring.** `/v1/usage/summary` for cost / error / latency
aggregates. `/v1/usage/recent` for the per-request audit log. Free.

**Personalised news feed.** Ranked stream of LLM papers (arxiv + HF
Daily Papers), new open-source models (HuggingFace), AI tools / launches
(HN), and LLM benchmarks (Open LLM Leaderboard). Two ways to call:
- `GET /v1/candidates/{id}/feed` — for stored candidates, uses their
  resume signals + `feed_preferences`.
- `POST /v1/recommendations` — **stateless**. Send personalisation signals
  in the body; we persist nothing, you never have to upload user PII to
  us. Same response shape.

Free. Cron-pulled cache, no per-call LLM cost.

**Stateless compute endpoints.** Every LLM-backed feature has a
**no-persist** variant so callers don't have to mirror their data to us:
- `POST /v1/rubrics` — JD text → 5-competency rubric
- `POST /v1/match_scores` — candidate profile + rubric → 5-dim score with
  evidence
- `POST /v1/recommendations` — signals → ranked news feed
- `POST /v1/resumes/parse` (already was stateless — `id` is transient)

Same LLM call, same response shape as the stateful versions. Nothing
about the request body is written to our DB.

**Baked in.** Bias firewall (no age / gender / caste / marital / etc.),
RFC 7807 errors with stable codes, `Idempotency-Key` headers, cursor
pagination, workspace isolation, rate limiting, signed request IDs on
every response.

---

## Quickstart

Get a key by emailing <chandugopisetty123@gmail.com>.

```bash
export AIWIRE_KEY="sk_live_YOUR_KEY"
```

**Verify the key:**

```bash
curl https://aiwire-api.aiwire.workers.dev/health
# → {"status":"ok","version":"...","timestamp":"..."}

curl -H "Authorization: Bearer $AIWIRE_KEY" \
  "https://aiwire-api.aiwire.workers.dev/v1/candidates?limit=5"
# → {"items":[],"has_more":false}
```

**Parse a resume.** This works copy-paste — points at a sample PDF we
host in this repo, so you'll see a real Profile come back:

```bash
curl -X POST https://aiwire-api.aiwire.workers.dev/v1/resumes/parse \
  -H "Authorization: Bearer $AIWIRE_KEY" \
  -H "Content-Type: application/json" \
  -d '{"url": "https://raw.githubusercontent.com/himasaichand/aiwire-docs/main/examples/sample-resume.pdf"}'
```

Returns a `Profile` with skills, experience, education, AI/ML signals,
ATS score, strengths, gaps, and per-section confidence. See
[`API.md`](API.md#resume-parsing) for the full field list.

**See your usage:**

```bash
curl -H "Authorization: Bearer $AIWIRE_KEY" \
  "https://aiwire-api.aiwire.workers.dev/v1/usage/summary?days=7"
```

End-to-end working scripts in [`examples/`](examples/) — pick curl, Node,
or Python.

---

## Endpoints at a glance

| Method | Path | Purpose |
|---|---|---|
| `GET` | [`/health`](API.md#health) | Liveness (no auth) |
| `POST` | [`/v1/resumes/parse`](API.md#resume-parsing) | PDF → structured Profile |
| `POST` | [`/v1/candidates`](API.md#candidates) | Upsert a candidate |
| `GET` | [`/v1/candidates`](API.md#candidates) | List candidates |
| `GET` | [`/v1/candidates/{id}`](API.md#candidates) | Get one |
| `POST` | [`/v1/jobs`](API.md#jobs) | Upsert a job (auto-rubric) |
| `GET` | [`/v1/jobs`](API.md#jobs) | List jobs |
| `GET` | [`/v1/jobs/{id}`](API.md#jobs) | Get one |
| `POST` | [`/v1/jobs/{id}/match`](API.md#match-scoring) | Score a candidate against a job |
| `POST` | [`/v1/applications`](API.md#applications) | Link a candidate to a job |
| `GET` | [`/v1/applications`](API.md#applications) | List applications |
| `GET` | [`/v1/usage/summary`](API.md#usage) | Aggregated usage |
| `GET` | [`/v1/usage/recent`](API.md#usage) | Per-request audit log |
| `GET` | [`/v1/candidates/{id}/feed`](API.md#news-feed) | Personalised feed for a stored candidate |
| `POST` | [`/v1/recommendations`](API.md#news-feed) | Stateless feed — signals in body, nothing persisted |
| `POST` | [`/v1/rubrics`](API.md#stateless-rubric-generation) | Stateless rubric generation — JD → rubric, nothing persisted |
| `POST` | [`/v1/match_scores`](API.md#stateless-match-scoring) | Stateless match scoring — profile + rubric → 5-dim score, nothing persisted |
| `PATCH` | [`/v1/candidates/{id}`](API.md#candidates) | Update feed preferences |

---

## Authentication

Send `Authorization: Bearer sk_live_<your-key>` on every `/v1/*` call.
Keep keys **server-side only** — never in frontend code, mobile apps, or
git. If a key leaks, email us; we revoke and reissue within minutes.

Every key resolves to one workspace. You can only see your own
workspace's data — cross-tenant access is technically impossible.

Errors: `401 unauthorized` (header missing/malformed), `403 forbidden`
(key invalid or revoked).

---

## Errors

We use [RFC 7807](https://datatracker.ietf.org/doc/html/rfc7807) — errors
come back as `Content-Type: application/problem+json`:

```json
{
  "type": "https://docs.aiwire.dev/errors/resume_parse_unavailable",
  "title": "Service Unavailable",
  "status": 503,
  "code": "resume_parse_unavailable",
  "detail": "Resume parsing failed: …",
  "request_id": "req_01KREF4X3VVWWJ8Y29WJQCCFGK"
}
```

Branch on `code`, not `detail` (detail wording may change). Every
response — success or failure — includes `Aiwire-Request-Id` in the
header; include it in support emails.

| Code | Status | When |
|---|---|---|
| `bad_request` | 400 | Body or query failed validation |
| `unauthorized` | 401 | Auth header missing/malformed |
| `forbidden` | 403 | Key invalid or revoked |
| `not_found` | 404 | Resource not in your workspace |
| `idempotency_key_mismatch` | 409 | Same key, different body |
| `resume_fetch_failed` | 422 | We couldn't download your PDF URL |
| `rate_limited` | 429 | More than 100 req/min/key — see `Retry-After` |
| `ai_parse_failed` | 502 | LLM returned invalid JSON even after retry. Safe to retry. |
| `resume_parse_unavailable` | 503 | Upstream (Anthropic, DB) is down |

For debugging, hit `GET /v1/usage/recent?status=errors` — you'll see
your most recent failures with status codes, latency, and the
`request_id` for each.

---

## Conventions

**Idempotency.** Send `Idempotency-Key: <uuid>` on any `POST`. Same key
+ same body → cached response (24h). Same key + different body →
`409 idempotency_key_mismatch`.

**Rate limit.** 100 requests / minute / key. On `429` you get
`Retry-After: <seconds>` plus `RateLimit-Remaining` and `RateLimit-Reset`
headers. Email us if you need a higher limit.

**Pagination.** All list endpoints use cursor pagination:

```bash
curl "...?limit=50"           # → { items, next_cursor, has_more }
curl "...?limit=50&cursor=eyJ..."
```

Default `limit=50`, max `100`. Cursors are opaque — don't decode.

**IDs.** Prefixed Crockford base32. `ws_*` (workspace, derived from key),
`cand_*`, `job_*`, `app_*`, `req_*` (in `Aiwire-Request-Id` header).

**Versioning.** Path-prefixed `/v1/`. When we ship v2 it'll live at
`/v2/` and `/v1/` will continue to work for at least 12 months.

---

## Coming next

- **Webhooks** — `resume.parsed`, `candidate.created`, `match.scored`
- **TypeScript SDK** — auto-generated from the OpenAPI spec
- **Self-serve key rotation** — POST to rotate, instant overlap

If you want any of these sooner, tell us.

---

## Pricing

Pay per call, no monthly minimum during pilot.

| Endpoint | Cost |
|---|---|
| `POST /v1/resumes/parse` | ~$0.012 |
| `POST /v1/jobs` (with auto-rubric) | ~$0.005 |
| `POST /v1/jobs/{id}/match` | ~$0.005 |
| Everything else (lists, gets, applications, usage) | Free |

Authoritative number is whatever `/v1/usage/summary` returns for the
billing month.

---

## Support

Email <chandugopisetty123@gmail.com>. Include the `Aiwire-Request-Id`
header from any failing call — we can pull the full trace in seconds.

---

License: documentation Apache 2.0 ([`LICENSE`](LICENSE)). The API itself is a hosted service.
