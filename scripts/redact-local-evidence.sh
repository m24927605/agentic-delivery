#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ $# -eq 0 ]]; then
  echo "usage: scripts/redact-local-evidence.sh <path> [path ...]" >&2
  exit 2
fi

for path in "$@"; do
  case "$path" in
    /*|*..*)
      echo "invalid evidence path: $path" >&2
      exit 2
      ;;
  esac

  if [[ -d "$path" ]]; then
    find "$path" -type f -print0 | xargs -0 perl -0pi \
      -e 's/ownership[_-]token/redacted_ait_metadata/ig; s#/Users/[^\s"]+#[local-path]#g'
  elif [[ -f "$path" ]]; then
    perl -0pi \
      -e 's/ownership[_-]token/redacted_ait_metadata/ig; s#/Users/[^\s"]+#[local-path]#g' \
      "$path"
  else
    echo "evidence path not found: $path" >&2
    exit 1
  fi
done

echo "local evidence redacted"
