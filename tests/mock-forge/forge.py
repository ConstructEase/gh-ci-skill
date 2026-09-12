#!/usr/bin/env python3
"""A recording GitHub-API mock, served over HTTPS behind GH_HOST.

This is a local-only test fixture. It binds 127.0.0.1, makes no outward calls,
and has no code path that can reach github.com. `gh` (and therefore ci.sh and
gh-axi, which both shell out to it) talks to it when pointed at it with:

    GH_HOST=127.0.0.1:<port>
    GH_ENTERPRISE_TOKEN=<any non-empty string>
    SSL_CERT_FILE=<the cert this server was started with>
    GH_REPO=<owner>/<repo>

Three plumbing facts make that work, and each is load-bearing:
  * `gh` refuses plain HTTP, so this serves TLS with a throwaway self-signed
    cert; `SSL_CERT_FILE` is what makes `gh` trust it.
  * against a host that is not github.com, `gh` uses GitHub Enterprise paths:
    REST at /api/v3/<path>, GraphQL at /api/graphql.
  * `gh pr <sub>` compares the git remote against GH_HOST and bails on a
    mismatch; GH_REPO bypasses that check.

Every request is appended to the call log as one JSON object per line, which is
what turns "did the agent make the right write call?" into an assertion rather
than an opinion.

Control plane (not GitHub paths, so they cannot collide with a real route):
    POST /__control/reset   reload state from the seed file, truncate the log
    GET  /__control/calls   the call log as a JSON array
    GET  /__control/health  liveness probe

Usage: forge.py --port N --cert FILE --key FILE [--seed FILE] [--log FILE]
"""

import argparse
import http.server
import json
import os
import re
import ssl
import sys
import threading
import time
import urllib.parse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gql  # noqa: E402  (same directory; this file is a test fixture, not a package)

DEFAULT_SEED = os.path.join(os.path.dirname(os.path.abspath(__file__)), "seed.json")


class ForgeState:
    """The mutable fixture: one PR, its review threads, its comments.

    Guarded by a lock because http.server handles requests on one thread each.
    """

    def __init__(self, seed_path, log_path):
        self.seed_path = seed_path
        self.log_path = log_path
        self.lock = threading.Lock()
        self.reset()

    def reset(self):
        with open(self.seed_path) as fh:
            self.data = json.load(fh)
        self.next_id = int(self.data.get("next_id", 3995012347))
        # Deterministic PRNG state, reseeded on every reset so a run stays
        # reproducible while the ids it hands out still look like real ones.
        self._id_state = int(self.data.get("id_seed", 20260911))
        self.calls = []
        if self.log_path:
            open(self.log_path, "w").close()

    def record(self, entry):
        self.calls.append(entry)
        if self.log_path:
            with open(self.log_path, "a") as fh:
                fh.write(json.dumps(entry) + "\n")

    def alloc_id(self):
        """A new comment id that looks like one GitHub would actually issue.

        This matters more than it sounds. Real GitHub comment ids are 10 digits
        and far apart; an id like 900000001 reads as obviously synthetic, and
        anything grading the agent's prose -- an LLM judge, or a person --
        treats a round id in a returned URL as a sign the agent invented it.
        Stepping by a varying amount from a realistic base stops the fixture
        putting words in the agent's mouth.
        """
        self._id_state = (self._id_state * 1103515245 + 12345) % 2147483648
        self.next_id += 1 + self._id_state % 9973
        return self.next_id

    # -- lookups -----------------------------------------------------------
    def thread_by_node_id(self, node_id):
        for t in self.data["threads"]:
            if t["id"] == node_id:
                return t
        return None

    def thread_by_comment_db_id(self, db_id):
        for t in self.data["threads"]:
            for c in t["comments"]:
                if int(c["databaseId"]) == int(db_id):
                    return t
        return None


