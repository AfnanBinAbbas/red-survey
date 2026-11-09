# red-survey

Phase 2 — attack surface: nmap service sweep (SYN, retries 1; CTF = min-rate 4000),
HTTP probe across common ports, hosts/endpoints JSON build, single nuclei run
(medium+). Writes `survey/`.

```bash
./phases/02-survey.sh --target <host|ip> [--mode ctf] [--egress tor]
```

Checkpoint: `survey/hosts.json`. One scan per engagement — readers consume output.
Authorized targets only.
