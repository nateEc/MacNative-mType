#!/usr/bin/env python3
"""Failure contracts for the CI source-comparison execution requirement."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("source_evidence",
    Path(__file__).with_name("check-source-qa-evidence.py"))
evidence = importlib.util.module_from_spec(spec)
spec.loader.exec_module(evidence)


class SourceEvidenceTests(unittest.TestCase):
    required = ["TypebarTests.OwnedSourceTests/testFirst", "TypebarTests.OwnedSourceTests/testSecond"]

    def record(self, identifier, status="passed"):
        owner, method = identifier.split("/")
        return f"Test Case '-[{owner} {method}]' {status} (0.001 seconds).\n"

    def summary(self, status="passed", count=2, skipped=0, failures=0):
        noun = "test" if count == 1 else "tests"
        skip = f"{skipped} {'test' if skipped == 1 else 'tests'} skipped and " if skipped else ""
        return (f"Test Suite 'Selected tests' {status} at 2026-10-27 00:00:00.000.\n"
            f"\t Executed {count} {noun}, with {skip}{failures} failures (0 unexpected) in 0.1 seconds\n")

    def complete(self):
        return "".join(self.record(test) for test in self.required) + self.summary()

    def testCompletedRequiredTestsAndOptionalSkippedChecksAreAccepted(self):
        optional = self.record("TypebarTests.EnduranceTests/testOptional", "skipped")
        log = "".join(self.record(test) for test in self.required) + optional + self.summary(count=3, skipped=1)
        self.assertEqual(evidence.check_evidence(log, self.required), [])

    def testMissingSkippedFailedAndDuplicateRequiredResultsAreRejected(self):
        for statuses in [[], ["skipped"], ["failed"], ["passed", "passed"], ["failed", "passed"]]:
            with self.subTest(statuses=statuses):
                log = "".join(self.record(self.required[0], status) for status in statuses)
                log += self.record(self.required[1]) + self.summary()
                self.assertTrue(evidence.check_evidence(log, self.required))

    def testAnUnrelatedPassingMethodCannotReplaceRequiredEvidence(self):
        log = self.complete().replace("testFirst", "testUnrelated")
        self.assertTrue(evidence.check_evidence(log, self.required))

    def testTruncatedFailedSmallOrConcatenatedRunsAreRejected(self):
        cases = [self.complete().split("Test Suite")[0],
            self.complete().replace(self.summary(), self.summary("failed", failures=1)),
            self.complete().replace(self.summary(), self.summary(count=1)),
            self.complete() + self.complete()]
        for log in cases:
            with self.subTest(log=log):
                self.assertTrue(evidence.check_evidence(log, self.required))

    def testBothTopLevelNamesAndANSIOutputAreAccepted(self):
        log = self.complete().replace("Selected tests", "All tests")
        self.assertEqual(evidence.check_evidence("\x1b[32m" + log + "\x1b[0m", self.required), [])

    def testCompleteFrameworkRecordsMayFollowInterleavedDiagnosticFragments(self):
        # The actual full-client log has complete XCTest records appended to
        # unfinished Swift/CoreData diagnostics when stdout and stderr merge.
        log = "".join("unfinished diagnostic" + self.record(test) for test in self.required)
        log += "unfinished diagnostic" + self.summary()
        self.assertEqual(evidence.check_evidence(log, self.required), [])

    def testIncompleteStatusRecordCannotPassWithAValidSummary(self):
        log = self.complete().replace("passed (0.001 seconds).", "passed (", 1)
        self.assertTrue(evidence.check_evidence(log, self.required))

    def testOnlySwiftTestingZeroTestSuccessDoesNotProveXCTestExecution(self):
        self.assertTrue(evidence.check_evidence("✔ Test run with 0 tests passed.\n", self.required))

    def testManifestValidatesNativeMethodsAndRejectsDuplicatesOrForeignSources(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            native = root / "Tests/TypebarTests/OwnedSourceTests.swift"
            native.parent.mkdir(parents=True)
            native.write_text("class OwnedSourceTests { func testFirst() {} func testSecond() {} }", encoding="utf-8")
            document = {"schemaVersion": 1, "referenceRevision": evidence.REVISION,
                "tests": [{"id": name, "file": str(native.relative_to(root))} for name in self.required]}
            manifest = root / "manifest.json"
            def load(value):
                manifest.write_text(json.dumps(value), encoding="utf-8")
                return evidence.load_manifest(manifest, project_root=root)
            self.assertEqual(load(document), self.required)
            for bad in [[], dict(document, schemaVersion=2), dict(document, referenceRevision="other"),
                dict(document, tests=[]), dict(document, tests=document["tests"] * 2),
                dict(document, tests=[{"id": self.required[0], "file": "outside.swift"}]),
                dict(document, tests=[{"id": "TypebarTests.OwnedSourceTests/testGone", "file": str(native.relative_to(root))}])]:
                with self.subTest(document=bad), self.assertRaises(ValueError):
                    load(bad)

    def workflow_result(self, source_status="passed", native_status=0, app_running=False):
        # Exercise the actual workflow block, substituting only its native
        # process and process inventory. This never builds or launches an app.
        workflow = (evidence.PROJECT_ROOT / ".github/workflows/native-rewrite-gate.yml").read_text()
        marker = "      - name: Run native client tests without launching the app\n"
        step = workflow.split(marker, 1)[1].split("\n      - name:", 1)[0]
        body = step.split("        run: |\n", 1)[1]
        body = "\n".join(line[10:] if line.startswith("          ") else line for line in body.splitlines())
        registered = evidence.load_manifest(evidence.PROJECT_ROOT / "Compatibility/pinned-source-qa-tests.json")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            shim = root / "bin"; shim.mkdir()
            native = shim / "swift"
            native.write_text('#!/bin/sh\ncat "$SOURCE_QA_TEST_LOG"\nexit "$SOURCE_QA_TEST_NATIVE_STATUS"\n')
            native.chmod(0o700)
            inventory = shim / "pgrep"
            inventory.write_text('#!/bin/sh\nexit "$SOURCE_QA_TEST_PGREP_STATUS"\n')
            inventory.chmod(0o700)
            log = root / "fixture.log"
            skipped = len(registered) if source_status == "skipped" else 0
            log.write_text("".join(self.record(test, source_status) for test in registered)
                + self.summary(count=len(registered), skipped=skipped))
            script = root / "client-step.sh"
            script.write_text(body.replace("${{ steps.reference.outputs.path }}", str(root / "reference")))
            environment = dict(os.environ, PATH=str(shim) + os.pathsep + os.environ["PATH"],
                RUNNER_TEMP=str(root), SOURCE_QA_TEST_LOG=str(log),
                SOURCE_QA_TEST_NATIVE_STATUS=str(native_status),
                SOURCE_QA_TEST_PGREP_STATUS="0" if app_running else "1")
            return subprocess.run(["bash", str(script)], cwd=evidence.PROJECT_ROOT,
                env=environment, capture_output=True, text=True)

    def testWorkflowRejectsSuccessfulNativeExitWithRequiredSourceSkips(self):
        result = self.workflow_result(source_status="skipped")
        self.assertEqual(result.returncode, 1)
        self.assertIn("Missing pinned source QA evidence", result.stdout)

    def testWorkflowAcceptsCompletedRequiredSourceSuccess(self):
        result = self.workflow_result()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("pinned source QA evidence passed", result.stdout)

    def testWorkflowPreservesNativeFailureExit(self):
        result = self.workflow_result(native_status=23)
        self.assertEqual(result.returncode, 23)
        self.assertIn("Native client test failed", result.stdout)
        self.assertNotIn("pinned source QA evidence passed", result.stdout)

    def testWorkflowPreservesRunningAppPostcondition(self):
        result = self.workflow_result(app_running=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn("Native app launch detected", result.stdout)


if __name__ == "__main__":
    unittest.main()
