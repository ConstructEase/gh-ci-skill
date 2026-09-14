#!/usr/bin/env python3
import re
import sys


VERDICT = re.compile(r"^(PASS|FAIL) - (\S(?:.*\S)?)$")


def parse(text):
    lines = text.splitlines()
    if len(lines) != 1:
        return "ERROR"
    match = VERDICT.fullmatch(lines[0])
    if not match or len(match.group(2).split()) > 15:
        return "ERROR"
    return match.group(1)


def main():
    if len(sys.argv) != 2:
        return 2
    try:
        with open(sys.argv[1]) as fh:
            text = fh.read()
    except OSError:
        print("ERROR")
        return 0
    print(parse(text))
    return 0


if __name__ == "__main__":
    sys.exit(main())
