#!/usr/bin/env python3
"""A minimal GraphQL selection-set parser and response projector.

The mock forge needs this because `gh` unmarshals GraphQL responses into Go
structs strictly: a field the query did not ask for is an error, not extra
credit ("struct field for \"id\" doesn't exist in any of 1 places to
unmarshal"). So the mock builds one generous "universe" of data and then
projects it down to exactly the shape the caller selected.

It also buys the benchmark something it genuinely needs: the `gh` and `gh-axi`
conditions have no command for reply/resolve, so their agents hand-author
GraphQL with selection sets nobody can predict. Projection answers whatever
they ask, instead of only the queries that were anticipated.

This is not a GraphQL implementation. It handles what a client sends: named and
anonymous operations, variables, aliases, arguments, nested selections, inline
fragments and named fragment spreads. It does not validate against a schema.
"""

import re

NAME = re.compile(r"[_A-Za-z][_0-9A-Za-z]*")


class ParseError(ValueError):
    pass


class _Cursor:
    def __init__(self, text):
        self.s = text
        self.i = 0

    def skip_ignored(self):
        """Whitespace, commas (which GraphQL treats as whitespace) and comments."""
        while self.i < len(self.s):
            ch = self.s[self.i]
            if ch in " \t\r\n,﻿":
                self.i += 1
            elif ch == "#":
                while self.i < len(self.s) and self.s[self.i] != "\n":
                    self.i += 1
            else:
                return

    def peek(self):
        self.skip_ignored()
        return self.s[self.i] if self.i < len(self.s) else ""

    def expect(self, ch):
        if self.peek() != ch:
            raise ParseError("expected %r at offset %d" % (ch, self.i))
        self.i += 1

    def name(self):
        self.skip_ignored()
        m = NAME.match(self.s, self.i)
        if not m:
            raise ParseError("expected a name at offset %d" % self.i)
        self.i = m.end()
        return m.group(0)


def _parse_string(cur):
    s, i = cur.s, cur.i
    if s.startswith('"""', i):
        end = s.index('"""', i + 3)
        cur.i = end + 3
        return s[i + 3:end]
    out = []
    i += 1
    while i < len(s):
        ch = s[i]
        if ch == "\\":
            nxt = s[i + 1]
            out.append({"n": "\n", "t": "\t", "r": "\r", "b": "\b",
                        "f": "\f"}.get(nxt, nxt))
            i += 2
            continue
        if ch == '"':
            cur.i = i + 1
            return "".join(out)
        out.append(ch)
        i += 1
    raise ParseError("unterminated string")


def _parse_value(cur):
    ch = cur.peek()
    if ch == "$":
        cur.i += 1
        return {"__var": cur.name()}
    if ch == '"':
        return _parse_string(cur)
    if ch == "{":
        cur.i += 1
        obj = {}
        while cur.peek() != "}":
            key = cur.name()
            cur.expect(":")
            obj[key] = _parse_value(cur)
        cur.i += 1
        return obj
    if ch == "[":
        cur.i += 1
        items = []
        while cur.peek() != "]":
            items.append(_parse_value(cur))
        cur.i += 1
        return items
    m = re.compile(r"-?\d+\.\d+([eE][+-]?\d+)?|-?\d+").match(cur.s, cur.i)
    if m and cur.s[cur.i] in "-0123456789":
        cur.i = m.end()
        text = m.group(0)
        return float(text) if ("." in text or "e" in text.lower()) else int(text)
    word = cur.name()
    if word == "true":
        return True
    if word == "false":
        return False
    if word == "null":
        return None
    return word  # an enum value


def _parse_arguments(cur):
    args = {}
    if cur.peek() != "(":
        return args
    cur.i += 1
    while cur.peek() != ")":
        key = cur.name()
        cur.expect(":")
        args[key] = _parse_value(cur)
    cur.i += 1
    return args


def _skip_directives(cur):
    while cur.peek() == "@":
        cur.i += 1
        cur.name()
        _parse_arguments(cur)


