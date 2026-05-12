# Examples

Three self-contained end-to-end demos. Each one does the same flow:
parse a PDF → save candidate → create job → score match → save
application → show today's spend.

```bash
export AIWIRE_KEY="sk_live_YOUR_KEY"

bash curl.sh ./resume.pdf "Senior ML Engineer"
node node.mjs ./resume.pdf "Senior ML Engineer"
python python.py ./resume.pdf "Senior ML Engineer"
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
