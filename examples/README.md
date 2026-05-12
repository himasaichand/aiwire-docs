# Examples

Three self-contained end-to-end demos. Each one does the same flow:
parse a PDF → save the candidate → create a job → score the match →
save the application → show today's spend.

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