def _parse_selection_set(cur):
    cur.expect("{")
    fields = []
    while True:
        ch = cur.peek()
        if ch == "}":
            cur.i += 1
            return fields
        if ch == "":
            raise ParseError("unterminated selection set")
        if cur.s.startswith("...", cur.i):
            cur.i += 3
            if cur.peek() == "{":  # inline fragment with no type condition
                fields.append({"spread": None, "sel": _parse_selection_set(cur)})
                continue
            word = cur.name()
            if word == "on":
                cur.name()  # the type condition, which we do not check
                _skip_directives(cur)
                fields.append({"spread": None, "sel": _parse_selection_set(cur)})
            else:
                _skip_directives(cur)
                fields.append({"spread": word, "sel": None})
            continue
        name = cur.name()
        alias = None
        if cur.peek() == ":":
            cur.i += 1
            alias, name = name, cur.name()
        args = _parse_arguments(cur)
        _skip_directives(cur)
        sel = _parse_selection_set(cur) if cur.peek() == "{" else None
        fields.append({"name": name, "alias": alias or name,
                       "args": args, "sel": sel})


def parse_document(text):
    """-> (operation_type, root_selection_set, fragments)

    If the document holds several operations, the first is used; clients that
    send more than one also send operationName, which nothing here needs.
    """
    fragments = {}
    root = None
    operation_type = None
    cur = _Cursor(text)
    while True:
        ch = cur.peek()
        if ch == "":
            break
        if ch == "{":  # anonymous query
            sel = _parse_selection_set(cur)
            if root is None:
                root = sel
                operation_type = "query"
            continue
        word = cur.name()
        if word == "fragment":
            fname = cur.name()
            cur.name()  # "on"
            cur.name()  # type condition
            _skip_directives(cur)
            fragments[fname] = _parse_selection_set(cur)
            continue
        if word in ("query", "mutation", "subscription"):
            if cur.peek() not in ("(", "{"):
                cur.name()  # operation name
            if cur.peek() == "(":  # variable definitions
                depth = 0
                while True:
                    c = cur.s[cur.i]
                    if c == "(":
                        depth += 1
                    elif c == ")":
                        depth -= 1
                        cur.i += 1
                        if depth == 0:
                            break
                        continue
                    elif c == '"':
                        _parse_string(cur)
                        continue
                    cur.i += 1
            _skip_directives(cur)
            sel = _parse_selection_set(cur)
            if root is None:
                root = sel
                operation_type = word
            continue
        raise ParseError("unexpected token %r at offset %d" % (word, cur.i))
    if root is None:
        raise ParseError("document has no operation")
    return operation_type, root, fragments


def resolve_args(args, variables):
    """Substitute $variables into a parsed argument tree."""
    if isinstance(args, dict):
        if set(args) == {"__var"}:
            return (variables or {}).get(args["__var"])
        return {k: resolve_args(v, variables) for k, v in args.items()}
    if isinstance(args, list):
        return [resolve_args(v, variables) for v in args]
    return args


def _flatten(selections, fragments):
    """Expand fragment spreads into a flat list of concrete fields."""
    out = []
    for field in selections:
        if "spread" in field:
            sub = field["sel"]
            if sub is None:
                sub = fragments.get(field["spread"], [])
            out.extend(_flatten(sub, fragments))
        else:
            out.append(field)
    return out


def project(selections, source, fragments=None, variables=None):
    """Shape `source` into exactly the fields `selections` asks for.

    A value in `source` may be a callable, which is invoked with the field's
    resolved arguments -- that is how `pullRequest(number: N)` gets to check
    the number it was given. A selected field the source does not carry comes
    back as null rather than being dropped, so a client asking for something
    unmodelled gets a well-formed response instead of a parse failure.
    """
    fragments = fragments or {}
    if source is None:
        return None
    if isinstance(source, list):
        return [project(selections, item, fragments, variables) for item in source]

    out = {}
    for field in _flatten(selections, fragments):
        name, alias = field["name"], field["alias"]
        if name == "__typename":
            out[alias] = source.get("__typename", "Unknown") if isinstance(source, dict) else "Unknown"
            continue
        value = source.get(name) if isinstance(source, dict) else None
        if callable(value):
            value = value(resolve_args(field["args"], variables))
        if field["sel"]:
            out[alias] = project(field["sel"], value, fragments, variables)
        else:
            out[alias] = _scalarize(value)
    return out


def _scalarize(value):
    """A leaf selection on a composite value would be a schema error upstream;
    here it just means the caller wanted an id-ish summary, so give it one."""
    if callable(value):
        value = value({})
    if isinstance(value, dict):
        return value.get("id") or value.get("login") or None
    return value