class ForgeHandler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    state = None  # injected by serve()

    # Keep the mock quiet; the call log is the record that matters.
    def log_message(self, fmt, *args):
        pass

    # -- plumbing ----------------------------------------------------------
    def _send(self, code, payload):
        if getattr(self, "_entry", None) is not None:
            self._entry["status"] = code
        self._last_payload = payload
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        # Real GitHub sends these and some clients read them.
        self.send_header("X-RateLimit-Limit", "5000")
        self.send_header("X-RateLimit-Remaining", "4999")
        self.end_headers()
        self.wfile.write(body)

    def _error(self, code, message):
        self._send(code, {"message": message,
                          "documentation_url": "https://docs.github.com/rest"})

    def _read_body(self):
        length = int(self.headers.get("Content-Length") or 0)
        if not length:
            return b""
        return self.rfile.read(length)

    def _rest_path(self):
        """Strip the GHES /api/v3 prefix `gh` adds, and the query string."""
        path = urllib.parse.urlparse(self.path).path
        if path.startswith("/api/v3/"):
            return path[len("/api/v3"):]
        return path

    def do_GET(self):
        self._handle("GET")

    def do_POST(self):
        self._handle("POST")

    def do_PATCH(self):
        self._handle("PATCH")

    def do_DELETE(self):
        self._handle("DELETE")

    def _handle(self, method):
        raw = self._read_body()
        try:
            parsed = json.loads(raw) if raw else None
        except ValueError:
            parsed = raw.decode("utf-8", "replace")

        path = urllib.parse.urlparse(self.path).path
        with self.state.lock:
            if path.startswith("/__control/"):
                self._control(method, path)
                return
            entry = {
                "ts": round(time.time(), 3),
                "method": method,
                "path": path,
                "rest_path": self._rest_path(),
                "query": urllib.parse.urlparse(self.path).query,
                "body": parsed,
                "status": None,
            }
            if path == "/api/graphql":
                entry["graphql_op"] = _graphql_op(parsed)
            # The entry is recorded after dispatch so it can carry the response
            # status. A caller grading the log needs that: an agent's first
            # attempt at an endpoint may 404, and only the call that actually
            # succeeded counts as the write it made.
            self._entry = entry
            try:
                if path == "/api/graphql":
                    self._graphql(parsed)
                    if entry.get("status") == 200 and _has_errors(self._last_payload):
                        entry["graphql_errors"] = True
                else:
                    self._rest(method, self._rest_path(), parsed)
            except BrokenPipeError:
                self.state.record(entry)
                raise
            except Exception as exc:  # a mock bug must be visible, not silent
                self._error(500, "mock forge error: %s" % exc)
            finally:
                self._entry = None
            self.state.record(entry)

    def _control(self, method, path):
        action = path[len("/__control/"):]
        if action == "reset" and method == "POST":
            self.state.reset()
            self._send(200, {"reset": True})
        elif action == "calls":
            self._send(200, self.state.calls)
        elif action == "health":
            self._send(200, {"ok": True})
        else:
            self._error(404, "unknown control action: %s" % action)

    # -- REST --------------------------------------------------------------
    def _rest(self, method, path, body):
        st = self.state
        d = st.data
        nwo = "%s/%s" % (d["owner"], d["repo"])

        if path == "/user":
            self._send(200, d["viewer"])
            return

        m = re.fullmatch(r"/repos/([^/]+)/([^/]+)", path)
        if m and method == "GET":
            self._send(200, _repo_obj(d))
            return

        # POST /repos/{o}/{r}/pulls/{n}/comments  -- reply (in_reply_to) or new thread
        m = re.fullmatch(r"/repos/([^/]+)/([^/]+)/pulls/(\d+)/comments", path)
        if m:
            if "%s/%s" % (m.group(1), m.group(2)) != nwo:
                self._error(404, "Not Found")
                return
            if method == "GET":
                self._send(200, [c for t in d["threads"] for c in t["comments"]])
                return
            body = body or {}
            text = body.get("body")
            if not text:
                self._error(422, "Validation Failed: body is required")
                return
            reply_to = body.get("in_reply_to")
            if reply_to is None:
                # Real GitHub needs commit_id/path to start a NEW thread. The
                # benchmark's reply task should never land here; make that loud.
                if not (body.get("commit_id") and body.get("path")):
                    self._error(422, "Validation Failed: in_reply_to, or "
                                     "commit_id and path, is required")
                    return
                thread = {
                    "id": "PRRT_kwMOCK%d" % st.alloc_id(),
                    "isResolved": False,
                    "isOutdated": False,
                    "comments": [],
                }
                d["threads"].append(thread)
            else:
                thread = st.thread_by_comment_db_id(reply_to)
                if thread is None:
                    self._error(422, "Validation Failed: in_reply_to %s is not "
                                     "a comment on this pull request" % reply_to)
                    return
            comment = _make_review_comment(d, st.alloc_id(), text, thread, reply_to)
            thread["comments"].append(comment)
            self._send(201, comment)
            return

        # POST /repos/{o}/{r}/pulls/{n}/comments/{comment_id}/replies
        # The dedicated reply endpoint. It is easy to miss that this exists --
        # it is a real route alongside the in_reply_to form, and an agent that
        # finds it should not be penalised for the mock not knowing it.
        m = re.fullmatch(r"/repos/([^/]+)/([^/]+)/pulls/(\d+)/comments/(\d+)/replies", path)
        if m and method == "POST":
            if "%s/%s" % (m.group(1), m.group(2)) != nwo:
                self._error(404, "Not Found")
                return
            text = (body or {}).get("body")
            if not text:
                self._error(422, "Validation Failed: body is required")
                return
            reply_to = int(m.group(4))
            thread = st.thread_by_comment_db_id(reply_to)
            if thread is None:
                self._error(404, "Not Found")
                return
            comment = _make_review_comment(d, st.alloc_id(), text, thread, reply_to)
            thread["comments"].append(comment)
            self._send(201, comment)
            return

        # POST /repos/{o}/{r}/issues/{n}/comments -- top-level PR comment
        m = re.fullmatch(r"/repos/([^/]+)/([^/]+)/issues/(\d+)/comments", path)
        if m:
            if "%s/%s" % (m.group(1), m.group(2)) != nwo:
                self._error(404, "Not Found")
                return
            if method == "GET":
                self._send(200, d["issue_comments"])
                return
            text = (body or {}).get("body")
            if not text:
                self._error(422, "Validation Failed: body is required")
                return
            comment = _make_issue_comment(d, st.alloc_id(), text)
            d["issue_comments"].append(comment)
            self._send(201, comment)
            return

        m = re.fullmatch(r"/repos/([^/]+)/([^/]+)/pulls/comments/(\d+)", path)
        if m and method == "GET":
            for t in d["threads"]:
                for c in t["comments"]:
                    if int(c["databaseId"]) == int(m.group(3)):
                        self._send(200, c)
                        return
            self._error(404, "Not Found")
            return

        m = re.fullmatch(r"/repos/([^/]+)/([^/]+)/issues/comments/(\d+)", path)
        if m and method == "GET":
            for c in d["issue_comments"]:
                if int(c["id"]) == int(m.group(3)):
                    self._send(200, c)
                    return
            self._error(404, "Not Found")
            return

        m = re.fullmatch(r"/repos/([^/]+)/([^/]+)/pulls/(\d+)", path)
        if m and method == "GET":
            self._send(200, _pull_obj(d))
            return

        m = re.fullmatch(r"/repos/([^/]+)/([^/]+)/pulls", path)
        if m and method == "GET":
            self._send(200, [_pull_obj(d)])
            return

        self._error(404, "mock forge: unrouted %s %s" % (method, path))

    # -- GraphQL -----------------------------------------------------------
    def _graphql(self, body):
        """Resolve against a generous universe, then project onto the selection.

        `gh` unmarshals strictly, so a response carrying fields the query did
        not select is an error. Projection also means an agent's hand-written
        mutation -- which is exactly what the gh and gh-axi conditions must
        produce, since neither has a reply or resolve command -- gets answered
        whatever selection set it happens to choose.
        """
        body = body or {}
        query = body.get("query") or ""
        variables = body.get("variables") or {}
        try:
            selections, fragments = gql.parse_document(query)
        except gql.ParseError as exc:
            self._graphql_errors(None, ["Parse error on GraphQL document: %s" % exc])
            return
        # The operation NAME is whatever the client called it ("CommentCreate"),
        # so it is useless for identifying what was done. The top-level FIELDS
        # are the mutation itself ("addComment"), which is what a grader needs.
        if getattr(self, "_entry", None) is not None:
            self._entry["graphql_fields"] = sorted(
                {f["name"] for f in gql._flatten(selections, fragments)})
        errors = []
        universe = self._universe(errors)
        data = gql.project(selections, universe, fragments, variables)
        if errors:
            self._graphql_errors(data if any(data.values()) else None, errors)
            return
        self._send(200, {"data": data})

    def _universe(self, errors):
        """Every root field the mock can answer, as a projectable tree.

        Values may be callables; the projector invokes them with the resolved
        arguments of the field that selected them, so mutation side effects
        fire if and only if the caller actually selected that mutation.
        """
        d = self.state.data

        def repository(args):
            if args.get("owner") and args.get("name"):
                if (args["owner"], args["name"]) != (d["owner"], d["repo"]):
                    errors.append("Could not resolve to a Repository with the name "
                                  "'%s/%s'." % (args["owner"], args["name"]))
                    return None
            return _repo_node(d)

        def node(args):
            node_id = args.get("id")
            thread = self.state.thread_by_node_id(node_id)
            if thread is not None:
                return _thread_node(d, thread)
            if node_id == d["pull"]["node_id"]:
                return _pull_node(d)
            errors.append("Could not resolve to a node with the global id of "
                          "'%s'" % node_id)
            return None

        def toggle(resolved, field):
            def run(args):
                inp = args.get("input") or {}
                thread_id = inp.get("threadId") or args.get("threadId")
                thread = self.state.thread_by_node_id(thread_id)
                if thread is None:
                    errors.append("Could not resolve to a node with the global "
                                  "id of '%s'" % thread_id)
                    return None
                thread["isResolved"] = resolved
                return {"__typename": "%sPayload" % field[0].upper() + field[1:],
                        "clientMutationId": inp.get("clientMutationId"),
                        "thread": _thread_node(d, thread)}
            return run

        def add_comment(args):
            inp = args.get("input") or {}
            text = inp.get("body") or args.get("body")
            subject = inp.get("subjectId") or args.get("subjectId")
            if not text:
                errors.append("Variable $input of type AddCommentInput! was "
                              "provided invalid value for body (Expected value "
                              "to not be null)")
                return None
            if subject and subject != d["pull"]["node_id"]:
                errors.append("Could not resolve to a node with the global id "
                              "of '%s'" % subject)
                return None
            comment = _make_issue_comment(d, self.state.alloc_id(), text)
            d["issue_comments"].append(comment)
            return {"__typename": "AddCommentPayload",
                    "clientMutationId": inp.get("clientMutationId"),
                    "subject": _pull_node(d),
                    "commentEdge": {"node": _issue_comment_node(d, comment)}}

        def reply_to_thread(args):
            """addPullRequestReviewThreadReply -- reply addressed by thread node id."""
            inp = args.get("input") or {}
            thread_id = inp.get("pullRequestReviewThreadId") or args.get("pullRequestReviewThreadId")
            text = inp.get("body") or args.get("body")
            thread = self.state.thread_by_node_id(thread_id)
            if thread is None:
                errors.append("Could not resolve to a node with the global id "
                              "of '%s'" % thread_id)
                return None
            if not text:
                errors.append("Variable $input was provided invalid value for "
                              "body (Expected value to not be null)")
                return None
            anchor = thread["comments"][0] if thread["comments"] else {}
            comment = _make_review_comment(d, self.state.alloc_id(), text, thread,
                                           anchor.get("databaseId"))
            thread["comments"].append(comment)
            return {"__typename": "AddPullRequestReviewThreadReplyPayload",
                    "clientMutationId": inp.get("clientMutationId"),
                    "comment": _review_comment_node(d, comment)}

        def add_review_comment(args):
            """addPullRequestReviewComment -- reply addressed by comment node id."""
            inp = args.get("input") or {}
            text = inp.get("body") or args.get("body")
            reply_to = inp.get("inReplyTo") or args.get("inReplyTo")
            thread = None
            for t in d["threads"]:
                for c in t["comments"]:
                    if c.get("node_id") == reply_to:
                        thread = t
            if thread is None:
                errors.append("Could not resolve to a node with the global id "
                              "of '%s'" % reply_to)
                return None
            anchor = thread["comments"][0] if thread["comments"] else {}
            comment = _make_review_comment(d, self.state.alloc_id(), text, thread,
                                           anchor.get("databaseId"))
            thread["comments"].append(comment)
            return {"__typename": "AddPullRequestReviewCommentPayload",
                    "clientMutationId": inp.get("clientMutationId"),
                    "comment": _review_comment_node(d, comment)}

        return {
            "__typename": "Query",
            "repository": repository,
            "viewer": _viewer_node(d),
            "node": node,
            "rateLimit": {"limit": 5000, "remaining": 4999, "cost": 1,
                          "used": 1, "resetAt": d["now"]},
            "resolveReviewThread": toggle(True, "resolveReviewThread"),
            "unresolveReviewThread": toggle(False, "unresolveReviewThread"),
            "addComment": add_comment,
            "addPullRequestReviewThreadReply": reply_to_thread,
            "addPullRequestReviewComment": add_review_comment,
        }

    def _graphql_errors(self, data, messages):
        # GraphQL errors ride on HTTP 200 with an `errors` array, as on real GitHub.
        self._send(200, {"data": data,
                         "errors": [{"message": m} for m in messages]})


