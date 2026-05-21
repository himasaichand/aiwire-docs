# Examples

Three self-contained end-to-end demos. Each one does the same flow:
parse a PDF → save the candidate → create a job → score the match →
save the application → pull the personalised news feed → show today's spend.

A sample resume ([`sample-resume.pdf`](sample-resume.pdf)) ships next to
the scripts, so the simplest way to try the API is to run them with no
arguments:

```bash
export AIWIRE_KEY="sk_live_YOUR_KEY"

bash curl.sh
node node.mjs
python python.py
```

Pass your own PDF and job title to test other inputs:

```bash
bash curl.sh ./my-resume.pdf "Senior Data Scientist"
```

| File | Requirements |
|---|---|
| [`curl.sh`](curl.sh) | `curl` + `jq` |
| [`node.mjs`](node.mjs) | Node 18+ |
| [`python.py`](python.py) | Python 3.10+ and `pip install httpx` |

Each is a single file. Copy into your project and adapt.

Need a different language? The OpenAPI spec at
[`../openapi/openapi.yaml`](../openapi/openapi.yaml) generates clients
for 50+ languages via [openapi-generator](https://openapi-generator.tech).

---

## Stateless news feed (no candidate stored)

The demos above use the **stateful** feed (`GET /v1/candidates/{id}/feed`),
which reads a saved candidate's profile + preferences. If you'd rather keep
all user data in **your** system and store nothing with us, use the
**stateless** `POST /v1/recommendations` — pass the signals inline and we
persist nothing. Same response shape, same ranking. This call is **free**
(served from a cron-pulled cache, no LLM per request).

```bash
# curl
curl -sS -X POST "https://aiwire-api.aiwire.workers.dev/v1/recommendations" \
  -H "Authorization: Bearer $AIWIRE_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "profile": {
      "skills": ["pytorch", "rag"],
      "ai_ml": { "domain_specializations": ["nlp", "genai/llms"] },
      "experience_level": "Senior"
    },
    "preferences": { "topics": ["papers", "tools"], "keywords_exclude": ["robotics"] },
    "limit": 10
  }' | jq -r '.items[] | "[\(.relevance)] \(.source) — \(.title[0:70])"'
```

```js
// Node
const { data: feed } = await call("POST", "/v1/recommendations", {
  profile: {
    skills: ["pytorch", "rag"],
    ai_ml: { domain_specializations: ["nlp", "genai/llms"] },
    experience_level: "Senior",
  },
  preferences: { topics: ["papers", "tools"], keywords_exclude: ["robotics"] },
  limit: 10,
});
for (const it of feed.items) console.log(`[${it.relevance}] ${it.source} — ${it.title.slice(0, 70)}`);
```

```python
# Python
feed = call("POST", "/v1/recommendations", {
    "profile": {
        "skills": ["pytorch", "rag"],
        "ai_ml": {"domain_specializations": ["nlp", "genai/llms"]},
        "experience_level": "Senior",
    },
    "preferences": {"topics": ["papers", "tools"], "keywords_exclude": ["robotics"]},
    "limit": 10,
})
for it in feed["items"]:
    print(f"[{it['relevance']}] {it['source']} — {it['title'][:70]}")
```
