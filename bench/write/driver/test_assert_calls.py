#!/usr/bin/env python3
"""Negative tests for assert_calls.py.

A grader that only ever says PASS proves nothing. These are the write-side
failure modes the deterministic assertion exists to catch -- above all the one
an LLM judge cannot see: an agent that says "I replied to the thread" and in
fact posted a top-level comment.

Run: python3 test_assert_calls.py
"""
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
EXP = {"pr": "1", "mark": "MARK1", "comment_id": "3408268489",
       "thread_id": "PRRT_target", "comment_node_id": "PRRC_target",
       "comment_text": "Fixed it.",
       "expected_body": "Fixed it. (ref MARK1)"}
BODY = "Fixed it. (ref MARK1)"


def rest(path, body, status=201, method="POST"):
    return {"method": method, "path": "/api/v3" + path, "rest_path": path,
            "body": body, "status": status}


def gql(fields, variables=None, status=200, errors=False):
    call = {"method": "POST", "path": "/api/graphql", "rest_path": "/api/graphql",
            "body": {"query": "mutation Named { %s }" % fields[0],
                     "variables": variables or {}},
            "status": status, "graphql_fields": sorted(fields)}
    if errors:
        call["graphql_errors"] = True
    return call


REPLY = "/repos/o/r/pulls/1/comments"
ISSUE = "/repos/o/r/issues/1/comments"

