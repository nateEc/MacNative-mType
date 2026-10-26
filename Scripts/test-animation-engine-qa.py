#!/usr/bin/env python3
"""Exercise artifact acceptance and failed-download cleanup without network."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().with_name("prepare-animation-engine-qa.sh")


class AnimationQA(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.valid = Path(os.environ["TYPEBAR_LINE_SCROLL_ANIME_ARCHIVE"]).resolve()
        if not cls.valid.is_file():
            raise AssertionError("Provide a verified QA archive before running these checks")

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="typebar-animation-preparation-test-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.binary = self.root / "bin"
        self.binary.mkdir()
        curl = self.binary / "curl"
        curl.write_text("""#!/bin/zsh
set -eu
output=""
while (( $# > 0 )); do
  if [[ "$1" == -o ]]; then shift; output="$1"; fi
  shift
done
[[ -n "$output" ]] || exit 70
if [[ "${TYPEBAR_TEST_DOWNLOAD_FAILURE:-0}" == 1 ]]; then
  print -r -- partial > "$output"
  exit 22
fi
cp -- "$TYPEBAR_TEST_DOWNLOAD" "$output"
""")
        curl.chmod(0o755)
        self.env = os.environ.copy()
        self.env.pop("TYPEBAR_LINE_SCROLL_ANIME_ARCHIVE", None)
        self.env.update(TMPDIR=str(self.root), PATH=str(self.binary) + os.pathsep + self.env["PATH"],
                        TYPEBAR_TEST_DOWNLOAD=str(self.valid))

    def run_preparation(self, archive=None, arguments=()):
        env = self.env.copy()
        if archive is not None:
            env["TYPEBAR_LINE_SCROLL_ANIME_ARCHIVE"] = str(archive)
        return subprocess.run(["zsh", str(SCRIPT), *arguments], env=env, text=True, capture_output=True, timeout=30)

    def assert_rejected_without_download_artifacts(self, result):
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertTrue(result.stderr)
        self.assertEqual(list(self.root.glob("typebar-anime-qa.*")), [])

    def test_verified_cached_archive_with_spaces_is_preserved(self):
        archive = self.root / "verified archive.tgz"
        shutil.copyfile(self.valid, archive)
        before = archive.read_bytes(), archive.stat().st_mtime_ns
        result = self.run_preparation(archive)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, str(archive) + "\n")
        self.assertEqual((archive.read_bytes(), archive.stat().st_mtime_ns), before)

    def test_downloaded_verified_archive_is_published(self):
        result = self.run_preparation()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(result.stdout.splitlines()), 1)
        archive = Path(result.stdout.strip())
        self.assertTrue(archive.is_relative_to(self.root))
        self.assertEqual(archive.read_bytes(), self.valid.read_bytes())

    def test_modified_cached_archive_fails_without_removing_the_input(self):
        archive = self.root / "modified.tgz"
        archive.write_bytes(b"not the pinned archive")
        self.assert_rejected_without_download_artifacts(self.run_preparation(archive))
        self.assertEqual(archive.read_bytes(), b"not the pinned archive")

    def test_missing_explicit_cache_is_not_silently_replaced(self):
        self.assert_rejected_without_download_artifacts(self.run_preparation(self.root / "missing.tgz"))

    def test_modified_download_is_not_published_and_is_cleaned(self):
        invalid = self.root / "invalid-download.tgz"
        invalid.write_bytes(b"not the pinned download")
        self.env["TYPEBAR_TEST_DOWNLOAD"] = str(invalid)
        self.assert_rejected_without_download_artifacts(self.run_preparation())
        self.assertTrue(invalid.exists())

    def test_partial_download_failure_is_not_published_and_is_cleaned(self):
        self.env["TYPEBAR_TEST_DOWNLOAD_FAILURE"] = "1"
        result = self.run_preparation()
        self.assertEqual(result.returncode, 22)
        self.assert_rejected_without_download_artifacts(result)

    def test_multiline_path_cannot_escape_an_environment_file_value(self):
        archive = self.root / "archive\nother=value.tgz"
        shutil.copyfile(self.valid, archive)
        self.assert_rejected_without_download_artifacts(self.run_preparation(archive))
        self.assertTrue(archive.exists())

    def test_unexpected_arguments_do_not_start_a_download(self):
        self.assert_rejected_without_download_artifacts(self.run_preparation(arguments=("unexpected",)))


if __name__ == "__main__":
    unittest.main()
