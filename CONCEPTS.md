# Concepts (1-min read)

New here? This is the vocabulary AIWire uses everywhere. Skim this once and the rest of the docs will read smoothly.

[← Back to README](README.md)

---

## Profile

The structured version of a resume. Instead of a PDF you have to read line-by-line, you get a JSON object — name, location, skills, years of experience, education, AI/ML specializations, ATS score, three strengths, three gaps. Every important fact is backed by an exact quote from the resume so you can verify it didn't come from thin air.

## Rubric

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

## The 5 match dimensions

A rubric tells you what matters *for that specific job*. But every match score we return uses the **same 5 universal dimensions** so you can compare candidates across jobs:

| Dimension | What it answers |
|---|---|
| `skill_fit` | Does the candidate's tech stack match what the rubric demands? |
| `level` | Is their seniority right? (e.g., Junior vs Senior vs Principal) |
| `location` | Do they live where the job is, or is the job remote? |
| `salary` | Do their comp expectations fit the band? (when known) |
| `company_quality` | Where have they worked? Top-tier companies signal capability. |

You get a 0–1 score per dimension, an `overall` weighted average, a `recommendation` enum (`strong_yes` / `yes` / `mixed` / `no` / `strong_no`), and an evidence quote explaining each score.

## ATS score

"ATS" = **Applicant Tracking System** — the resume-parsing software big companies use to filter resumes *before* a human ever sees them (Workday, Greenhouse, Lever, etc.). Resumes with clean structure, action verbs, and keyword density score well; resumes with fancy graphics or non-standard headings often get auto-rejected.

Every parsed resume gets a 0–100 ATS score so you (or the candidate) know whether it'll survive that automated layer. Higher is better.

## Evidence quote

Every numeric or categorical claim AIWire makes comes with a verbatim quote from the source. If we say someone has 7 years of experience, you'll see `years_total_evidence: "Engineer at Flipkart, Jan 2018 – present"`. If we can't cite, the field is `null` — never a guess. This is the anti-hallucination guarantee.

## Stateless vs. stateful

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

## Gap

A skill / experience the candidate is missing for a given role. Each gap has a `severity` (`CRITICAL` / `HIGH` / `MEDIUM` / `LOW`) plus an optional `resource` recommendation (Coursera, fast.ai, etc.) so the candidate has a path forward. AIWire returns exactly 3 gaps per profile, ranked by impact.

## Strength

The mirror of a gap — a skill / pattern the candidate clearly demonstrates, backed by an evidence quote. Also exactly 3 per profile.

---

**Next:** [API reference →](API.md) &nbsp;·&nbsp; [Quickstart in README →](README.md#quickstart)
