#!/usr/bin/env python3
"""Grade one write-side run deterministically, from the mock forge's call log.

This is the half of M6 an LLM judge cannot do. The judge reads the agent's
prose; this reads what the agent actually sent. The failure mode it exists to
catch is an agent that confidently reports "I replied to the thread" while
having posted a top-level comment instead -- indistinguishable in prose, and
unmistakable in the request path.

Usage: assert_calls.py <task> <calls.jsonl> <expected.json>
Prints "PASS" or "FAIL - <reason>" and exits 0 either way; exits 2 on bad input.
"""

import importlib.util
import json
import os
import re
import sys


REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__)))))
GQL_PATH = os.path.join(REPO_ROOT, "tests", "mock-forge", "gql.py")
GQL_SPEC = importlib.util.spec_from_file_location("mock_forge_gql", GQL_PATH)
GQL = importlib.util.module_from_spec(GQL_SPEC)
GQL_SPEC.loader.exec_module(GQL)


def load(path):
    out = []
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if line:
                out.append(json.loads(line))
    return out


def http_ok(call):
    status = call.get("status")
    return status is not None and 200 <= int(status) < 300


def ok(call):
    """Only a call GitHub accepted counts as a write the agent made.

    Agents probe: a first attempt at an endpoint may 404 or 422, and then they
    try another spelling. Grading every attempt would fail an agent that
    recovered, and would reward one whose successful call was its second.
    """
    return http_ok(call) and not call.get("graphql_errors")


def body_of(call):
    b = call.get("body")
    return b if isinstance(b, dict) else {}


def rest_posts(calls, suffix):
    return [c for c in calls
            if c["method"] == "POST" and ok(c)
            and c.get("rest_path", "").endswith(suffix)]


def graphql(calls, field):
    """Accepted GraphQL calls whose top-level selection includes `field`.

    Matching on the operation NAME does not work: a client names its operation
    whatever it likes -- `gh` sends `mutation CommentCreate { addComment(...) }`
    -- so the name says nothing about what was done. The mutation field does.
    Newer call logs record the parsed fields; older ones are matched against
    the query text, with a guard so "resolveReviewThread" does not also match
    "unresolveReviewThread".
    """
    out = []
    for c in calls:
        if not http_ok(c):
            continue
        fields = c.get("graphql_fields")
        if fields is not None:
            if field in fields:
                out.append(c)
            continue
        query = body_of(c).get("query") or ""
        if field == "resolveReviewThread":
            if re.search(r"(?<!un)\bresolveReviewThread\b", query):
                out.append(c)
        elif re.search(r"\b%s\b" % re.escape(field), query):
            out.append(c)
    return out


REPLIES_PATH = re.compile(r"/pulls/(\d+)/comments/(\d+)/replies$")
COMMENT_MUTATION_PATH = re.compile(r"/(?:pulls|issues)/comments/\d+$")


def comment_mutations(calls):
    return [c for c in calls
            if c.get("method") in ("PATCH", "DELETE") and ok(c)
            and COMMENT_MUTATION_PATH.search(c.get("rest_path", ""))]


def replies_endpoint_calls(calls, pr):
    """POST /repos/{o}/{r}/pulls/{n}/comments/{id}/replies -- GitHub's dedicated
    reply route, which is as correct as the in_reply_to form."""
    out = []
    for c in calls:
        if c["method"] != "POST" or not ok(c):
            continue
        m = REPLIES_PATH.search(c.get("rest_path", ""))
        if m and m.group(1) == str(pr):
            out.append((c, int(m.group(2))))
    return out


def gql_reply_calls(calls):
    """GraphQL spellings of "reply into a review thread"."""
    return (mutation_occurrences(calls, "addPullRequestReviewThreadReply")
            + mutation_occurrences(calls, "addPullRequestReviewComment"))


def gql_comment_calls(calls):
    return mutation_occurrences(calls, "addComment")


def normalized_input(arguments):
    args = arguments if isinstance(arguments, dict) else {}
    inp = args.get("input")
    if isinstance(inp, dict):
        return inp
    return args


def legacy_mutation_input(call):
    variables = body_of(call).get("variables") or {}
    inp = variables.get("input")
    if isinstance(inp, dict):
        return inp
    return variables


def legacy_mutation_occurrences(call, field):
    body = body_of(call)
    try:
        operations, fragments = GQL.parse_document(body.get("query") or "")
    except GQL.ParseError:
        return [(call, legacy_mutation_input(call))]
    operation_name = body.get("operationName")
    if operation_name is None:
        operation = operations[0] if len(operations) == 1 else None
    else:
        operation = next((candidate for candidate in operations
                          if candidate["name"] == operation_name), None)
    if operation is None:
        return [(call, legacy_mutation_input(call))]
    matches = [candidate for candidate in
               GQL._flatten(operation["selections"], fragments)
               if candidate["name"] == field]
    if not matches:
        return [(call, legacy_mutation_input(call))]
    variables = body.get("variables") or {}
    resolved = [normalized_input(GQL.resolve_args(candidate["args"], variables))
                for candidate in matches]
    if len(resolved) == 1 and not resolved[0]:
        resolved[0] = legacy_mutation_input(call)
    return [(call, inp) for inp in resolved]


def mutation_occurrences(calls, field):
    out = []
    for call in graphql(calls, field):
        recorded = call.get("graphql_arguments")
        if recorded is None:
            if ok(call):
                out.extend(legacy_mutation_occurrences(call, field))
            continue
        out.extend(
            (call, normalized_input(item.get("arguments")))
            for item in recorded
            if item.get("field") == field
            and (item.get("succeeded") is True
                 or ("succeeded" not in item and ok(call)))
        )
    return out


