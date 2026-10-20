#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("western", Path(__file__).with_name("check-western-basic-corpora.py"))
western = importlib.util.module_from_spec(spec)
spec.loader.exec_module(western)


class WesternBasicCorpusAuditTests(unittest.TestCase):
    def test_statistical_lookup_uses_casefold_without_rewriting_practice_words(self):
        self.assertEqual(western.frequency_key("Straße"), "strasse")
        self.assertEqual(western.frequency_key("Größe"), "grösse")
        self.assertEqual(western.frequency_key("ÉCOUTE"), "écoute")
        self.assertEqual(western.frequency_key("e\u0301"), "é")

    def test_accents_and_german_case_are_retained(self):
        report = western.audit_words(["Brücke", "Straße", "Mühe"], 3, 0, 10)
        self.assertEqual(report["uppercaseCount"], 3)
        self.assertEqual(report["count"], 3)

    def test_real_multiword_candidates_are_counted_as_candidates_not_tokens(self):
        report = western.audit_words(["ici", "tout à fait", "peu à peu"], 3, 2, 12)
        self.assertEqual(report["multiwordCount"], 2)
        self.assertEqual(report["count"], 3)

    def test_duplicate_case_and_underfilled_lists_fail(self):
        for words in (["Haus", "haus"], ["Haus"]):
            with self.assertRaisesRegex(ValueError, "count or uniqueness"):
                western.audit_words(words, 2, 0, 10)

    def test_invalid_shapes_and_decomposed_accents_fail(self):
        for word in [" mot", "mot ", "deux  mots", "a1", "mot\t", "m\not", "e\u0301", "word-", "词"]:
            with self.subTest(word=word), self.assertRaises(ValueError):
                western.audit_words([word], 1, int(" " in word), 20)

    def test_wrong_phrase_count_and_length_fail(self):
        with self.assertRaisesRegex(ValueError, "multiword"):
            western.audit_words(["zu Hause"], 1, 0, 10)
        with self.assertRaisesRegex(ValueError, "invalid"):
            western.audit_words(["bonjour"], 1, 0, 3)


if __name__ == "__main__":
    unittest.main()
