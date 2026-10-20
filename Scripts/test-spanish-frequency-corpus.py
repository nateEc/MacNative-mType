#!/usr/bin/env python3
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("spanish", Path(__file__).with_name("prepare-spanish-frequency-corpus.py"))
spanish = importlib.util.module_from_spec(spec)
spec.loader.exec_module(spanish)
ROOT = Path(__file__).resolve().parent.parent


class SpanishPreparationTests(unittest.TestCase):
    def test_frequency_order_and_within_band_order_are_preserved(self):
        words, bands, candidates = spanish.select([["de", "la"], ["a", "niño", "árbol"]], 4)
        self.assertEqual(words, ["de", "la", "a", "niño"])
        self.assertEqual(bands, [0, 0, 1, 1])
        self.assertEqual(candidates, 5)

    def test_fragments_foreign_function_words_and_misspellings_are_explicitly_excluded(self):
        for word in ["q", "x", "d", "the", "and", "in", "of", "tambien", "asi", "dia", "aqui", "etc", "pp"]:
            self.assertFalse(spanish.eligible(word), word)
        for word in ["a", "e", "o", "u", "y", "también", "aquí", "ñandú", "pingüino"]:
            self.assertTrue(spanish.eligible(word), word)

    def test_shapes_are_not_repaired_or_silently_normalized(self):
        for word in ["Él", "Niño", "e\u0301", "a1", "dos palabras", "hola-", "hola ", "词", "", "hola\n"]:
            self.assertFalse(spanish.eligible(word), repr(word))

    def test_bad_bands_even_after_enough_words_fail(self):
        for bins in [[['de'], ['la', 'la']], [['de'], ['z', 'a']], [['de'], ['de']], [['de'], [1]], {}]:
            with self.subTest(bins=bins), self.assertRaises(ValueError):
                spanish.select(bins, 1)

    def test_short_corpus_is_never_padded_and_invalid_count_fails(self):
        for bins, count in [([['de']], 2), ([['de']], 0), ([['de']], True)]:
            with self.assertRaises(ValueError):
                spanish.select(bins, count)

    def test_wrong_source_hash_fails_before_msgpack_import(self):
        with tempfile.TemporaryDirectory() as directory:
            wheel = Path(directory) / "not-the-pinned-wheel.whl"
            wheel.write_bytes(b"not the fixed input")
            with self.assertRaisesRegex(ValueError, "wheel SHA"):
                spanish.read_source(wheel)

    def test_publish_refuses_partial_overwrite_and_check_is_read_only(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "existing").write_bytes(b"mine")
            with self.assertRaisesRegex(ValueError, "refusing"):
                spanish.publish({Path("new"): b"new", Path("existing"): b"other"}, root)
            self.assertFalse((root / "new").exists())
            with self.assertRaisesRegex(ValueError, "mismatch"):
                spanish.publish({Path("existing"): b"other"}, root, check=True)
            self.assertEqual((root / "existing").read_bytes(), b"mine")

    def test_real_bundled_artifacts_are_consistent(self):
        spanish.verify_bundled(ROOT)

    def test_corrupted_data_notice_and_provenance_are_detected(self):
        for path in [spanish.SWIFT, spanish.NOTICES, spanish.MANIFEST]:
            with self.subTest(path=path), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                for source in [spanish.SWIFT, spanish.NOTICES, spanish.MANIFEST]:
                    target = root / source
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes((ROOT / source).read_bytes())
                target = root / path
                if path == spanish.MANIFEST:
                    manifest = json.loads(target.read_text())
                    manifest["revision"] = "tampered"
                    target.write_text(json.dumps(manifest))
                else:
                    target.write_bytes(target.read_bytes() + b"tampered\n")
                with self.assertRaises(ValueError):
                    spanish.verify_bundled(root)


if __name__ == "__main__":
    unittest.main()
