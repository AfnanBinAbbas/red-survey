#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/checkpoint.sh"

parse_common_args "$@"
init_workspace

if skip_if_checkpoint "survey/hosts.json" "survey"; then mark_phase_done survey; exit 0; fi

require_tools nmap curl python3

HOST="$(target_host)"
URL="$(target_url)"
S="$WS/survey"
mkdir -p "$S"
CTF_ARGS=""
[[ "$MODE" == "ctf" ]] && CTF_ARGS="--min-rate 4000"

log "survey: nmap service sweep on $HOST"

if [[ "$HOST" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  nmap -sS -T3 --max-retries 1 -p- $CTF_ARGS -oA "$S/svc-$HOST" "$HOST" >>"$S/nmap.log" 2>&1 &
else
  nmap -sV -T3 --max-retries 1 --top-ports 1000 -oA "$S/svc-$HOST" "$HOST" >>"$S/nmap.log" 2>&1 &
fi
NMAP_PID=$!

log "survey: http probe"
python3 - "$URL" "$S/http_probe.json" <<'PY'
import json, subprocess, sys, ssl, socket, urllib.request, urllib.error
from urllib.parse import urlparse
url, outp = sys.argv[1], sys.argv[2]
u = urlparse(url); host = u.hostname
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
ports = [80, 443, 8080, 8443, 2083, 2087, 2030, 2031, 8888, 8081, 9090, 3000, 5000, 8000]
results = {}
for p in ports:
    for scheme in ("https", "http"):
        if (scheme=="https" and p not in (443,8443,2083,2087,8083,9443)) or (scheme=="http" and p not in (80,8080,2030,2031,8888,8081,3000,5000,8000,8008)):
            continue
        test = f"{scheme}://{host}:{p}/"
        try:
            ctx = ssl.create_default_context(); ctx.check_hostname=False; ctx.verify_mode=ssl.CERT_NONE
            req = urllib.request.Request(test, headers={"User-Agent": UA})
            r = urllib.request.urlopen(req, timeout=6, context=ctx)
            body = r.read(4000)
            results[test] = {"status": r.status, "server": r.headers.get("Server"), "len": len(body),
                             "powered_by": r.headers.get("X-Powered-By")}
        except urllib.error.HTTPError as e:
            results[test] = {"status": e.code, "server": e.headers.get("Server"), "len": len(e.read() or b"")}
        except Exception:
            pass
json.dump(results, open(outp,"w"), indent=2)
print(f"http probe: {len(results)} open endpoints")
PY

wait $NMAP_PID || true

log "survey: hosts.json / endpoints.json build"
python3 - "$HOST" "$S" <<'PY'
import glob, json, re, sys
host, s = sys.argv[1], sys.argv[2]
hosts = {"host": host, "ports": [], "services": []}
for f in glob.glob(f"{s}/svc-{host}.gnmap"):
    for line in open(f):
        m = re.search(r"Host: (\S+) \(\)\s+Ports: (.*)", line)
        if m:
            for pm in re.finditer(r"(\d+)/(\w+)/(\w+)/([^/]*)(?:/([^/]*))?", m.group(2)):
                hosts["ports"].append({"port": int(pm.group(1)), "state": pm.group(2), "proto": pm.group(3), "service": pm.group(4), "version": pm.group(5) or ""})
hosts["services"] = sorted({p["service"] for p in hosts["ports"] if p["state"]=="open"})
json.dump(hosts, open(f"{s}/hosts.json","w"), indent=2)
try:
    eps = json.load(open(f"{s}/http_probe.json"))
except Exception:
    eps = {}
json.dump({"endpoints": list(eps.keys())}, open(f"{s}/endpoints.json","w"), indent=2)
print(f"hosts.json: {len(hosts['ports'])} ports, endpoints: {len(eps)}")
PY

if command -v nuclei >/dev/null 2>&1; then
  log "survey: single nuclei run (severity medium+)"
  [[ -s "$S/endpoints.json" ]] && \
  python3 -c "import json;[print(u) for u in json.load(open('$S/endpoints.json'))['endpoints']]" > "$S/urls.txt" || true
  if [[ -s "$S/urls.txt" ]]; then
    nuclei -silent -severity medium,high,critical -l "$S/urls.txt" -o "$S/nuclei.txt" >>"$S/nuclei.log" 2>&1 || true
  fi
else
  log "nuclei not installed — skipped"
fi

mark_phase_done survey