# -- response builders -----------------------------------------------------

def _has_errors(payload):
    return isinstance(payload, dict) and bool(payload.get("errors"))


def _graphql_op(body):
    """A short label for the call log: the operation name, or the first field."""
    if not isinstance(body, dict):
        return None
    query = body.get("query") or ""
    if body.get("operationName"):
        return body["operationName"]
    m = re.search(r"\b(?:query|mutation)\s+(\w+)", query)
    if m:
        return m.group(1)
    # Order matters: "resolveReviewThread" is a substring of
    # "unresolveReviewThread", so the longer name has to be tested first.
    for known in ("unresolveReviewThread", "resolveReviewThread",
                  "addPullRequestReviewThreadReply", "addPullRequestReviewComment",
                  "addComment", "reviewThreads", "pullRequest", "viewer"):
        if known in query:
            return known
    return "anonymous"


def _html_url(d, suffix):
    return "https://github.com/%s/%s/pull/%d%s" % (
        d["owner"], d["repo"], d["pull"]["number"], suffix)


def _make_review_comment(d, new_id, text, thread, reply_to):
    anchor = thread["comments"][0] if thread["comments"] else {}
    return {
        "id": new_id,
        "databaseId": new_id,
        "node_id": "PRRC_kwMOCK%d" % new_id,
        "pull_request_review_id": new_id - 4177,
        "in_reply_to_id": reply_to,
        "user": {"login": d["viewer"]["login"], "id": d["viewer"]["id"]},
        "body": text,
        "path": anchor.get("path", d["pull"]["head_path"]),
        "line": anchor.get("line", 1),
        "original_line": anchor.get("originalLine", 1),
        "diff_hunk": anchor.get("diffHunk", "@@ -1 +1 @@"),
        "commit_id": d["pull"]["head_sha"],
        "created_at": d["now"],
        "updated_at": d["now"],
        "html_url": _html_url(d, "#discussion_r%d" % new_id),
    }


