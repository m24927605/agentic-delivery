#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
  cat >&2 <<'USAGE'
usage: scripts/validate-boss-idea-run-competitor-brief.sh <run-id> <brief-file-relative-to-run>
USAGE
}

if [[ $# -ne 2 ]]; then
  usage
  exit 2
fi

RUN_ID="$1" BRIEF_FILE="$2" ruby <<'RUBY'
require File.expand_path("scripts/lib/boss_idea", Dir.pwd)
require "pathname"

run_id = ENV.fetch("RUN_ID")
brief_file = ENV.fetch("BRIEF_FILE")

def fail_with(message, code = 1)
  warn message
  exit code
end

def lexists?(path)
  File.lstat(path)
  true
rescue Errno::ENOENT
  false
end

unless run_id.match?(/\A[A-Za-z0-9][A-Za-z0-9._-]*\z/)
  fail_with("invalid run id: #{run_id}", 2)
end

if brief_file.empty? || brief_file.start_with?("/") || brief_file.split("/").include?("..")
  fail_with("invalid brief file path: #{brief_file}", 2)
end

run_dir = File.join("agentic/runs", run_id)
fail_with("blocked_missing_source: #{run_dir}") unless File.directory?(run_dir)
fail_with("invalid run directory is a symlink: #{run_dir}", 2) if File.lstat(run_dir).symlink?

expected_run_real = Pathname.new(File.expand_path(run_dir, Dir.pwd)).cleanpath.to_s
run_real = Pathname.new(run_dir).realpath.to_s
fail_with("invalid run directory realpath: #{run_dir}", 2) unless run_real == expected_run_real
target = File.join(run_dir, brief_file)
current = run_dir

File.dirname(brief_file).split("/").each do |part|
  next if part.empty? || part == "."

  current = File.join(current, part)
  next unless lexists?(current)

  fail_with("invalid brief file path uses symlink component: #{current}", 2) if File.lstat(current).symlink?
end

fail_with("blocked_missing_source: #{target}") unless File.file?(target)
fail_with("invalid brief file path is a symlink: #{target}", 2) if File.lstat(target).symlink?

target_real = Pathname.new(target).realpath.to_s
unless target_real == run_real || target_real.start_with?("#{run_real}/")
  fail_with("invalid brief file path escapes run directory: #{target}", 2)
end

system("scripts/validate-boss-idea-competitor-brief.sh", target)
status = $?
exit(status.exitstatus || 1) unless status&.success?
RUBY
