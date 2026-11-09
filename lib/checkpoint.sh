#!/usr/bin/env bash

# checkpoint contract (PLAYBOOK.md):
#   recon/recon.json          <- 01-recon
#   recon/services.json       <- 02-survey
#   survey/hosts.json         <- 02-survey
#   survey/endpoints.json     <- 02-survey
#   survey/nuclei.txt         <- 02-survey
#   exploit/findings-raw.md   <- 03/04/05
#   report/findings.json      <- 06-report

checkpoint_exists() {
  local f="$WS/$1"
  [[ -s "$f" ]]
}

skip_if_checkpoint() {
  local f="$1" name="$2"
  if [[ $FORCE -eq 0 ]] && checkpoint_exists "$f"; then
    log "SKIP $name: checkpoint $f exists (use --force to re-run)"
    return 0
  fi
  return 1
}

mark_phase_done() {
  local phase="$1"
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $phase done" >> "$WS/report/phases.log"
  log "DONE $phase"
}

phase_status() {
  local phase="$1" marker
  case "$phase" in
    recon)    marker="recon/recon.json" ;;
    survey)   marker="survey/hosts.json" ;;
    web)      marker="exploit/findings-raw.md" ;;
    infra)    marker="exploit/findings-raw.md" ;;
    exfil)    marker="loot/EXFIL.log" ;;
    validate) marker="report/validation.md" ;;
    report)   marker="report/findings.json" ;;
    *) return 1 ;;
  esac
  if checkpoint_exists "$marker"; then echo done; else echo pending; fi
}