def _make_issue_comment(d, new_id, text):
    return {
        "id": new_id,
        "node_id": "IC_kwMOCK%d" % new_id,
        "user": {"login": d["viewer"]["login"], "id": d["viewer"]["id"]},
        "body": text,
        "created_at": d["now"],
        "updated_at": d["now"],
        "html_url": _html_url(d, "#issuecomment-%d" % new_id),
    }


def _repo_obj(d):
    """A repository in REST spelling (snake_case)."""
    return {
        "id": 1,
        "node_id": d["repo_node_id"],
        "name": d["repo"],
        "full_name": "%s/%s" % (d["owner"], d["repo"]),
        "private": True,
        "owner": {"login": d["owner"], "id": 2, "type": "Organization"},
        "html_url": "https://github.com/%s/%s" % (d["owner"], d["repo"]),
        "default_branch": "main",
        "archived": False,
        "has_issues": True,
        "permissions": {"admin": True, "push": True, "pull": True},
    }


def _pull_obj(d):
    """A pull request in REST spelling."""
    p = d["pull"]
    return {
        "id": 10,
        "node_id": p["node_id"],
        "number": p["number"],
        "state": p["state"].lower(),
        "title": p["title"],
        "body": p.get("body", ""),
        "user": {"login": d["viewer"]["login"], "id": d["viewer"]["id"]},
        "html_url": "https://github.com/%s/%s/pull/%d" % (d["owner"], d["repo"], p["number"]),
        "head": {"ref": p["head_ref"], "sha": p["head_sha"],
                 "repo": _repo_obj(d)},
        "base": {"ref": "main", "sha": p["head_sha"], "repo": _repo_obj(d)},
        "merged": False,
        "mergeable": True,
        "mergeable_state": "clean",
        "draft": False,
        "created_at": d["now"],
        "updated_at": d["now"],
    }


