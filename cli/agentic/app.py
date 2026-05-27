"""Agentic CLI root."""

import platform
import sys

import typer

from agentic import __version__

app = typer.Typer(
    name="agentic",
    help="Agentic Delivery — plan → review → approve → implement.",
    no_args_is_help=True,
    add_completion=True,
)


@app.callback()
def _root() -> None:
    """Root callback. Forces multi-command app structure even with a single command.

    Later slices (CLI-02 onward) extend this with global flags like
    --repo, --run-id, --actor, --role, --json, --no-compat-check.
    """


@app.command()
def version() -> None:
    """Print CLI, python, and platform info."""
    typer.echo(f"agentic-delivery CLI  {__version__}")
    typer.echo(f"  python:   {platform.python_version()}")
    typer.echo(f"  platform: {sys.platform}")


def main() -> None:
    app()


if __name__ == "__main__":
    main()
