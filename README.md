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

**Personalised news feed.** `GET /v1/candidates/{id}/feed` returns a
ranked stream of LLM papers (arxiv + HF Daily Papers), new open-source
models (HuggingFace), AI tools / launches (HN), and LLM benchmarks
(Open LLM Leaderboard). Personalisation is driven by the candidate's
resume signals + explicit `feed_preferences` (`PATCH /v1/candidates/{id}`).
Free. Cron-pulled cache, no per-call LLM cost.

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
| `GET` | [`/v1/candidates/{id}/feed`](API.md#news-feed) | Personalised AI/ML news feed |
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
