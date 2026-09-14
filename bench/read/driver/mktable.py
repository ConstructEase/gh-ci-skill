#!/usr/bin/env python3
import os
"""Render aggregate.json as the markdown tables for the README section."""
import json

D = os.environ.get("BENCH_ROOT", os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TASKS = [
    ("T1", "CI status for a PR"),
    ("T2", "Wait on a named check"),
    ("T4", "Read a failing run log"),
    ("T5", "Check mergeability"),
    ("T6", "Read PR comments"),
]
CONDS = [("C-ghci", "gh-ci"), ("C-gh", "`gh`"), ("C-ghaxi", "gh-axi")]

a = json.load(open(f"{D}/aggregate.json"))
cells, roll = a["cells"], a["conditions"]


def n(x):
    return f"{x:,.0f}"


def rng(d):
    lo, hi = d["iqr"]
    return f"{n(d['med'])} ({n(lo)}–{n(hi)})"


print("### Per task × condition\n")
print(
    "| Task | Condition | Success | Total input tok (IQR) | cache_read | cache_write | input | output | Wall s | API calls | Tool calls |"
)
print("|---|---|---|---|---|---|---|---|---|---|---|")
for tid, tname in TASKS:
    for cid, cname in CONDS:
        c = cells.get(f"{tid}|{cid}")
        if not c:
            continue
        first = f"**{tid}** {tname}" if cid == CONDS[0][0] else ""
        print(
            f"| {first} | {cname} | {c['success_rate']*100:.0f}% ({c['pass']}/{c['n']}) "
            f"| {rng(c['total_in'])} | {n(c['cache_read']['med'])} | {n(c['cache_write']['med'])} "
            f"| {n(c['in_tok']['med'])} | {n(c['out_tok']['med'])} "
            f"| {c['wall_ms']['med']/1000:.1f} | {c['api_calls']['med']:.0f} | {c['tool_calls']['med']:.0f} |"
        )

print("\n### Rolled up across all five tasks\n")
print(
    "| Condition | Success | Median total input tok (IQR) | Median output tok | Median wall s | Median API calls | Median tool calls |"
)
print("|---|---|---|---|---|---|---|")
for cid, cname in CONDS:
    c = roll[cid]
    lo, hi = c["total_in_iqr"]
    print(
        f"| {cname} | {c['success_rate']*100:.0f}% ({c['pass']}/{c['n']}) "
        f"| {n(c['total_in_med'])} ({n(lo)}–{n(hi)}) | {n(c['out_med'])} "
        f"| {c['wall_ms_med']/1000:.1f} | {c['api_calls_med']:.0f} | {c['tool_calls_med']:.0f} |"
    )
print(f"\ntotal spend: ${sum(c['usd'] for c in roll.values()):.2f}")
