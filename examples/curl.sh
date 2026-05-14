#!/usr/bin/env bash
# End-to-end demo: parse a PDF, save the candidate, create a job,
# score the match, persist the application.
#
#   export AIWIRE_KEY="sk_live_YOUR_KEY"
#   bash curl.sh ./resume.pdf "Senior ML Engineer"
#
# Requires curl + jq.
set -euo pipefail

BASE_URL="https://aiwire-api.aiwire.workers.dev"
: "${AIWIRE_KEY:?set AIWIRE_KEY=sk_live_... in your env}"

# Defaults to the bundled sample-resume.pdf next to this script.
HERE="$(cd "$(dirname "$0")" && pwd)"
PDF_PATH="${1:-$HERE/sample-resume.pdf}"
JOB_TITLE="${2:-Senior ML Engineer}"

UUID() { uuidgen 2>/dev/null || python3 -c 'import uuid; print(uuid.uuid4())'; }

# 1. Parse the resume PDF.
echo "→ Parsing resume (~10-20 sec)..."
B64=$(base64 < "$PDF_PATH" | tr -d '\n')
PARSED=$(curl -sS -X POST "$BASE_URL/v1/resumes/parse" \
  -H "Authorization: Bearer $AIWIRE_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"base64\": \"$B64\", \"media_type\": \"application/pdf\"}")
PROFILE=$(echo "$PARSED" | jq -c .profile)
echo "  ✓ $(echo "$PROFILE" | jq -r '.name // "candidate"') parsed"

# 2. Persist as a candidate.
NAME=$(echo "$PROFILE" | jq -r '.name // ""')
FIRST=${NAME%% *}; LAST=${NAME#* }
CANDIDATE=$(curl -sS -X POST "$BASE_URL/v1/candidates" \
  -H "Authorization: Bearer $AIWIRE_KEY" \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: $(UUID)" \
  -d "$(jq -n --arg eid "applicant_$(UUID | cut -c1-8)" \
                --arg first "$FIRST" \
                --arg last  "$LAST" \
                --argjson profile "$PROFILE" \
                '{external_id:$eid, first_name:$first, last_name:$last, profile:$profile}')")
CAND_ID=$(echo "$CANDIDATE" | jq -r .id)
echo "  ✓ Saved as $CAND_ID"

# 3. Create a job (auto-generated rubric).
echo "→ Creating job + rubric (~3-5 sec)..."
JOB=$(curl -sS -X POST "$BASE_URL/v1/jobs" \
  -H "Authorization: Bearer $AIWIRE_KEY" \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: $(UUID)" \
  -d "$(jq -n --arg eid "req_$(UUID | cut -c1-8)" \
                --arg title "$JOB_TITLE" \
                '{external_id:$eid, title:$title, description: ("Hiring a " + $title + ". See team page for details.")}')")
JOB_ID=$(echo "$JOB" | jq -r .id)
N_COMP=$(echo "$JOB" | jq '.rubric.competencies | length')
echo "  ✓ Job $JOB_ID: $N_COMP competencies"

# 4. Score the match.
echo "→ Scoring (~3-5 sec)..."
SCORE=$(curl -sS -X POST "$BASE_URL/v1/jobs/$JOB_ID/match" \
  -H "Authorization: Bearer $AIWIRE_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"candidate_id\": \"$CAND_ID\"}")
OVERALL=$(echo "$SCORE" | jq -r '.overall * 100 | floor')
REC=$(echo "$SCORE" | jq -r .recommendation)
echo "  ✓ Overall: ${OVERALL}% — $REC"
echo "$SCORE" | jq -r '.dimensions | to_entries[] | "    \(.key) — \(.value.score * 100 | floor)% — \(.value.evidence[0] // "" | .[0:70])"'

# 5. Persist the (candidate, job) pairing.
APP=$(curl -sS -X POST "$BASE_URL/v1/applications" \
  -H "Authorization: Bearer $AIWIRE_KEY" \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: $(UUID)" \
  -d "{\"candidate_id\": \"$CAND_ID\", \"job_id\": \"$JOB_ID\", \"source\": \"demo\"}")
APP_ID=$(echo "$APP" | jq -r .id)
echo "  ✓ Application $APP_ID"

# 6. Set feed preferences + pull the personalised AI/ML news feed.
echo "→ Setting feed preferences + pulling feed..."
curl -sS -X PATCH "$BASE_URL/v1/candidates/$CAND_ID" \
  -H "Authorization: Bearer $AIWIRE_KEY" \
  -H "Content-Type: application/json" \
  -d '{"feed_preferences": {"topics": ["papers", "models", "benchmarks"], "keywords_exclude": ["computer vision"]}}' > /dev/null

FEED=$(curl -sS -H "Authorization: Bearer $AIWIRE_KEY" "$BASE_URL/v1/candidates/$CAND_ID/feed?limit=5")
FEED_COUNT=$(echo "$FEED" | jq -r .count)
DOMAINS=$(echo "$FEED" | jq -r '.personalisation.domains | join(", ")')
echo "  ✓ $FEED_COUNT feed items (personalised on: ${DOMAINS:-profile defaults})"
echo "$FEED" | jq -r '.items[] | "    [\(.relevance)] \(.source) — \(.title[0:70])"'

# 7. Show today's spend.
USAGE=$(curl -sS -H "Authorization: Bearer $AIWIRE_KEY" "$BASE_URL/v1/usage/summary?days=1")
TODAY_COST=$(echo "$USAGE" | jq -r '.totals.cost_usd')
TODAY_CALLS=$(echo "$USAGE" | jq -r '.totals.calls')
echo
echo "Today: \$$TODAY_COST across $TODAY_CALLS calls"
