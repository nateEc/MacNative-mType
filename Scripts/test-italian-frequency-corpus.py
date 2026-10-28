#!/usr/bin/env python3
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("italian", Path(__file__).with_name("prepare-italian-frequency-corpus.py"))
italian = importlib.util.module_from_spec(spec)
spec.loader.exec_module(italian)
ROOT = Path(__file__).resolve().parent.parent


class ItalianPreparationTests(unittest.TestCase):
    def test_frequency_bands_precede_alphabetical_order(self):
        words, bands, count = italian.select([["di", "e"], ["a", "perché"]], 3)
        self.assertEqual(words, ["di", "e", "a"])
        self.assertEqual(bands, [0, 0, 1]); self.assertEqual(count, 4)

    def test_filter_keeps_italian_accents_but_rejects_fragments_and_foreign_functions(self):
        for word in ["a", "e", "i", "o", "è", "perché", "città", "più", "sì", "famiglia", "a" * 25]:
            self.assertTrue(italian.eligible(word), word)
        for word in ["b", "u", "the", "and", "www", "http", "it", "Italia", "e\u0300", "ciao2", "a" * 26, ""]:
            self.assertFalse(italian.eligible(word), word)

    def test_invalid_bins_and_shortages_never_generate_padding(self):
        for bins in [[['e', 'di']], [['di', 'di']], [['di'], ['di']], [[1]], {}]:
            with self.assertRaises(ValueError): italian.select(bins, 1)
        with self.assertRaises(ValueError): italian.select([["di"]], 2)
        for count in [0, -1, True, 1.5]:
            with self.assertRaises(ValueError): italian.select([["di"]], count)

    def test_case_edits_and_scale_bound_leave_original_tokens_unchanged(self):
        raw = ["italia", "roma", "a" * 15, "grazie"]
        self.assertEqual(italian.curate(raw), ["Italia", "Roma", "a" * 15, "grazie"])
        self.assertEqual(italian.scale_words(raw, 1159), ["Italia", "Roma", "grazie"])
        self.assertEqual(raw, ["italia", "roma", "a" * 15, "grazie"])
        self.assertEqual(italian.ADDITIONS, [])

    def test_wrong_wheel_hash_is_rejected_before_dependency_import(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/"bad.whl"; path.write_bytes(b"invalid")
            with self.assertRaisesRegex(ValueError, "SHA-256"):
                italian.read_source(path)

    def test_bundled_data_and_notices_reproduce_their_internal_manifest(self):
        italian.verify_bundled(ROOT)

    def test_publish_refuses_every_existing_destination_before_writing(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); (root/"existing").write_bytes(b"old")
            with self.assertRaises(ValueError):
                italian.publish({Path("new"): b"new", Path("existing"): b"changed"}, root)
            self.assertFalse((root/"new").exists()); self.assertEqual((root/"existing").read_bytes(), b"old")

    def test_manifest_records_real_counts_bounds_and_no_padding(self):
        m = json.loads((ROOT/italian.MANIFEST).read_text())
        self.assertEqual(m["observedCount"], 279833)
        self.assertEqual(m["schemaVersion"], 2)
        self.assertEqual(m["unrankedEditorialAdditions"], [])
        self.assertEqual(m["technicalEditorialNames60k"], ["C++", "C#"])
        for name, count in italian.COUNTS.items():
            self.assertEqual(m["scales"][name]["count"], count)
            self.assertEqual(m["scales"][name]["uniqueCount"], count)
            self.assertEqual(m["scales"][name]["multiwordCount"], 0)
            self.assertLessEqual(m["scales"][name]["maximumLength"], italian.LIMITS[name])

    def test_band_runs_preserve_ranks_and_reject_corrupt_or_excessive_sizes(self):
        bands = italian.expand_band_runs([[1, 10], [5, italian.OBSERVED_COUNT - 10]])
        self.assertEqual(bands[:10], [1] * 10); self.assertEqual(bands[10:], [5] * (italian.OBSERVED_COUNT - 10))
        for runs in [None, [], [[-1, italian.OBSERVED_COUNT]], [[1, 1]], [[1, 0]],
                     [[1, True]], [[1, italian.OBSERVED_COUNT + 1]], [[1, 1], [1, italian.OBSERVED_COUNT - 1]],
                     [[3, 1], [2, italian.OBSERVED_COUNT - 1]], [[1]], [[1, 2, 3]], [[False, italian.OBSERVED_COUNT]]]:
            with self.assertRaises(ValueError): italian.expand_band_runs(runs)

    def test_each_scale_filters_before_taking_the_count(self):
        raw = ["a" * 15, "a" * 19, "a" * 25, "di", "perché"]
        self.assertEqual(italian.scale_words(raw, 1159), ["di", "perché"])
        self.assertEqual(italian.scale_words(raw, 7154), ["a" * 15, "di", "perché"])
        self.assertEqual(italian.scale_words(raw, 60442), ["a" * 15, "di", "perché"])
        self.assertEqual(italian.scale_words(raw, 279833), raw)

    def test_punctuated_observations_have_a_distinct_frequency_cutoff(self):
        bins = [[] for _ in range(452)]
        bins[450] = sorted(["com'è", "all'interno", "l'", "ciao--mondo", "C++", "com'e\u0300"])
        bins[451] = ["dell'anno"]
        rows = italian.punctuated_observations(bins)
        self.assertEqual(rows, [["all'interno", 450], ["com'è", 450]])
        self.assertEqual(italian.scale_words(["di", "e"], 60442, rows),
                         ["di", "e", "all'interno", "com'è", "C++", "C#"])


if __name__ == "__main__":
    unittest.main()
