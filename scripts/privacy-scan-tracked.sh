#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
  cat >&2 <<'USAGE'
usage: scripts/privacy-scan-tracked.sh [--cached]

Scans tracked files, or staged files with --cached, for public-safety and common
secret-assignment patterns. Ignored local evidence is not scanned.
USAGE
}

CACHED=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cached)
      CACHED=1
      shift
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

CACHED="$CACHED" ruby <<'RUBY'
cached = ENV.fetch("CACHED") == "1"

paths = if cached
  `git diff --cached --name-only -z`.split("\0")
else
  `git ls-files -z`.split("\0")
end

paths = paths.select { |path| File.file?(path) }
patterns = [
  Regexp.new("private product " + "name", Regexp::IGNORECASE),
  Regexp.new("private strategy " + "file", Regexp::IGNORECASE),
  Regexp.new("customer " + "name", Regexp::IGNORECASE),
  Regexp.new("ownership[_-]" + "token", Regexp::IGNORECASE),
  Regexp.new("vu" + "lcan", Regexp::IGNORECASE),
  Regexp.new("secure " + "harness", Regexp::IGNORECASE),
  Regexp.new("private agent runtime " + "gateway", Regexp::IGNORECASE),
  Regexp.new("origin-" + "strategy", Regexp::IGNORECASE),
  /(api[_-]?key|secret|password|private[_-]?key|ownership[_-]?token)\s*[:=]/i
]

findings = []
paths.each do |path|
  next if path.start_with?("agentic/reviews/")
  next if path.start_with?("agentic/runs/") && path != "agentic/runs/.gitkeep"

  File.readlines(path, chomp: true).each_with_index do |line, index|
    patterns.each do |pattern|
      next unless line.match?(pattern)
      findings << "#{path}:#{index + 1}: #{pattern.inspect}"
    end
  end
end

unless findings.empty?
  findings.each { |finding| warn "privacy scan finding: #{finding}" }
  exit 1
end

scope = cached ? "cached" : "tracked"
puts "privacy scan ok: #{scope} files=#{paths.length}"
RUBY