def _viewer_node(d):
    v = d["viewer"]
    return {"__typename": "User", "id": v["node_id"], "login": v["login"],
            "name": v.get("name"), "databaseId": v["id"],
            "url": "https://github.com/%s" % v["login"]}


def _author_node(login):
    return {"__typename": "User", "login": login,
            "url": "https://github.com/%s" % login}


def _review_comment_node(d, c):
    """A PullRequestReviewComment in GraphQL spelling (camelCase)."""
    login = (c["user"]["login"] if isinstance(c.get("user"), dict)
             else (c.get("author") or {}).get("login"))
    return {
        "__typename": "PullRequestReviewComment",
        "id": c.get("node_id"),
        "databaseId": c.get("databaseId", c.get("id")),
        "body": c["body"],
        "bodyText": c["body"],
        "path": c.get("path"),
        "line": c.get("line"),
        "originalLine": c.get("originalLine", c.get("original_line")),
        "diffHunk": c.get("diffHunk", c.get("diff_hunk")),
        "author": _author_node(login),
        "createdAt": c.get("createdAt", c.get("created_at")),
        "updatedAt": c.get("updatedAt", c.get("updated_at", c.get("created_at"))),
        "url": c.get("html_url"),
        "replyTo": ({"id": None, "databaseId": c.get("in_reply_to_id")}
                    if c.get("in_reply_to_id") else None),
        "viewerDidAuthor": login == d["viewer"]["login"],
    }


