// End-to-end demo: parse a PDF, save the candidate, create a job,
// score the match, persist the application.
//
//   export AIWIRE_KEY="sk_live_YOUR_KEY"
//   node node.mjs ./resume.pdf "Senior ML Engineer"
//
// Requires Node 18+ (native fetch). Single file — copy into your project.

import { readFile } from "node:fs/promises";
import { randomUUID } from "node:crypto";

const BASE_URL = "https://aiwire-api.aiwire.workers.dev";
const apiKey = process.env.AIWIRE_KEY;
if (!apiKey) { console.error("set AIWIRE_KEY=sk_live_..."); process.exit(2); }

// Defaults to the bundled sample-resume.pdf if no path is given so this
// script runs end-to-end on a fresh clone with just `node node.mjs`.
const pdfPath  = process.argv[2] ?? new URL("./sample-resume.pdf", import.meta.url).pathname;
const jobTitle = process.argv[3] ?? "Senior ML Engineer";

// ─── Minimal client ──────────────────────────────────────────────────────
async function call(method, path, { body, idempotencyKey } = {}) {
  const headers = {
    "Authorization": `Bearer ${apiKey}`,
    "Content-Type": "application/json",
  };
  if (idempotencyKey) headers["Idempotency-Key"] = idempotencyKey;
  const res = await fetch(BASE_URL + path, {
    method,
    headers,
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  const requestId = res.headers.get("aiwire-request-id");
  const text = await res.text();
  let payload = null;
  try { payload = text ? JSON.parse(text) : null; } catch {}
  if (!res.ok) {
    throw new Error(`HTTP ${res.status} (${payload?.code ?? "unknown"}) — ${payload?.detail ?? text}\n   request_id: ${requestId}`);
  }
  return { data: payload, requestId };
}

// ─── End-to-end flow ─────────────────────────────────────────────────────

// 1. Parse the resume PDF.
const pdfBytes = await readFile(pdfPath);
const b64 = pdfBytes.toString("base64");
console.log("→ Parsing resume (~10-20 sec)...");
const { data: parsed } = await call("POST", "/v1/resumes/parse", {
  body: { base64: b64, media_type: "application/pdf" },
});
console.log(`  ✓ ${parsed.profile.name ?? "candidate"} parsed`);

// 2. Persist as a candidate.
const parts = (parsed.profile.name ?? "").split(" ", 2);
const { data: candidate } = await call("POST", "/v1/candidates", {
  idempotencyKey: randomUUID(),
  body: {
    external_id: `applicant_${randomUUID().slice(0, 8)}`,
    email: parsed.profile.email,
    first_name: parts[0],
    last_name: parts[1],
    profile: parsed.profile,
  },
});
console.log(`  ✓ Saved as ${candidate.id}`);

// 3. Create a job (auto-generated rubric).
console.log("→ Creating job + rubric (~3-5 sec)...");
const { data: job } = await call("POST", "/v1/jobs", {
  idempotencyKey: randomUUID(),
  body: {
    external_id: `req_${randomUUID().slice(0, 8)}`,
    title: jobTitle,
    description: `Hiring a ${jobTitle}. See team page for details.`,
  },
});
console.log(`  ✓ Job ${job.id}: ${job.rubric.competencies.length} competencies`);

// 4. Score the match.
console.log("→ Scoring (~3-5 sec)...");
const { data: score } = await call("POST", `/v1/jobs/${job.id}/match`, {
  body: { candidate_id: candidate.id },
});
console.log(`  ✓ Overall: ${(score.overall * 100).toFixed(0)}% — ${score.recommendation}`);
for (const [name, dim] of Object.entries(score.dimensions)) {
  console.log(`    ${name.padEnd(18)} ${(dim.score * 100).toFixed(0)}%  ${dim.evidence[0]?.slice(0, 70)}`);
}

// 5. Persist the (candidate, job) pairing.
const { data: app } = await call("POST", "/v1/applications", {
  idempotencyKey: randomUUID(),
  body: { candidate_id: candidate.id, job_id: job.id, source: "demo" },
});
console.log(`  ✓ Application ${app.id}`);

// 6. Set feed preferences + pull the personalised AI/ML news feed.
console.log("→ Setting feed preferences + fetching news feed...");
await call("PATCH", `/v1/candidates/${candidate.id}`, {
  body: { feed_preferences: { topics: ["papers", "models", "benchmarks"], keywords_exclude: ["computer vision"] } },
});
const { data: feed } = await call("GET", `/v1/candidates/${candidate.id}/feed?limit=5`);
console.log(`  ✓ ${feed.count} feed items (personalised on: ${(feed.personalisation?.domains ?? []).join(", ") || "profile defaults"})`);
for (const it of feed.items.slice(0, 5)) {
  console.log(`    [${it.relevance.toFixed(2)}] ${it.source.padEnd(11)} ${it.title.slice(0, 70)}`);
}

// 7. Show today's spend.
const { data: usage } = await call("GET", "/v1/usage/summary?days=1");
console.log(`\nToday: $${usage.totals.cost_usd.toFixed(4)} across ${usage.totals.calls} calls`);
