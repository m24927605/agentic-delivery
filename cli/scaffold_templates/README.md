# {{PROJECT_NAME}}

An agentic-delivery project. Scaffolded with `agentic` CLI v{{CLI_VERSION}}.

## Quick start

```bash
# Validate the scaffold and default profile
scripts/validate-agentic-system.sh

# Start a planning run
agentic init "Your first delivery goal"

# Inspect what to do next
agentic next
agentic status
```

## Profiles

This project ships with two starter profiles:

| Profile | Purpose |
|---------|---------|
| `default-delivery` | Generic planning + implementation pipeline runs |
| `boss-idea-response` | Triage executive ideas into research, recommendation, POC, MVP, or no-go |

Switch profile with `PROFILE=<id>` on any pipeline command.

## Pipeline

```
profile + goal
  → planning run
  → AIT multi-agent planning deliberation
  → generated drafts
  → review-fix loop
  → reviewed and approved artifacts
  → implementation run
  → implementation task graph
  → worker dispatch + execution
  → implementation review-fix
  → validation + PR/release preparation
```

See `agentic/README.md` or the reference repo for the full pipeline reference. Run `agentic --help` for CLI commands.

## License

This scaffold is your project's. Choose a license that fits your work.