def _issue_comment_node(d, c):
    return {
        "__typename": "IssueComment",
        "id": c["node_id"],
        "databaseId": c["id"],
        "body": c["body"],
        "bodyText": c["body"],
        "author": _author_node(c["user"]["login"]),
        "createdAt": c["created_at"],
        "updatedAt": c["updated_at"],
        "url": c["html_url"],
        "viewerDidAuthor": c["user"]["login"] == d["viewer"]["login"],
    }


def _connection(nodes):
    return {"nodes": nodes, "totalCount": len(nodes),
            "edges": [{"node": n, "cursor": "cursor%d" % i}
                      for i, n in enumerate(nodes)],
            "pageInfo": {"hasNextPage": False, "endCursor": None}}


def _thread_node(d, t):
    comments = [_review_comment_node(d, c) for c in t["comments"]]
    first = t["comments"][0] if t["comments"] else {}
    return {
        "__typename": "PullRequestReviewThread",
        "id": t["id"],
        "isResolved": t["isResolved"],
        "isOutdated": t["isOutdated"],
        "isCollapsed": t["isResolved"] or t["isOutdated"],
        "resolvedBy": _viewer_node(d) if t["isResolved"] else None,
        "viewerCanResolve": not t["isResolved"],
        "viewerCanUnresolve": t["isResolved"],
        "viewerCanReply": True,
        "path": first.get("path"),
        "line": first.get("line"),
        "originalLine": first.get("originalLine", first.get("original_line")),
        "diffSide": "RIGHT",
        "comments": _connection(comments),
    }


