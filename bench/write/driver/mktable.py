#!/usr/bin/env python3
"""Render one benchmark aggregate using the shared results schema."""
import json
import sys

CONDS = [("C-ghci", "gh-ci"), ("C-gh", "`gh`"), ("C-ghaxi", "gh-axi")]

def number(value):
    return f"{value:,.0f}"

def total(metric):
    lo, hi = metric["iqr"]
    return f"{number(metric['med'])} ({number(lo)}–{number(hi)})"

def render(path):
    cells = json.load(open(path))["cells"]
    tasks = sorted({key.split("|")[0] for key in cells}, key=lambda task: int(task[1:]))
    print("| Task | Condition | Success | Total input tok (IQR) | cache_read | cache_write | input | output | Wall s | API calls | Tool calls |")
    print("|---|---|---|---|---|---|---|---|---|---|---|")
    for task in tasks:
        for condition, label in CONDS:
            cell = cells.get(f"{task}|{condition}")
            if not cell:
                continue
            success = f"{cell['pass']}/{cell['n']}"
            if "call_pass" in cell:
                success = f"call {cell['call_pass']}/{cell['n']}; judge {success}"
            print(f"| {task} | {label} | {success} | {total(cell['total_in'])} | "
                  f"{number(cell['cache_read']['med'])} | {number(cell['cache_write']['med'])} | "
                  f"{number(cell['in_tok']['med'])} | {number(cell['out_tok']['med'])} | "
                  f"{cell['wall_ms']['med']/1000:.1f} | {number(cell['api_calls']['med'])} | "
                  f"{number(cell['tool_calls']['med'])} |")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: mktable.py AGGREGATE.json")
    render(sys.argv[1])
