#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

WORK_TYPE="${1:-poc}"

case "$WORK_TYPE" in
  poc|mvp) ;;
  -h|--help)
    echo "usage: scripts/plan-boss-idea-poc-mvp.sh [poc|mvp]" >&2
    exit 0
    ;;
  *)
    echo "work type must be poc or mvp" >&2
    exit 2
    ;;
esac

cat <<MARKDOWN
---
work_type: $WORK_TYPE
timebox_days: 5
scope_in:
  - Demonstrate one approved workflow.
scope_out:
  - Production deployment.
demo_path: docs/demo/boss-idea-demo.md
validation_command: scripts/validate-agentic-system.sh
rollback_notes: Revert generated POC or MVP changes and keep decision evidence.
---
# POC MVP Timebox Plan
MARKDOWN