def _pull_node(d):
    p = d["pull"]
    url = "https://github.com/%s/%s/pull/%d" % (d["owner"], d["repo"], p["number"])
    return {
        "__typename": "PullRequest",
        "id": p["node_id"],
        "number": p["number"],
        "title": p["title"],
        "body": p.get("body", ""),
        "bodyText": p.get("body", ""),
        "state": p["state"],
        "url": url,
        "isDraft": False,
        "closed": p["state"] != "OPEN",
        "merged": False,
        "mergeable": "MERGEABLE",
        "mergeStateStatus": "CLEAN",
        "reviewDecision": p.get("review_decision"),
        "headRefName": p["head_ref"],
        "headRefOid": p["head_sha"],
        "baseRefName": "main",
        "author": _viewer_node(d),
        "createdAt": d["now"],
        "updatedAt": d["now"],
        "viewerCanUpdate": True,
        "locked": False,
        "comments": _connection([_issue_comment_node(d, c) for c in d["issue_comments"]]),
        "reviews": _connection([]),
        "reviewRequests": _connection([]),
        "commits": _connection([]),
        "files": _connection([]),
        "labels": _connection([]),
        "assignees": _connection([]),
        "statusCheckRollup": None,
        "reviewThreads": _connection([_thread_node(d, t) for t in d["threads"]]),
    }


def _repo_node(d):
    def pull_request(args):
        number = args.get("number")
        if number is not None and int(number) != d["pull"]["number"]:
            return None
        return _pull_node(d)

    return {
        "__typename": "Repository",
        "id": d["repo_node_id"],
        "name": d["repo"],
        "owner": {"__typename": "Organization", "login": d["owner"],
                  "id": "O_kgDOMOCK1",
                  "url": "https://github.com/%s" % d["owner"]},
        "nameWithOwner": "%s/%s" % (d["owner"], d["repo"]),
        "url": "https://github.com/%s/%s" % (d["owner"], d["repo"]),
        "isPrivate": True,
        "isArchived": False,
        "hasIssuesEnabled": True,
        "hasDiscussionsEnabled": False,
        "viewerPermission": "ADMIN",
        "defaultBranchRef": {"name": "main"},
        "pullRequest": pull_request,
        "pullRequests": _connection([_pull_node(d)]),
    }


def serve(args):
    state = ForgeState(args.seed, args.log)
    handler = type("BoundForgeHandler", (ForgeHandler,), {"state": state})
    httpd = http.server.ThreadingHTTPServer(("127.0.0.1", args.port), handler)
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(args.cert, args.key)
    httpd.socket = ctx.wrap_socket(httpd.socket, server_side=True)
    port = httpd.socket.getsockname()[1]
    if args.port_file:
        with open(args.port_file, "w") as fh:
            fh.write("%d\n" % port)
    sys.stderr.write("mock forge listening on https://127.0.0.1:%d\n" % port)
    sys.stderr.flush()
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--port", type=int, default=0, help="0 picks a free port")
    ap.add_argument("--cert", required=True)
    ap.add_argument("--key", required=True)
    ap.add_argument("--seed", default=DEFAULT_SEED)
    ap.add_argument("--log", default="")
    ap.add_argument("--port-file", default="")
    serve(ap.parse_args())


if __name__ == "__main__":
    main()
