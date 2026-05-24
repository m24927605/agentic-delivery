#!/usr/bin/env python3
"""Run an isolated local browser search and return result candidates as JSON.

The helper is optional. It is used only when the Boss Idea market crawler is
explicitly invoked with the local_browser_search provider and live crawl gates.
Default validation uses fixture JSON and does not require Playwright or Chrome.
"""

from __future__ import annotations

import argparse
import json
import sys


def fail(message: str, code: int = 1) -> None:
    print(json.dumps({"ok": False, "error": message}), file=sys.stderr)
    raise SystemExit(code)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--query", required=True)
    parser.add_argument("--search-url", required=True)
    parser.add_argument("--max-results", type=int, default=5)
    parser.add_argument("--timeout-ms", type=int, default=20000)
    parser.add_argument("--channel", default="chrome")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        from playwright.sync_api import sync_playwright  # type: ignore
    except Exception as exc:  # pragma: no cover - exercised by live operator smoke.
        fail(f"playwright runtime unavailable: {type(exc).__name__}: {exc}", 3)

    results = []
    with sync_playwright() as runtime:
        browser = runtime.chromium.launch(channel=args.channel, headless=True)
        context = browser.new_context(locale="en-US")
        page = context.new_page()
        page.goto(args.search_url, wait_until="domcontentloaded", timeout=args.timeout_ms)
        anchors = page.locator("a").evaluate_all(
            """els => els.map((el) => ({
              url: el.href || "",
              title: (el.textContent || "").trim(),
              snippet: (el.getAttribute("data-snippet") || "").trim()
            }))"""
        )
        for anchor in anchors:
            url = str(anchor.get("url", ""))
            title = " ".join(str(anchor.get("title", "")).split())
            if not url.startswith(("http://", "https://")) or not title:
                continue
            results.append({"url": url, "title": title, "content": str(anchor.get("snippet", ""))[:240]})
            if len(results) >= args.max_results:
                break
        context.close()
        browser.close()

    print(json.dumps({"ok": True, "query": args.query, "results": results}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
