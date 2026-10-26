#!/usr/bin/env python3
"""Require completed XCTest evidence for the registered pinned-source checks.

This verifies execution, not the adequacy of each comparison or full parity.
The caller must also check the test process exit status.
"""
import argparse
import json
from pathlib import Path
import re
import sys

REVISION = "91bd24bb8513785c7364cbea29296ff7adafac41"
PROJECT_ROOT = Path(__file__).resolve().parent.parent
RESULT = re.compile(
    r"Test Case '-\[(TypebarTests\.\w+) (test\w+)\]' (passed|failed|skipped) "
    r"\([0-9]+(?:\.[0-9]+)? seconds\)\.",
    re.MULTILINE,
)
SUMMARY = re.compile(
    r"Test Suite '(?:All tests|Selected tests)' (passed|failed) at [^\n]+\n"
    r"\s*Executed (\d+) tests?, with (?:(\d+) tests? skipped and )?(\d+) failures?",
    re.MULTILINE,
)


def load_manifest(path, project_root=PROJECT_ROOT):
    document = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(document, dict) or document.get("schemaVersion") != 1 or document.get("referenceRevision") != REVISION:
        raise ValueError("unsupported pinned-source QA manifest")
    tests = document.get("tests")
    if not isinstance(tests, list) or not tests:
        raise ValueError("manifest must register required tests")
    required = []
    test_directory = (Path(project_root) / "Tests/TypebarTests").resolve()
    for test in tests:
        identifier = test["id"]
        match = re.fullmatch(r"TypebarTests\.(\w+)/(test\w+)", identifier)
        if not match or identifier in required:
            raise ValueError("invalid or duplicate required test: " + identifier)
        source = (Path(project_root) / test["file"]).resolve()
        if not source.is_relative_to(test_directory) or source.suffix != ".swift":
            raise ValueError("required test must refer to a native client test source")
        text = source.read_text(encoding="utf-8")
        if not re.search(r"\bfunc\s+" + re.escape(match[2]) + r"\s*\(", text):
            raise ValueError("required native test method is missing: " + identifier)
        required.append(identifier)
    return required


def check_evidence(text, required):
    # Captured CI files are normally uncolored. Preserve matching if a caller
    # explicitly enabled ANSI color without accepting arbitrary log prefixes.
    text = re.sub(r"\x1b\[[0-9;]*m", "", text)
    # Do not require a line boundary: real stdout/stderr merging can prefix a
    # complete framework record with an unfinished diagnostic. The status,
    # duration and terminator must still be present in full.
    results = {}
    for owner, method, status in RESULT.findall(text):
        results.setdefault(owner + "/" + method, []).append(status)
    problems = []
    summaries = SUMMARY.findall(text)
    if len(summaries) != 1:
        problems.append("expected one completed top-level XCTest summary")
    else:
        status, count, _skipped, failures = summaries[0]
        if status != "passed" or int(failures) != 0 or int(count) < len(required):
            problems.append("top-level XCTest run did not pass the required scope")
    for identifier in required:
        observed = results.get(identifier, [])
        if observed != ["passed"]:
            problems.append(identifier + ": " + (", ".join(observed) if observed else "missing result"))
    return problems


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    parser.add_argument("--manifest", type=Path,
        default=PROJECT_ROOT / "Compatibility/pinned-source-qa-tests.json")
    arguments = parser.parse_args()
    try:
        required = load_manifest(arguments.manifest)
        problems = check_evidence(arguments.log.read_text(encoding="utf-8"), required)
    except (OSError, ValueError, KeyError, TypeError) as error:
        print("pinned source QA evidence unavailable: " + str(error), file=sys.stderr)
        return 1
    if problems:
        print("pinned source QA evidence failed:", file=sys.stderr)
        for problem in problems:
            print("- " + problem, file=sys.stderr)
        return 1
    print(f"pinned source QA evidence passed ({len(required)} required tests)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