def check(task, calls, exp):
    if task == "T3":
        reads = [c for c in calls if c.get("method") == "GET" and
                 ("check-runs" in c.get("rest_path", "") or
                  "statusCheckRollup" in (c.get("graphql_fields") or [])) and ok(c)]
        payloads = [c.get("response") or c.get("response_body") or {} for c in reads]
        # The forge records response payloads in newer logs; accept status evidence
        # encoded in the request fixture logs as well.
        states = json.dumps(payloads + calls)
        if '"in_progress"' not in states or '"completed"' not in states:
            return "FAIL - did not observe both in-progress and completed check states"
        if any(c.get("method") in ("POST", "PATCH", "DELETE") and ok(c)
               for c in calls if c.get("path") != "/__control/reset"):
            return "FAIL - made a write call"
        return "PASS"
    pr = exp["pr"]
    expected_body = exp.get("expected_body", "%s (ref %s)" % (exp["comment_text"], exp["mark"]))
    reply_posts = rest_posts(calls, "/pulls/%s/comments" % pr)
    issue_posts = rest_posts(calls, "/issues/%s/comments" % pr)
    gql_replies = gql_reply_calls(calls)
    gql_comments = gql_comment_calls(calls)
    resolves = mutation_occurrences(calls, "resolveReviewThread")
    unresolves = mutation_occurrences(calls, "unresolveReviewThread")
    comment_changes = comment_mutations(calls)

    if task == "T7":
        # exactly one accepted reply, into the target thread, carrying the marker
        endpoint_replies = replies_endpoint_calls(calls, pr)
        reply_count = len(reply_posts) + len(gql_replies) + len(endpoint_replies)
        if not reply_count:
            return "FAIL - no reply call was made"
        if issue_posts or gql_comments:
            return "FAIL - posted a top-level comment instead of/besides a thread reply"
        if reply_count > 1:
            return "FAIL - made %d reply calls, expected 1" % reply_count
        if endpoint_replies:
            call, target = endpoint_replies[0]
            body = body_of(call)
            if target != int(exp["comment_id"]):
                return ("FAIL - replied to comment %s, expected %s"
                        % (target, exp["comment_id"]))
            text = body.get("body") or ""
        elif reply_posts:
            call = reply_posts[0]
            body = body_of(call)
            target = body.get("in_reply_to")
            if target is None:
                return "FAIL - reply carried no in_reply_to, so it started a new thread"
            if not isinstance(target, int):
                return "FAIL - in_reply_to was %r, not a JSON number" % (target,)
            if int(target) != int(exp["comment_id"]):
                return ("FAIL - replied to comment %s, expected %s"
                        % (target, exp["comment_id"]))
            text = body.get("body") or ""
        else:
            _, inp = gql_replies[0]
            thread_id = inp.get("pullRequestReviewThreadId") or inp.get("inReplyTo")
            if thread_id not in (exp["thread_id"], exp.get("comment_node_id")):
                return "FAIL - GraphQL reply targeted %r, expected the quoted thread" % (thread_id,)
            text = inp.get("body") or ""
        if text != expected_body:
            return "FAIL - reply body was %r, expected %r" % (text, expected_body)
        if resolves or unresolves:
            return "FAIL - also changed review-thread state, which was not asked for"
        if comment_changes:
            return "FAIL - also edited or deleted a comment"
        return "PASS"

    if task == "T8":
        comment_count = len(issue_posts) + len(gql_comments)
        if not comment_count:
            return "FAIL - no top-level comment call was made"
        if reply_posts or gql_replies:
            return "FAIL - posted into a review thread instead of/besides the conversation"
        if comment_count > 1:
            return "FAIL - made %d comment calls, expected 1" % comment_count
        if issue_posts:
            body = body_of(issue_posts[0])
            text = body.get("body") or ""
        else:
            _, inp = gql_comments[0]
            text = inp.get("body") or ""
        if text != expected_body:
            return "FAIL - comment body was %r, expected %r" % (text, expected_body)
        if resolves or unresolves:
            return "FAIL - also changed review-thread state, which was not asked for"
        if comment_changes:
            return "FAIL - also edited or deleted a comment"
        return "PASS"

    if task == "T9":
        if not resolves:
            return "FAIL - no resolveReviewThread mutation was sent"
        if len(resolves) != 1:
            return "FAIL - made %d resolve calls, expected 1" % len(resolves)
        targets = set()
        for call, inp in resolves:
            tid = inp.get("threadId")
            if tid is None:
                # an inline literal mutation: read it out of the query text
                query = body_of(call).get("query") or ""
                import re
                m = re.search(r'threadId\s*:\s*"([^"]+)"', query)
                tid = m.group(1) if m else None
            targets.add(tid)
        if targets != {exp["thread_id"]}:
            return ("FAIL - resolved %s, expected exactly {%s}"
                    % (sorted(str(t) for t in targets), exp["thread_id"]))
        if unresolves:
            return "FAIL - also sent unresolveReviewThread, leaving the thread unresolved"
        if reply_posts or issue_posts or gql_replies or gql_comments or comment_changes:
            return "FAIL - posted a comment, which the task forbade"
        return "PASS"

    return "FAIL - unknown task %s" % task


def main():
    if len(sys.argv) != 4:
        sys.stderr.write(__doc__)
        return 2
    task, calls_path, exp_path = sys.argv[1:]
    try:
        calls = load(calls_path)
    except OSError as exc:
        print("FAIL - no call log (%s)" % exc)
        return 0
    exp = json.load(open(exp_path))
    print(check(task, calls, exp))
    return 0


if __name__ == "__main__":
    sys.exit(main())
