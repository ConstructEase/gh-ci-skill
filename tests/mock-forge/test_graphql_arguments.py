#!/usr/bin/env python3
import json
import os
import ssl
import subprocess
import sys
import tempfile
import urllib.request


HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
FORGE = os.path.join(HERE, "forge.sh")
GRADER = os.path.join(ROOT, "bench", "write", "driver", "assert_calls.py")
BODY = "Fixed it. (ref MARK1)"


def post(url, payload, context):
    request = urllib.request.Request(
        url, data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(request, context=context) as response:
        return json.load(response)


def grade(task, calls, expected, verdict, directory):
    calls_path = os.path.join(directory, "one-call.jsonl")
    expected_path = os.path.join(directory, "expected.json")
    with open(calls_path, "w") as fh:
        for call in calls:
            fh.write(json.dumps(call) + "\n")
    with open(expected_path, "w") as fh:
        json.dump(expected, fh)
    result = subprocess.run(
        [sys.executable, GRADER, task, calls_path, expected_path],
        capture_output=True, text=True, check=True)
    if result.stdout.strip().split(" ", 1)[0] != verdict:
        raise AssertionError("%s: %s" % (task, result.stdout.strip()))


def main():
    expected = {
        "pr": "1", "mark": "MARK1", "comment_id": "3408268489",
        "thread_id": "PRRT_kwDOMOCKFx86JVu00",
        "comment_node_id": "PRRC_kwDOMOCKF86Ja00",
        "comment_text": "Fixed it.", "expected_body": BODY,
    }
    with tempfile.TemporaryDirectory() as directory:
        subprocess.run(["bash", FORGE, "start", directory],
                       capture_output=True, text=True, check=True)
        try:
            with open(os.path.join(directory, "forge.port")) as fh:
                port = fh.read().strip()
            context = ssl.create_default_context(
                cafile=os.path.join(directory, "cert.pem"))
            url = "https://127.0.0.1:%s/api/graphql" % port
            scenarios = [
                ("T7", "PASS", {
                    "query": "mutation($threadId:ID!,$body:String!){addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:$threadId,body:$body}){comment{id}}}",
                    "variables": {"threadId": expected["thread_id"], "body": BODY},
                }),
                ("T8", "PASS", {
                    "query": "mutation{addComment(input:{subjectId:\"PR_kwDOMOCKF1\",body:\"%s\"}){commentEdge{node{id}}}}" % BODY,
                }),
                ("T9", "PASS", {
                    "query": "mutation($threadId:ID!){resolveReviewThread(input:{threadId:$threadId}){thread{id}}}",
                    "variables": {"threadId": expected["thread_id"]},
                }),
                ("T8", "FAIL", {
                    "query": "mutation{first:addComment(input:{subjectId:\"PR_kwDOMOCKF1\",body:\"%s\"}){commentEdge{node{id}}}second:addComment(input:{subjectId:\"PR_kwDOMOCKF1\",body:\"%s\"}){commentEdge{node{id}}}}" % (BODY, BODY),
                }),
            ]
            for task, verdict, payload in scenarios:
                post(url, payload, context)
                with open(os.path.join(directory, "calls.jsonl")) as fh:
                    call = json.loads(fh.readlines()[-1])
                if not call.get("graphql_arguments"):
                    raise AssertionError("%s: resolved arguments were not recorded" % task)
                grade(task, [call], expected, verdict, directory)

            post(url.replace("/api/graphql", "/api/v3/repos/ConstructEase/gh-ci-bench-fixture/issues/1/comments"),
                 {"body": BODY}, context)
            post(url, {
                "query": "mutation($threadId:ID!){good:resolveReviewThread(input:{threadId:$threadId}){thread{id}}bad:addComment(input:{subjectId:\"PR_kwDOMOCKF1\"}){commentEdge{node{id}}}}",
                "variables": {"threadId": expected["thread_id"]},
            }, context)
            with open(os.path.join(directory, "calls.jsonl")) as fh:
                calls = [json.loads(line) for line in fh]
            partial = calls[-1]
            if not partial.get("graphql_errors"):
                raise AssertionError("partial GraphQL failure was not recorded")
            successes = [item.get("succeeded")
                         for item in partial.get("graphql_arguments", [])]
            if successes != [True, False]:
                raise AssertionError("unexpected mutation outcomes: %r" % successes)
            grade("T8", calls[-2:], expected, "FAIL", directory)
        finally:
            subprocess.run(["bash", FORGE, "stop", directory], check=True)
    print("5 resolved GraphQL argument scenarios passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
