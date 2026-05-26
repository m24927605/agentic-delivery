#!/usr/bin/env python3
"""Crawl one approved Boss Idea URL through Crawl4AI and emit JSON.

This helper is intentionally small. The shell/Ruby wrapper owns URL policy,
manifest updates, and public-safe result normalization; this file owns only the
Crawl4AI runtime call and returns markdown plus runtime metadata.
"""

from __future__ import annotations

import argparse
import asyncio
from datetime import datetime, timezone
import ipaddress
import json
import socket
import sys
from urllib.parse import urlparse


def fail(message: str, code: int = 1) -> None:
    print(json.dumps({"ok": False, "error": message}), file=sys.stderr)
    raise SystemExit(code)


def markdown_text(markdown: object) -> str:
    if markdown is None:
        return ""
    if isinstance(markdown, str):
        return markdown
    for attr in ("raw_markdown", "markdown", "fit_markdown"):
        value = getattr(markdown, attr, None)
        if isinstance(value, str) and value.strip():
            return value
    return str(markdown)


def result_final_url(result: object, requested_url: str) -> str:
    for attr in ("final_url", "redirected_url", "url"):
        value = getattr(result, attr, None)
        if isinstance(value, str) and value.strip():
            return value.strip()
    return requested_url


def resolved_ips(host: str, port: int) -> list[str]:
    try:
        infos = socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)
    except socket.gaierror as exc:
        raise ValueError(f"observed network DNS resolution failed: {exc}") from exc

    ips: list[str] = []
    seen: set[str] = set()
    for info in infos:
        value = str(info[4][0]).split("%", 1)[0]
        try:
            normalized = str(ipaddress.ip_address(value))
        except ValueError:
            continue
        if normalized not in seen:
            seen.add(normalized)
            ips.append(normalized)
    if not ips:
        raise ValueError("observed network DNS resolution returned no IPs")
    return ips


def observed_network_payload(requested_url: str, final_url: str) -> dict[str, object]:
    uri = urlparse(final_url)
    if uri.scheme not in {"http", "https"} or not uri.hostname:
        raise ValueError("observed network final_url must be http or https with host")
    port = uri.port or (443 if uri.scheme == "https" else 80)
    return {
        "requested_url": requested_url,
        "final_url": final_url,
        "final_host": uri.hostname.lower(),
        "observed_ips": resolved_ips(uri.hostname, port),
        "resolved_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "source": "dns",
    }


async def crawl(args: argparse.Namespace) -> dict[str, object]:
    try:
        import crawl4ai  # type: ignore
        from crawl4ai import AsyncWebCrawler, BrowserConfig, CacheMode, CrawlerRunConfig  # type: ignore
    except Exception as exc:  # pragma: no cover - depends on operator runtime
        fail(f"crawl4ai runtime unavailable: {type(exc).__name__}: {exc}", 3)

    browser_config = BrowserConfig(
        headless=True,
        user_agent=args.user_agent,
    )
    run_config = CrawlerRunConfig(
        cache_mode=CacheMode.BYPASS,
        page_timeout=args.timeout_ms,
        check_robots_txt=True,
        user_agent=args.user_agent,
    )

    async with AsyncWebCrawler(config=browser_config) as crawler:
        result = await crawler.arun(url=args.url, config=run_config)

    success = bool(getattr(result, "success", False))
    if not success:
        error_message = getattr(result, "error_message", "") or "Crawl4AI returned unsuccessful result"
        fail(str(error_message), 4)

    markdown = markdown_text(getattr(result, "markdown", ""))
    if not markdown.strip():
        fail("Crawl4AI returned no usable markdown", 5)
    if len(markdown.encode("utf-8")) > args.max_response_bytes:
        fail("Crawl4AI markdown exceeds max response bytes", 7)

    truncated = False
    if len(markdown) > args.max_markdown_chars:
        markdown = markdown[: args.max_markdown_chars]
        truncated = True

    final_url = result_final_url(result, args.url)
    try:
        observed_network = observed_network_payload(args.url, final_url)
    except ValueError as exc:
        fail(str(exc), 8)

    return {
        "ok": True,
        "url": args.url,
        "crawl4ai_version": getattr(crawl4ai, "__version__", "unknown"),
        "markdown": markdown,
        "truncated": truncated,
        "observed_network": observed_network,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", required=True)
    parser.add_argument("--user-agent", required=True)
    parser.add_argument("--timeout-ms", type=int, required=True)
    parser.add_argument("--max-response-bytes", type=int, required=True)
    parser.add_argument("--max-markdown-chars", type=int, required=True)
    args = parser.parse_args()

    try:
        payload = asyncio.run(crawl(args))
    except SystemExit:
        raise
    except Exception as exc:  # pragma: no cover - defensive runtime boundary
        fail(f"Crawl4AI crawl failed: {type(exc).__name__}: {exc}", 6)

    print(json.dumps(payload))


if __name__ == "__main__":
    main()