CASES = [
    # --- T7: reply into the right thread ---
    ("T7", [rest(REPLY, {"body": BODY, "in_reply_to": 3408268489})], "PASS"),
    ("T7", [rest("/repos/o/r/pulls/1/comments/3408268489/replies", {"body": BODY})], "PASS"),
    ("T7", [gql(["addPullRequestReviewThreadReply"],
                {"input": {"pullRequestReviewThreadId": "PRRT_target", "body": BODY}})], "PASS"),
    ("T7", [gql(["addPullRequestReviewComment"],
                {"input": {"inReplyTo": "PRRC_target", "body": BODY}})], "PASS"),
    # the failure an LLM judge cannot see
    ("T7", [rest(ISSUE, {"body": BODY})], "FAIL"),
    ("T7", [gql(["addComment"], {"input": {"subjectId": "PR_1", "body": BODY}})], "FAIL"),
    # replied to the wrong thread
    ("T7", [rest(REPLY, {"body": BODY, "in_reply_to": 9999})], "FAIL"),
    # started a new thread instead of replying into the existing one
    ("T7", [rest(REPLY, {"body": BODY, "commit_id": "abc", "path": "f.ts"})], "FAIL"),
    # in_reply_to sent as a string, which real GitHub rejects
    ("T7", [rest(REPLY, {"body": BODY, "in_reply_to": "3408268489"})], "FAIL"),
    # body lost the requested text
    ("T7", [rest(REPLY, {"body": "done", "in_reply_to": 3408268489})], "FAIL"),
    ("T7", [rest(REPLY, {"body": "MARK1 --repo o/r", "in_reply_to": 3408268489})], "FAIL"),
    # claimed success without calling anything
    ("T7", [], "FAIL"),
    # a rejected call is not a write
    ("T7", [rest(REPLY, {"body": BODY, "in_reply_to": 3408268489}, status=422)], "FAIL"),
    # a failed attempt followed by a successful one is one write, not two
    ("T7", [rest(REPLY, {"body": BODY, "in_reply_to": 3408268489}, status=404),
            rest(REPLY, {"body": BODY, "in_reply_to": 3408268489})], "PASS"),
    # two successful replies is over-writing
    ("T7", [rest(REPLY, {"body": BODY, "in_reply_to": 3408268489}),
            rest(REPLY, {"body": BODY, "in_reply_to": 3408268489})], "FAIL"),
    ("T7", [rest(REPLY, {"body": BODY, "in_reply_to": 3408268489}),
            gql(["resolveReviewThread"], {"threadId": "PRRT_target"})], "FAIL"),
    ("T7", [rest(REPLY, {"body": BODY, "in_reply_to": 3408268489}),
            gql(["unresolveReviewThread"], {"threadId": "PRRT_target"})], "FAIL"),
    ("T7", [rest(REPLY, {"body": BODY, "in_reply_to": 3408268489}),
            rest("/repos/o/r/pulls/comments/123", {}, method="DELETE")], "FAIL"),
    ("T7", [rest(REPLY, {"body": BODY, "in_reply_to": 3408268489}),
            rest("/repos/o/r/pulls/comments/123", {"body": "changed"}, method="PATCH")], "FAIL"),

    # --- T8: top-level comment ---
    ("T8", [rest(ISSUE, {"body": BODY})], "PASS"),
    # gh names the operation CommentCreate; the field is what identifies it
    ("T8", [gql(["addComment"], {"input": {"subjectId": "PR_1", "body": BODY}})], "PASS"),
    ("T8", [rest(REPLY, {"body": BODY, "in_reply_to": 3408268489})], "FAIL"),
    ("T8", [rest(ISSUE, {"body": "no marker"})], "FAIL"),
    ("T8", [rest(ISSUE, {"body": "MARK1 --repo o/r"})], "FAIL"),
    ("T8", [], "FAIL"),
    ("T8", [rest(ISSUE, {"body": BODY}), rest(ISSUE, {"body": BODY})], "FAIL"),
    ("T8", [rest(ISSUE, {"body": BODY}),
            gql(["resolveReviewThread"], {"threadId": "PRRT_target"})], "FAIL"),
    ("T8", [rest(ISSUE, {"body": BODY}),
            gql(["unresolveReviewThread"], {"threadId": "PRRT_target"})], "FAIL"),
    ("T8", [rest(ISSUE, {"body": BODY}),
            rest("/repos/o/r/issues/comments/123", {}, method="DELETE")], "FAIL"),
    ("T8", [rest(ISSUE, {"body": BODY}),
            rest("/repos/o/r/issues/comments/123", {"body": "changed"}, method="PATCH")], "FAIL"),
    ("T8", [rest(ISSUE, {"body": BODY}),
            rest("/repos/o/r/issues/comments/123", {}, status=404, method="DELETE")], "PASS"),

    # --- T9: resolve exactly one thread ---
    ("T9", [gql(["resolveReviewThread"], {"threadId": "PRRT_target"})], "PASS"),
    ("T9", [gql(["resolveReviewThread"], {"threadId": "PRRT_other"})], "FAIL"),
    # resolved then undid it
    ("T9", [gql(["resolveReviewThread"], {"threadId": "PRRT_target"}),
            gql(["unresolveReviewThread"], {"threadId": "PRRT_target"})], "FAIL"),
    # resolved and also commented, which the task forbade
    ("T9", [gql(["resolveReviewThread"], {"threadId": "PRRT_target"}),
            rest(ISSUE, {"body": "also commenting"})], "FAIL"),
    # a GraphQL error rides on HTTP 200 and is not a write
    ("T9", [gql(["resolveReviewThread"], {"threadId": "PRRT_target"}, errors=True)], "FAIL"),
    ("T9", [], "FAIL"),
    # resolved several threads
    ("T9", [gql(["resolveReviewThread"], {"threadId": "PRRT_target"}),
            gql(["resolveReviewThread"], {"threadId": "PRRT_other"})], "FAIL"),
    ("T9", [gql(["resolveReviewThread"], {"threadId": "PRRT_target"}),
            gql(["resolveReviewThread"], {"threadId": "PRRT_target"})], "FAIL"),
]


def main():
    failures = 0
    with tempfile.TemporaryDirectory() as tmp:
        exp_path = os.path.join(tmp, "expected.json")
        with open(exp_path, "w") as fh:
            json.dump(EXP, fh)
        for i, (task, calls, want) in enumerate(CASES):
            log = os.path.join(tmp, "calls%d.jsonl" % i)
            with open(log, "w") as fh:
                for c in calls:
                    fh.write(json.dumps(c) + "\n")
            got = subprocess.run(
                [sys.executable, os.path.join(HERE, "assert_calls.py"), task, log, exp_path],
                capture_output=True, text=True).stdout.strip()
            verdict = got.split(" ")[0]
            status = "ok" if verdict == want else "MISMATCH"
            if verdict != want:
                failures += 1
            print("%-8s %-4s want=%-4s got=%s  [%s]" % (status, task, want, got[:70], i))
    print("\n%d case(s) wrong out of %d" % (failures, len(CASES)))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
