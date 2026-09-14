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

import json
import re
import sys


def load(path):
    out = []
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if line:
                out.append(json.loads(line))
    return out


def ok(call):
    """Only a call GitHub accepted counts as a write the agent made.

    Agents probe: a first attempt at an endpoint may 404 or 422, and then they
    try another spelling. Grading every attempt would fail an agent that
    recovered, and would reward one whose successful call was its second.
    """
    status = call.get("status")
    if status is None or not (200 <= int(status) < 300):
        return False
    return not call.get("graphql_errors")


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
        if not ok(c):
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
    return (graphql(calls, "addPullRequestReviewThreadReply")
            + graphql(calls, "addPullRequestReviewComment"))


def gql_comment_calls(calls):
    return graphql(calls, "addComment")


def check(task, calls, exp):
    pr = exp["pr"]
    mark = exp["mark"]
    reply_posts = rest_posts(calls, "/pulls/%s/comments" % pr)
    issue_posts = rest_posts(calls, "/issues/%s/comments" % pr)
    gql_replies = gql_reply_calls(calls)
    gql_comments = gql_comment_calls(calls)
    resolves = graphql(calls, "resolveReviewThread")
    unresolves = graphql(calls, "unresolveReviewThread")

    if task == "T7":
        # exactly one accepted reply, into the target thread, carrying the marker
        endpoint_replies = replies_endpoint_calls(calls, pr)
        replies = reply_posts + gql_replies + [c for c, _ in endpoint_replies]
        if not replies:
            return "FAIL - no reply call was made"
        if issue_posts or gql_comments:
            return "FAIL - posted a top-level comment instead of/besides a thread reply"
        if len(replies) > 1:
            return "FAIL - made %d reply calls, expected 1" % len(replies)
        call = replies[0]
        body = body_of(call)
        if endpoint_replies:
            _, target = endpoint_replies[0]
            if target != int(exp["comment_id"]):
                return ("FAIL - replied to comment %s, expected %s"
                        % (target, exp["comment_id"]))
            text = body.get("body") or ""
        elif call in reply_posts:
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
            variables = body.get("variables") or {}
            inp = variables.get("input") or {}
            thread_id = inp.get("pullRequestReviewThreadId") or inp.get("inReplyTo")
            if thread_id not in (exp["thread_id"], exp.get("comment_node_id")):
                return "FAIL - GraphQL reply targeted %r, expected the quoted thread" % (thread_id,)
            text = inp.get("body") or ""
        if mark not in text:
            return "FAIL - reply body did not carry the requested text (%r)" % mark
        if resolves:
            return "FAIL - also resolved a thread, which was not asked for"
        return "PASS"

    if task == "T8":
        comments = issue_posts + gql_comments
        if not comments:
            return "FAIL - no top-level comment call was made"
        if reply_posts or gql_replies:
            return "FAIL - posted into a review thread instead of/besides the conversation"
        if len(comments) > 1:
            return "FAIL - made %d comment calls, expected 1" % len(comments)
        call = comments[0]
        body = body_of(call)
        if call in issue_posts:
            text = body.get("body") or ""
        else:
            inp = ((body.get("variables") or {}).get("input")) or {}
            text = inp.get("body") or ""
        if mark not in text:
            return "FAIL - comment body did not carry the requested text (%r)" % mark
        return "PASS"

    if task == "T9":
        if not resolves:
            return "FAIL - no resolveReviewThread mutation was sent"
        targets = set()
        for call in resolves:
            variables = body_of(call).get("variables") or {}
            tid = variables.get("threadId")
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
        if reply_posts or issue_posts or gql_replies or gql_comments:
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
