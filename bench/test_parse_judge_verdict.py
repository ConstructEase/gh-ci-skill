#!/usr/bin/env python3
import os
import subprocess
import sys
import tempfile


PARSER = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                      "parse-judge-verdict.py")
CASES = [
    ("PASS - correct answer\n", "PASS"),
    ("FAIL - omitted a required result\n", "FAIL"),
    ("I would FAIL this; it does not PASS\n", "ERROR"),
    ("PASS - first line\nFAIL - second line\n", "ERROR"),
    ("pass - lowercase verdict\n", "ERROR"),
    ("PASS - \n", "ERROR"),
    ("PASS - one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen\n", "PASS"),
    ("PASS - one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen\n", "ERROR"),
]


def main():
    failures = 0
    with tempfile.TemporaryDirectory() as tmp:
        for index, (content, expected) in enumerate(CASES):
            path = os.path.join(tmp, "judge-%d.txt" % index)
            with open(path, "w") as fh:
                fh.write(content)
            result = subprocess.run([sys.executable, PARSER, path],
                                    capture_output=True, text=True, check=True)
            actual = result.stdout.strip()
            if actual != expected:
                failures += 1
                print("case %d: expected %s, got %s" % (index, expected, actual))
    print("%d case(s) wrong out of %d" % (failures, len(CASES)))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
