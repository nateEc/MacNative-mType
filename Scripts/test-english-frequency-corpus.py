#!/usr/bin/env python3
"""Deterministic preparation contracts; no downloads or full upstream build."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("prepare", Path(__file__).with_name("prepare-english-frequency-corpus.py"))
prepare = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepare)


class EnglishFrequencyPreparationTests(unittest.TestCase):
    def test_dictionary_membership_and_frequency_order_not_dictionary_order(self):
        words, bands, count = prepare.select_words(
            ["zebra", "bird", "apple", "apple", "notranked"],
            [["zebra"], ["absent", "apple"], ["bird"]], 3)
        self.assertEqual(words, ["zebra", "apple", "bird"])
        self.assertEqual(bands, [0, 1, 2])
        self.assertEqual(count, 3)

    def test_natural_case_is_preserved_without_creating_dictionary_forms(self):
        words, _, _ = prepare.select_words(
            ["APPLE", "Apple", "apple", "France", "I", "i"], [["apple", "france", "i"]], 3)
        self.assertEqual(words, ["apple", "France", "I"])

    def test_digits_symbols_and_accents_are_not_silently_folded_into_words(self):
        words, _, _ = prepare.select_words(
            ["a1", "a-b", "a b", "café", "plain"], [["a b", "a-b", "a1", "café", "plain"]], 1)
        self.assertEqual(words, ["plain"])

    def test_short_candidates_are_rejected_without_synthetic_padding(self):
        with self.assertRaisesRegex(ValueError, "insufficient real dictionary words"):
            prepare.select_words(["a"], [["a", "unknown"]], 2)

    def test_wrong_wheel_is_rejected_before_importing_or_executing_any_package(self):
        with tempfile.TemporaryDirectory() as directory:
            wheel = Path(directory) / "wordfreq-3.1.1-py3-none-any.whl"
            wheel.write_bytes(b"not the pinned wheel")
            with self.assertRaisesRegex(ValueError, "SHA-256 mismatch"):
                prepare.read_frequency(wheel)

    def test_invalid_frequency_data_is_rejected_even_beyond_requested_prefix(self):
        for bins in ([["b", "a"]], [["a", "a"]], [["a"], ["a"]], [["a"], [123]], [["a"], "bad"]):
            with self.subTest(bins=bins), self.assertRaises(ValueError):
                prepare.select_words(["a"], bins, 1)

    def test_candidate_selection_does_not_depend_on_dictionary_iteration_order(self):
        data = ["ZEBRA", "Zebra", "zebra", "Apple", "APPLE"]
        self.assertEqual(prepare.select_words(data, [["apple", "zebra"]], 2),
                         prepare.select_words(list(reversed(data)), [["apple", "zebra"]], 2))

    def test_check_mode_detects_tampering_and_never_overwrites(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            outputs = {Path("data/words.txt"): b"apple\n"}
            prepare.publish(outputs, root, False)
            prepare.publish(outputs, root, True)
            with self.assertRaisesRegex(ValueError, "refusing to replace"):
                prepare.publish(outputs, root, False)
            with self.assertRaisesRegex(ValueError, "mismatch"):
                prepare.publish({Path("data/words.txt"): b"tampered\n"}, root, True)
            self.assertEqual((root / "data/words.txt").read_bytes(), b"apple\n")

    def test_bundled_integrity_detects_changed_data_and_notices(self):
        # Synthetic fixture tests integrity mechanics, not dictionary validity.
        words = ["word" + chr(97 + n // 17576) + chr(97 + n // 676 % 26)
                 + chr(97 + n // 26 % 26) + chr(97 + n % 26)
                 for n in range(prepare.WORD_COUNT)]
        outputs = prepare.artifacts(words, list(range(len(words))), len(words), b"packed", "SCOWL", "credits")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            prepare.publish(outputs, root, False)
            prepare.verify_bundled(root)
            notice = root / prepare.NOTICES_PATH
            notice.write_bytes(notice.read_bytes() + b"changed")
            with self.assertRaisesRegex(ValueError, "hash mismatch"):
                prepare.verify_bundled(root)
            notice.write_bytes(outputs[prepare.NOTICES_PATH])
            source = root / prepare.SWIFT_PATH
            source.write_bytes(source.read_bytes().replace(b"wordaaa", b"changed", 1))
            with self.assertRaisesRegex(ValueError, "hash mismatch"):
                prepare.verify_bundled(root)

    def test_existing_small_corpus_words_remain_byte_identical(self):
        # Pin the previous 1k/5k/10k data, not the enlarged container's bytes.
        source = (Path(__file__).resolve().parent.parent / prepare.SWIFT_PATH).read_bytes()
        body = source.split(b'  static let words: [String] = """\n', 1)[1].split(b'""".split', 1)[0]
        old_prefix = b"\n".join(body.splitlines()[:9944]) + b"\n"
        self.assertEqual(prepare.digest(old_prefix),
                         "0a28013ab4dba0ad9bf0394810e217b87e8dd37c95b18eff9a77effcad1c2e96")

    def test_every_choice_records_its_own_exact_data_digest(self):
        words = ["a" + str(n) for n in range(prepare.WORD_COUNT)]
        # Artifact construction uses synthetic fixtures; source selection and
        # bundled validation separately reject these numeric test tokens.
        outputs = prepare.artifacts(words, list(range(len(words))), len(words), b"packed", "SCOWL", "credits")
        provenance = json.loads(outputs[prepare.PROVENANCE_PATH])
        self.assertEqual(set(provenance["choices"]), {"1000", "5000", "9944", "24141"})
        for count in prepare.CHOICE_COUNTS:
            self.assertEqual(provenance["choices"][str(count)]["wordsSHA256"],
                             prepare.digest(("\n".join(words[:count]) + "\n").encode()))


if __name__ == "__main__":
    unittest.main()
