#!/usr/bin/env python3
"""Generate a deterministic SVG chart from GitHub's stargazer timestamps."""

from __future__ import annotations

import argparse
import json
import os
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path


THEMES = {
    "light": {
        "background": "#ffffff",
        "border": "#d0d7de",
        "grid": "#d8dee4",
        "muted": "#57606a",
        "text": "#24292f",
        "line": "#1f883d",
        "fill": "#dafbe1",
    },
    "dark": {
        "background": "#0d1117",
        "border": "#30363d",
        "grid": "#30363d",
        "muted": "#8b949e",
        "text": "#e6edf3",
        "line": "#3fb950",
        "fill": "#12261a",
    },
}


def github_json(url: str, token: str) -> object:
    request = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github.star+json",
            "Authorization": f"Bearer {token}",
            "User-Agent": "spotify-lyricify-star-history",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    with urllib.request.urlopen(request) as response:
        return json.load(response)


def fetch_repository(repo: str, token: str) -> tuple[datetime, list[datetime]]:
    metadata = github_json(f"https://api.github.com/repos/{repo}", token)
    if not isinstance(metadata, dict):
        raise RuntimeError("Unexpected repository metadata response")
    created_at = datetime.fromisoformat(str(metadata["created_at"]).replace("Z", "+00:00"))

    stars: list[datetime] = []
    page = 1
    while True:
        payload = github_json(
            f"https://api.github.com/repos/{repo}/stargazers?per_page=100&page={page}",
            token,
        )
        if not isinstance(payload, list):
            raise RuntimeError("Unexpected stargazer response")
        for item in payload:
            if isinstance(item, dict) and item.get("starred_at"):
                stars.append(
                    datetime.fromisoformat(str(item["starred_at"]).replace("Z", "+00:00"))
                )
        if len(payload) < 100:
            break
        page += 1
    return created_at, sorted(stars)


def escape(text: str) -> str:
    return (
        text.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )


def render(repo: str, created_at: datetime, stars: list[datetime], theme: str) -> str:
    colors = THEMES[theme]
    width, height = 800, 420
    left, right, top, bottom = 74, 28, 68, 62
    plot_width = width - left - right
    plot_height = height - top - bottom

    start = created_at.astimezone(timezone.utc)
    latest = max([start, *stars])
    end = max(latest + timedelta(hours=1), start + timedelta(days=1))
    total_seconds = max((end - start).total_seconds(), 1)
    max_stars = max(len(stars), 1)

    def x_for(value: datetime) -> float:
        return left + ((value - start).total_seconds() / total_seconds) * plot_width

    def y_for(value: int) -> float:
        return top + plot_height - (value / max_stars) * plot_height

    points: list[tuple[float, float]] = [(x_for(start), y_for(0))]
    count = 0
    for starred_at in stars:
        x = x_for(starred_at)
        points.append((x, y_for(count)))
        count += 1
        points.append((x, y_for(count)))
    points.append((x_for(end), y_for(count)))

    line_points = " ".join(f"{x:.2f},{y:.2f}" for x, y in points)
    area_points = (
        f"{left},{top + plot_height} "
        + line_points
        + f" {left + plot_width},{top + plot_height}"
    )

    if max_stars <= 5:
        y_ticks = list(range(max_stars + 1))
    else:
        y_ticks = sorted({0, round(max_stars * 0.25), round(max_stars * 0.5), round(max_stars * 0.75), max_stars})

    span = end - start
    fractions = (0, 1) if span < timedelta(days=4) else (0, 0.25, 0.5, 0.75, 1)
    x_ticks = [start + span * fraction for fraction in fractions]
    x_label_format = "%b %d" if span.days < 366 else "%b %Y"

    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}" role="img" aria-labelledby="title desc">',
        f'<title id="title">Star history for {escape(repo)}</title>',
        f'<desc id="desc">{len(stars)} GitHub star{"s" if len(stars) != 1 else ""}, generated from GitHub stargazer timestamps.</desc>',
        f'<rect width="{width}" height="{height}" rx="12" fill="{colors["background"]}" stroke="{colors["border"]}"/>',
        f'<text x="{left}" y="35" fill="{colors["text"]}" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="20" font-weight="600">Star History</text>',
        f'<text x="{left}" y="55" fill="{colors["muted"]}" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="13">{escape(repo)} · {len(stars)} star{"s" if len(stars) != 1 else ""}</text>',
    ]

    for tick in y_ticks:
        y = y_for(tick)
        parts.extend(
            [
                f'<line x1="{left}" y1="{y:.2f}" x2="{left + plot_width}" y2="{y:.2f}" stroke="{colors["grid"]}" stroke-width="1"/>',
                f'<text x="{left - 12}" y="{y + 4:.2f}" text-anchor="end" fill="{colors["muted"]}" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="12">{tick}</text>',
            ]
        )

    for index, tick in enumerate(x_ticks):
        x = x_for(tick)
        anchor = "start" if index == 0 else "end" if index == len(x_ticks) - 1 else "middle"
        parts.append(
            f'<text x="{x:.2f}" y="{height - 25}" text-anchor="{anchor}" fill="{colors["muted"]}" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="12">{tick.strftime(x_label_format)}</text>'
        )

    parts.extend(
        [
            f'<polygon points="{area_points}" fill="{colors["fill"]}"/>',
            f'<polyline points="{line_points}" fill="none" stroke="{colors["line"]}" stroke-width="3" stroke-linejoin="round"/>',
            f'<circle cx="{points[-1][0]:.2f}" cy="{points[-1][1]:.2f}" r="4" fill="{colors["line"]}"/>',
            f'<text x="{left + plot_width}" y="35" text-anchor="end" fill="{colors["line"]}" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="20" font-weight="700">★ {len(stars)}</text>',
            "</svg>",
            "",
        ]
    )
    return "\n".join(parts)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY"))
    parser.add_argument("--output-dir", default="assets")
    args = parser.parse_args()
    if not args.repo:
        parser.error("--repo or GITHUB_REPOSITORY is required")

    token = os.environ.get("GITHUB_TOKEN")
    if not token:
        raise SystemExit("GITHUB_TOKEN is required")

    created_at, stars = fetch_repository(args.repo, token)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    for theme in THEMES:
        (output_dir / f"star-history-{theme}.svg").write_text(
            render(args.repo, created_at, stars, theme), encoding="utf-8"
        )
    print(f"Generated star history for {args.repo}: {len(stars)} stars")


if __name__ == "__main__":
    main()
