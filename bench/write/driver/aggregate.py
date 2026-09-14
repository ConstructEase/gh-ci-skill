#!/usr/bin/env python3
import os
"""Aggregate a write-side results.tsv into per-(task x condition) medians and IQRs.

Reports median and IQR (Q1-Q3) across repeats, never the mean, per the scout
report's guidance on model nondeterminism.

The write half carries two success rates, not one: `call` is the deterministic
assertion on the HTTP request the agent actually issued, and `judge` is the LLM
judge reading its prose. They sit side by side on purpose -- where they
disagree, the call assertion is the ground truth and the disagreement is itself
a result.

Usage: aggregate.py [results.tsv] [aggregate.json]
"""
import csv
import json
import sys
from collections import defaultdict

D = os.environ.get("BENCH_ROOT", os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TASKS = ["T7", "T8", "T9"]
CONDS = ["C-ghci", "C-gh", "C-ghaxi"]


def quantile(xs, q):
    """Linear-interpolation quantile on a sorted list (numpy 'linear' method)."""
    if not xs:
        return float("nan")
    s = sorted(xs)
    if len(s) == 1:
        return float(s[0])
    pos = (len(s) - 1) * q
    lo = int(pos)
    hi = min(lo + 1, len(s) - 1)
    frac = pos - lo
    return s[lo] + (s[hi] - s[lo]) * frac


def med(xs):
    return quantile(xs, 0.5)


def iqr(xs):
    return quantile(xs, 0.25), quantile(xs, 0.75)


OUT_PATH = None


def main(path=None):
    rows = []
    with open(path or f"{D}/results.tier1.tsv") as fh:
        for r in csv.DictReader(fh, delimiter="\t"):
            rows.append(r)

    cells = defaultdict(list)
    for r in rows:
        cells[(r["task"], r["cond"])].append(r)

    out = {}
    for task in TASKS:
        for cond in CONDS:
            rs = cells.get((task, cond), [])
            if not rs:
                continue
            n = len(rs)
            passes = sum(1 for r in rs if r["verdict"] == "PASS")
            call_passes = sum(1 for r in rs if r["call_assert"] == "PASS")
            f = lambda k: [float(r[k]) for r in rs]
            i = lambda k: [int(float(r[k])) for r in rs]
            total_in = [
                float(r["in_tok"]) + float(r["cache_read"]) + float(r["cache_write"])
                for r in rs
            ]
            out[f"{task}|{cond}"] = {
                "n": n,
                "pass": passes,
                "success_rate": passes / n,
                "call_pass": call_passes,
                "call_success_rate": call_passes / n,
                "wall_ms": {"med": med(f("wall_ms")), "iqr": iqr(f("wall_ms"))},
                "api_calls": {"med": med(i("api_calls")), "iqr": iqr(i("api_calls"))},
                "tool_calls": {"med": med(i("tool_calls")), "iqr": iqr(i("tool_calls"))},
                "in_tok": {"med": med(i("in_tok")), "iqr": iqr(i("in_tok"))},
                "cache_read": {"med": med(i("cache_read")), "iqr": iqr(i("cache_read"))},
                "cache_write": {"med": med(i("cache_write")), "iqr": iqr(i("cache_write"))},
                "out_tok": {"med": med(i("out_tok")), "iqr": iqr(i("out_tok"))},
                "total_in": {"med": med(total_in), "iqr": iqr(total_in)},
                "usd": sum(f("agent_usd")) + sum(f("judge_usd")),
            }

    # condition rollups
    roll = {}
    for cond in CONDS:
        rs = [r for r in rows if r["cond"] == cond]
        if not rs:
            continue
        passes = sum(1 for r in rs if r["verdict"] == "PASS")
        call_passes = sum(1 for r in rs if r["call_assert"] == "PASS")
        total_in = [
            float(r["in_tok"]) + float(r["cache_read"]) + float(r["cache_write"])
            for r in rs
        ]
        roll[cond] = {
            "n": len(rs),
            "pass": passes,
            "success_rate": passes / len(rs),
            "call_pass": call_passes,
            "call_success_rate": call_passes / len(rs),
            "total_in_med": med(total_in),
            "total_in_iqr": iqr(total_in),
            "wall_ms_med": med([float(r["wall_ms"]) for r in rs]),
            "api_calls_med": med([int(float(r["api_calls"])) for r in rs]),
            "tool_calls_med": med([int(float(r["tool_calls"])) for r in rs]),
            "out_med": med([int(float(r["out_tok"])) for r in rs]),
            "usd": sum(float(r["agent_usd"]) for r in rs)
            + sum(float(r["judge_usd"]) for r in rs),
        }

    report = {"cells": out, "conditions": roll, "runs": len(rows)}
    with open(OUT_PATH or f"{D}/aggregate.json", "w") as fh:
        json.dump(report, fh, indent=2)

    print(f"runs={len(rows)}")
    print()
    hdr = (f"{'task':5} {'cond':9} {'n':>2} {'call':>5} {'judge':>6} "
           f"{'totIn med (IQR)':>26} {'out':>6} {'wall s':>8} {'api':>4} {'tool':>5}")
    print(hdr)
    print("-" * len(hdr))
    for task in TASKS:
        for cond in CONDS:
            c = out.get(f"{task}|{cond}")
            if not c:
                continue
            lo, hi = c["total_in"]["iqr"]
            print(
                f"{task:5} {cond:9} {c['n']:>2} {c['call_success_rate']*100:>4.0f}% "
                f"{c['success_rate']*100:>5.0f}% "
                f"{c['total_in']['med']:>10,.0f} ({lo:>7,.0f}-{hi:>7,.0f}) "
                f"{c['out_tok']['med']:>6,.0f} {c['wall_ms']['med']/1000:>8.1f} "
                f"{c['api_calls']['med']:>4.0f} {c['tool_calls']['med']:>5.0f}"
            )
    print()
    print("condition rollups:")
    for cond, c in roll.items():
        lo, hi = c["total_in_iqr"]
        print(
            f"  {cond:9} n={c['n']:>3} call={c['call_success_rate']*100:>5.1f}% "
            f"judge={c['success_rate']*100:>5.1f}% "
            f"total-in med={c['total_in_med']:>10,.0f} (IQR {lo:,.0f}-{hi:,.0f}) "
            f"wall={c['wall_ms_med']/1000:.1f}s api={c['api_calls_med']:.0f} "
            f"tool={c['tool_calls_med']:.0f} spend=${c['usd']:.2f}"
        )
    total = sum(c["usd"] for c in roll.values())
    print(f"\nTOTAL SPEND: ${total:.2f}")


if __name__ == "__main__":
    if len(sys.argv) > 2:
        OUT_PATH = sys.argv[2]
    main(sys.argv[1] if len(sys.argv) > 1 else None)
