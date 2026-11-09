#!/usr/bin/env bash
set -euo pipefail

RTS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RTS_ROOT="$(dirname "$RTS_LIB_DIR")"

RTS_UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
RTS_TOR_SOCKS="socks5h://127.0.0.1:9050"
RTS_DELAY_DEFAULT=3

log()  { printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "${WS_LOG:-/dev/null}"; }
err()  { printf '[%s] ERROR: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2 | tee -a "${WS_LOG:-/dev/null}" >&2; }
die()  { err "$*"; exit 1; }

usage_common() {
  cat <<'EOF'
Required:
  --target <host|url|ip>   engagement target
  --ws <path>              workspace root (default: ~/redteam-runs/<target>/<ts>)
Optional:
  --mode ctf|engagement    default: engagement (ctf = louder, full sweeps)
  --egress direct|tor      default: direct (tor = socks5h://127.0.0.1:9050)
  --delay <sec>            inter-request delay (default: 3)
  --phase <list>           conductor only: comma phases
  --force                  re-run even if checkpoint exists
  --out <dir>              phase output dir override
EOF
}

parse_common_args() {
  TARGET="" WS="" MODE="engagement" EGRESS="direct" DELAY="$RTS_DELAY_DEFAULT"
  FORCE=0 PHASES="" OUT="" EXTRA_ARGS=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --target)  TARGET="${2:?}"; shift 2 ;;
      --ws)      WS="${2:?}"; shift 2 ;;
      --mode)    MODE="${2:?}"; shift 2 ;;
      --egress)  EGRESS="${2:?}"; shift 2 ;;
      --delay)   DELAY="${2:?}"; shift 2 ;;
      --phase)   PHASES="${2:?}"; shift 2 ;;
      --out)     OUT="${2:?}"; shift 2 ;;
      --force)   FORCE=1; shift ;;
      --help|-h) usage_common; exit 0 ;;
      *)         EXTRA_ARGS+=("$1"); shift ;;
    esac
  done
  [[ -n "$TARGET" ]] || { usage_common; die "--target is required"; }
  [[ "$MODE" == "ctf" || "$MODE" == "engagement" ]] || die "--mode must be ctf or engagement"
  [[ "$EGRESS" == "direct" || "$EGRESS" == "tor" ]] || die "--egress must be direct or tor"
}

init_workspace() {
  local slug ts
  slug="$(echo "$TARGET" | sed 's#[^A-Za-z0-9._-]#_#g' | cut -c1-60)"
  ts="$(date +%Y-%m-%d_%H%M)"
  WS="${WS:-$HOME/redteam-runs/$slug/$ts}"
  mkdir -p "$WS"/{recon,survey,exploit,loot,report}
  WS_LOG="$WS/report/run.log"
  touch "$WS_LOG"
  log "workspace: $WS  target=$TARGET mode=$MODE egress=$EGRESS delay=${DELAY}s"
}

target_url() {
  if [[ "$TARGET" =~ ^https?:// ]]; then echo "$TARGET";
  elif [[ "$TARGET" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then echo "http://$TARGET";
  else echo "https://$TARGET"; fi
}

target_host() {
  target_url | sed -E 's#^https?://([^/:]+).*#\1#'
}

http_get() {
  local url="$1"; shift
  local extra=()
  [[ "$EGRESS" == "tor" ]] && extra+=(--socks5-hostname 127.0.0.1:9050)
  curl -sk --max-time 25 -A "$RTS_UA" "${extra[@]}" "$@" "$url"
}

http_code() {
  local url="$1"; shift
  local extra=()
  [[ "$EGRESS" == "tor" ]] && extra+=(--socks5-hostname 127.0.0.1:9050)
  curl -sk --max-time 25 -A "$RTS_UA" -o /dev/null -w '%{http_code}' "${extra[@]}" "$@" "$url" 2>/dev/null || echo "000"
}

throttle() { sleep "${DELAY:-$RTS_DELAY_DEFAULT}"; }

json_field() {
  python3 -c 'import json,sys
try:
  d=json.load(open(sys.argv[1]))
  for k in sys.argv[2].split("."):
    d=d[k] if isinstance(d,dict) else d[int(k)]
  print(d if not isinstance(d,(dict,list)) else json.dumps(d))
except Exception:
  pass' "$1" "$2" 2>/dev/null
}

require_tools() {
  local missing=()
  for t in "$@"; do command -v "$t" >/dev/null 2>&1 || missing+=("$t"); done
  [[ ${#missing[@]} -eq 0 ]] || die "missing tools: ${missing[*]}"
}

logcheck() {
  local name="$1" file="$2"
  log "CHECK DONE: $name → $file"
}
