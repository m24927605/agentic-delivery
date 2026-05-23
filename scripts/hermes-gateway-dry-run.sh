#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

cat <<'YAML'
hermes gateway dry run
---
schema_version: 1
authority: repo_manifest
gateway_mode: dry_run
push_enabled: false
data_crossing_boundary:
  - run id
  - run mode
  - run state
  - manifest path
  - next suggested repo-local action
data_not_crossing_boundary:
  - secrets
  - customer identifiers
  - private strategy
  - raw review traces
  - authoritative approval decisions outside manifest
manual_rerun:
  - scripts/report-run-status.sh <run-id>
  - scripts/run-hermes-action.sh --dry-run <action-id> key=value
hermes_disabled_mode:
  supported: true
  behavior: repo-local scripts remain manually runnable
YAML
