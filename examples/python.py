"""End-to-end demo: parse a PDF, save the candidate, create a job,
score the match, persist the application.

  export AIWIRE_KEY="sk_live_YOUR_KEY"
  pip install httpx
  python python.py ./resume.pdf "Senior ML Engineer"

Single file. Copy into your project.
"""
from __future__ import annotations

import base64
import json
import os
import sys
import uuid
from pathlib import Path

import httpx

BASE_URL = "https://aiwire-api.aiwire.workers.dev"


def main() -> int:
    api_key = os.environ.get("AIWIRE_KEY")
    if not api_key:
        print("set AIWIRE_KEY=sk_live_...", file=sys.stderr)
        return 2
    if len(sys.argv) < 3:
        print("usage: python python.py <pdf> <job-title>", file=sys.stderr)
        return 2
    pdf_path, job_title = Path(sys.argv[1]), sys.argv[2]

    client = httpx.Client(
        base_url=BASE_URL,
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
        timeout=60.0,
    )

    def call(method: str, path: str, body=None, idempotency_key=None):
        headers = {"Idempotency-Key": idempotency_key} if idempotency_key else {}
        r = client.request(method, path, json=body, headers=headers)
        req_id = r.headers.get("aiwire-request-id")
        try:
            payload = r.json() if r.text else None
        except json.JSONDecodeError:
            payload = None
        if not r.is_success:
            code = (payload or {}).get("code", "unknown")
            detail = (payload or {}).get("detail", r.text[:200])
            raise RuntimeError(f"HTTP {r.status_code} ({code}) — {detail}\n   request_id: {req_id}")
        return payload

    # 1. Parse the resume.
    print("→ Parsing resume (~10-20 sec)...")
    b64 = base64.b64encode(pdf_path.read_bytes()).decode("ascii")
    parsed = call("POST", "/v1/resumes/parse", {"base64": b64, "media_type": "application/pdf"})
    print(f"  ✓ {parsed['profile'].get('name', 'candidate')} parsed")

    # 2. Persist the candidate.
    parts = (parsed["profile"].get("name") or "").split(" ", 1)
    candidate = call(
        "POST",
        "/v1/candidates",
        {
            "external_id": f"applicant_{uuid.uuid4().hex[:8]}",
            "email": parsed["profile"].get("email"),
            "first_name": parts[0] if parts else None,
            "last_name": parts[1] if len(parts) > 1 else None,
            "profile": parsed["profile"],
        },
        idempotency_key=str(uuid.uuid4()),
    )
    print(f"  ✓ Saved as {candidate['id']}")

    # 3. Create a job.
    print("→ Creating job + rubric (~3-5 sec)...")
    job = call(
        "POST",
        "/v1/jobs",
        {
            "external_id": f"req_{uuid.uuid4().hex[:8]}",
            "title": job_title,
            "description": f"Hiring a {job_title}. See team page for details.",
        },
        idempotency_key=str(uuid.uuid4()),
    )
    print(f"  ✓ Job {job['id']}: {len(job['rubric']['competencies'])} competencies")

    # 4. Score.
    print("→ Scoring (~3-5 sec)...")
    score = call("POST", f"/v1/jobs/{job['id']}/match", {"candidate_id": candidate["id"]})
    pct = int(score["overall"] * 100)
    print(f"  ✓ Overall: {pct}% — {score['recommendation']}")
    for name, dim in score["dimensions"].items():
        ev = dim["evidence"][0] if dim["evidence"] else ""
        print(f"    {name:<18} {int(dim['score'] * 100):>3}%  {ev[:70]}")

    # 5. Save the pairing.
    app = call(
        "POST",
        "/v1/applications",
        {"candidate_id": candidate["id"], "job_id": job["id"], "source": "demo"},
        idempotency_key=str(uuid.uuid4()),
    )
    print(f"  ✓ Application {app['id']}")

    # 6. Today's spend.
    usage = call("GET", "/v1/usage/summary?days=1")
    print(f"\nToday: ${usage['totals']['cost_usd']:.4f} across {usage['totals']['calls']} calls")
    return 0


if __name__ == "__main__":
    sys.exit(main())
