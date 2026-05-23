#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
  cat >&2 <<'USAGE'
usage: scripts/record-validation-evidence.sh --slice <slice-id> [--round <n>] -- <command> [args...]
USAGE
}

SLICE_ID=""
ROUND="1"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --slice)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      SLICE_ID="$2"
      shift 2
      ;;
    --round)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      ROUND="$2"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown option: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ -z "$SLICE_ID" || $# -eq 0 ]]; then
  usage
  exit 2
fi

case "$SLICE_ID" in
  /*|*..*|"")
    echo "invalid slice id: $SLICE_ID" >&2
    exit 2
    ;;
esac

case "$ROUND" in
  *[!0-9]*|"")
    echo "invalid round: $ROUND" >&2
    exit 2
    ;;
esac

EVIDENCE_DIR="agentic/reviews/auto-doc-to-implementation/$SLICE_ID"
EVIDENCE_PATH="$EVIDENCE_DIR/validation-round-$ROUND.log"
mkdir -p "$EVIDENCE_DIR"

set +e
"$@" >"$EVIDENCE_PATH.tmp" 2>&1
STATUS=$?
set -e

{
  printf 'command:'
  printf ' %q' "$@"
  printf '\n'
  printf 'exit_status: %s\n' "$STATUS"
  printf 'recorded_at: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'output:\n'
  sed \
    -e 's/ownership[_-]token/redacted_ait_metadata/Ig' \
    -e 's#/[Uu]sers/[^[:space:]]*#[local-path]#g' \
    "$EVIDENCE_PATH.tmp"
} >"$EVIDENCE_PATH"

rm -f "$EVIDENCE_PATH.tmp"
echo "validation evidence: $EVIDENCE_PATH status=$STATUS"
exit "$STATUS"
