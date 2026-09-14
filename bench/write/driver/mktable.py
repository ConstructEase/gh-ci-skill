#!/usr/bin/env python3
"""Render aggregate.json as the markdown tables for the write-side results.

Usage: mktable.py <aggregate.json> [tier2-results.tsv]
"""
import csv
import json
import sys

TASKS = ["T7", "T8", "T9"]
CONDS = ["C-ghci", "C-gh", "C-ghaxi"]
LABEL = {"C-ghci": "gh-ci", "C-gh": "plain gh", "C-ghaxi": "gh-axi"}
TASKNAME = {"T7": "T7 reply to an inline review comment",
            "T8": "T8 post a top-level PR comment",
            "T9": "T9 resolve a review thread"}


def n(x):
    return "{:,.0f}".format(x)


def rng(pair):
    return "%s-%s" % (n(pair[0]), n(pair[1]))


def main():
    agg = json.load(open(sys.argv[1]))
    cells, roll = agg["cells"], agg["conditions"]
    out = []

    out.append("## Tier 1 — 45 runs against the recording mock\n")
    out.append("Median (IQR) across 5 repeats. `call` is the deterministic assertion on the")
    out.append("HTTP request the agent issued; `judge` is the LLM judge reading its prose.\n")
    for task in TASKS:
        out.append("### %s\n" % TASKNAME[task])
        out.append("| tool | n | call | judge | total input tok | cache read | cache write | output tok | API calls | wall s |")
        out.append("|---|--:|--:|--:|--:|--:|--:|--:|--:|--:|")
        for cond in CONDS:
            c = cells.get("%s|%s" % (task, cond))
            if not c:
                continue
            out.append("| %s | %d | %d/%d | %d/%d | %s (%s) | %s | %s | %s (%s) | %s (%s) | %.1f (%.1f-%.1f) |" % (
                LABEL[cond], c["n"], c["call_pass"], c["n"], c["pass"], c["n"],
                n(c["total_in"]["med"]), rng(c["total_in"]["iqr"]),
                n(c["cache_read"]["med"]), n(c["cache_write"]["med"]),
                n(c["out_tok"]["med"]), rng(c["out_tok"]["iqr"]),
                n(c["api_calls"]["med"]), rng(c["api_calls"]["iqr"]),
                c["wall_ms"]["med"] / 1000,
                c["wall_ms"]["iqr"][0] / 1000, c["wall_ms"]["iqr"][1] / 1000))
        out.append("")

    out.append("### All three write tasks together\n")
    out.append("| tool | n | call | judge | total input tok | output tok | API calls | wall s | spend |")
    out.append("|---|--:|--:|--:|--:|--:|--:|--:|--:|")
    for cond in CONDS:
        c = roll.get(cond)
        if not c:
            continue
        out.append("| %s | %d | %d/%d (%.0f%%) | %d/%d (%.0f%%) | %s (IQR %s) | %s | %s | %.1f | $%.2f |" % (
            LABEL[cond], c["n"], c["call_pass"], c["n"], c["call_success_rate"] * 100,
            c["pass"], c["n"], c["success_rate"] * 100,
            n(c["total_in_med"]), rng(c["total_in_iqr"]),
            n(c["out_med"]), n(c["api_calls_med"]),
            c["wall_ms_med"] / 1000, c["usd"]))
    out.append("")

    if len(sys.argv) > 2:
        rows = list(csv.DictReader(open(sys.argv[2]), delimiter="\t"))
        if rows:
            out.append("## Tier 2 — 9 runs against real GitHub\n")
            out.append("| task | tool | state check | judge | total input tok | API calls | wall s |")
            out.append("|---|---|--:|--:|--:|--:|--:|")
            for task in TASKS:
                for cond in CONDS:
                    for r in rows:
                        if r["task"] == task and r["cond"] == cond:
                            tot = (float(r["in_tok"]) + float(r["cache_read"])
                                   + float(r["cache_write"]))
                            out.append("| %s | %s | %s | %s | %s | %s | %.1f |" % (
                                task, LABEL[cond], r["call_assert"], r["verdict"],
                                n(tot), r["api_calls"], float(r["wall_ms"]) / 1000))
            out.append("")
    print("\n".join(out))


if __name__ == "__main__":
    main()
