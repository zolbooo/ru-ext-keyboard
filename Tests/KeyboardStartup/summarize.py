#!/usr/bin/env python3
"""Summarize fresh-process construction timings, optionally enforcing a median budget."""
import argparse
import json
import re
import statistics
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("logs", nargs="+", type=Path)
parser.add_argument("--max-median-ms", type=float)
args = parser.parse_args()
first = []
warm = []
for path in args.logs:
    matches = re.findall(
        r"^BENCHMARK first_ms=([0-9.]+) warm_median_ms=([0-9.]+) checks=passed$",
        path.read_text(),
        re.MULTILINE,
    )
    if len(matches) != 1:
        parser.error(f"Expected exactly one successful benchmark in {path}")
    cold_ms, warm_ms = map(float, matches[0])
    first.append(cold_ms)
    warm.append(warm_ms)
median = statistics.median(first)
print(json.dumps({
    "samples": len(first),
    "first_ms": first,
    "first_median_ms": median,
    "first_min_ms": min(first),
    "first_max_ms": max(first),
    "warm_median_ms": statistics.median(warm),
}, indent=2))
if args.max_median_ms is not None:
    if len(first) < 5:
        parser.error("Collect at least five fresh-process samples to enforce a startup budget")
    if median > args.max_median_ms:
        parser.exit(1, f"Median {median:.3f} ms exceeds {args.max_median_ms:.3f} ms\n")
