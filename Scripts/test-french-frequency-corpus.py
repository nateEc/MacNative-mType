#!/usr/bin/env python3
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("french", Path(__file__).with_name("prepare-french-frequency-corpus.py"))
french = importlib.util.module_from_spec(spec)
spec.loader.exec_module(french)
ROOT = Path(__file__).resolve().parent.parent


class FrenchPreparationTests(unittest.TestCase):
    def test_frequency_order_precedes_alphabetical_order_across_bins(self):
        words, bands, count = french.select([["la", "le"], ["a", "être"]], 3)
        self.assertEqual(words, ["la", "le", "a"])
        self.assertEqual(bands, [0, 0, 1]); self.assertEqual(count, 4)

    def test_filter_preserves_accents_and_rejects_fragments_and_foreign_functions(self):
        for word in ["à", "a", "y", "ô", "être", "cœur", "français", "on"]:
            self.assertTrue(french.eligible(word), word)
        for word in ["qu", "l", "d", "j", "the", "and", "www", "hui", "être1", "e\u0302tre", "Paris", "a" * 21, ""]:
            self.assertFalse(french.eligible(word), word)

    def test_invalid_or_insufficient_bins_are_rejected_without_padding(self):
        for bins in [[['le', 'la']], [['la', 'la']], [['la'], ['la']], [[1]], {}]:
            with self.assertRaises(ValueError): french.select(bins, 1)
        with self.assertRaises(ValueError): french.select([["la"]], 2)
        for count in [0, -1, True, 1.5]:
            with self.assertRaises(ValueError): french.select([["la"]], count)

    def test_editorial_case_and_expressions_do_not_mutate_observed_tokens(self):
        raw = ["de", "france", "paris"]
        self.assertEqual(french.curate(raw), ["de", "France", "Paris"])
        self.assertEqual(raw, ["de", "france", "paris"])
        words = french.scale_words(raw, 9)
        self.assertEqual(words[:3], french.curate(raw))
        self.assertEqual(words[3:], french.ADDITIONS)

    def test_wrong_source_hash_fails_before_reading_or_importing_dependencies(self):
        with tempfile.TemporaryDirectory() as directory:
            wheel = Path(directory)/"bad.whl"; wheel.write_bytes(b"invalid")
            with self.assertRaisesRegex(ValueError, "SHA-256"):
                french.read_source(wheel)

    def test_bundled_generated_files_are_internally_consistent(self):
        french.verify_bundled(ROOT)

    def test_tampered_case_expressions_metadata_and_attribution_are_rejected(self):
        changes = [(french.SWIFT, "France", "france"),
                   (french.SWIFT, "tout à fait", "toutàfait"),
                   (french.MANIFEST, '"count": 1394', '"count": 1393'),
                   (french.NOTICES, "## License", "## Removed")]
        for path, old, new in changes:
            with tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                for name in [french.SWIFT, french.MANIFEST, french.NOTICES]:
                    target = root/name; target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes((ROOT/name).read_bytes())
                text = (root/path).read_text(); self.assertIn(old, text)
                (root/path).write_text(text.replace(old, new))
                with self.assertRaises(ValueError): french.verify_bundled(root)

    def test_publishing_refuses_to_overwrite_any_existing_artifact(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); (root/"existing").write_bytes(b"old")
            with self.assertRaises(ValueError):
                french.publish({Path("new"): b"new", Path("existing"): b"changed"}, root)
            self.assertFalse((root/"new").exists()); self.assertEqual((root/"existing").read_bytes(), b"old")

    def test_scale_manifest_and_shared_observed_data_match_each_actual_pool(self):
        m = json.loads((ROOT/french.MANIFEST).read_text())
        self.assertEqual(m['observedCount'], 10245)
        self.assertEqual(m['unrankedEditorialAdditions'], french.ADDITIONS)
        for name, count in french.COUNTS.items():
            self.assertEqual(m['scales'][name]['count'], count)
            self.assertEqual(m['scales'][name]['uniqueCount'], count)
            self.assertEqual(m['scales'][name]['multiwordCount'], 5)


if __name__ == "__main__":
    unittest.main()
