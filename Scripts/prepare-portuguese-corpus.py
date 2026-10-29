#!/usr/bin/env python3
"""Prepare independent Portuguese dictionaries / observations and two unit examples.
Source preparation requires Unicode 15.0.0 and msgpack 1.1.2. No downloads or
reference words. Runtime has no Python, msgpack or network dictionary dependency.
"""
import argparse
from collections import Counter
import gzip
import hashlib
import json
from pathlib import Path
import re
import sys
import unicodedata
import unittest
import zipfile

SOURCE_URL = "https://kaikki.org/dictionary/downloads/pt/pt-extract.jsonl.gz"
SOURCE_SHA = "9a244407ef90051e8c3292bd896a830f69429872059dc52da2a6eaecfd771faa"
WHEEL_SHA = "4b1c6ecffc6198be3396d5cf871c4423ca71c907c231348d352dd54d62b97473"
MEMBER = "wordfreq/data/large_pt.msgpack.gz"
MEMBER_SHA = "7d764586bca6262f554d5fa77ad8e6841ef42534776e70558065140853660ce2"
REVISION = "kaikki-pt-20261029-wordfreq-3.1.1-v1"
COUNTS = {"1k": 1000, "3k": 3043, "5k": 5665, "320k": 318601, "550k": 558207}
LETTER_LIMITS = dict(zip(COUNTS, [16, 17, 18, 33, 33]))
PUNCTUATION_LIMITS = dict(zip(COUNTS, [13, 14, 15, 41, 41]))
PUNCTUATION_TARGETS = dict(zip(COUNTS, [3, 16, 15, 50480, 50480]))
PHRASES = dict(zip(COUNTS, [0, 0, 36, 119, 119]))
TRAILING_PREFIXES = ["anti-", "pré-"]
UNIT_EXAMPLES = ["m²", "m³"]
TECHNICAL_OBSERVATION = "2d"
SI_SOURCE = "https://doi.org/10.59161/AUEZ1291"
PARTS = frozenset("noun name verb adj adv article pron det conj intj prep postp num particle phrase abbrev prefix suffix affix infix participle contraction onomatopoeia interfix prep_phrase adv_phrase adj_phrase".split())
SWIFT = Path("Sources/Typebar/PortugueseCorpus.generated.swift")
MANIFEST = Path("Compatibility/portuguese-corpus.json")
NOTICES = Path("Resources/PortugueseCorpusNotices.txt")
SOURCES = Path("Resources/PortugueseCorpusSources.txt")
ATTRIBUTION_PINS = {
    str(NOTICES): "ba2571fcaf2a8f27a37b179a1c67b63a82c7bf92f384f823ffbc0f8b52dee5ee",
    str(SOURCES): "3c2a24ef184070fc0e6035f9c8c048ceaaecf23e3a744042890a4c2f91e3227b",
}

def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def file_digest(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def letters(word):
    return bool(word) and all(c.isalpha() and unicodedata.name(c, "").startswith("LATIN ") for c in word)


def literal(word):
    return type(word) is str and 1 <= len(word) <= 60 and word == unicodedata.normalize("NFC", word)


def collect_entry(item, pools):
    require(type(item) is dict, "dictionary entry must be an object")
    if item.get("lang_code") != "pt" or item.get("pos") not in PARTS:
        return
    lemma = item.get("word")
    require(type(lemma) is str and lemma and not any(c in lemma for c in "\t\r\n"), "invalid source title")
    forms = item.get("forms", [])
    require(type(forms) is list, "forms must be an array")
    for form in [{"form": lemma, "tags": []}] + forms:
        require(type(form) is dict and type(form.get("form")) is str, "invalid dictionary form")
        tags = form.get("tags", [])
        require(type(tags) is list and all(type(t) is str for t in tags), "invalid form tags")
        if any(t in {"table-tags", "inflection-template", "romanization", "class"} or t.startswith("error-") for t in tags):
            continue
        word = form["form"]
        if not literal(word):
            continue
        kind = None
        if letters(word):
            kind = "letters" if word == word.lower() else "cased"
        elif word == word.lower():
            if word == lemma and " " in word and all(letters(p) for p in word.split(" ")):
                kind = "phrases"
            elif "-" in word and all(letters(p) for p in word.split("-")):
                kind = "hyphen"
            elif word == lemma and word in TRAILING_PREFIXES:
                kind = "hyphen"
            elif word == lemma and "." in word and all(letters(p) for p in word.rstrip(".").split(".")):
                kind = "period"
            elif any(c in word for c in "'’") and all(letters(p) for p in re.split("['’]", word)):
                kind = "apostrophe"
        if kind:
            previous = pools[kind].get(word)
            if previous is None or (len(lemma), lemma) < (len(previous), previous):
                pools[kind][word] = lemma


def read_dictionary(path):
    require(unicodedata.unidata_version == "15.0.0", "source preparation requires Unicode 15.0.0")
    require(file_digest(path) == SOURCE_SHA, "Portuguese dictionary snapshot SHA-256 mismatch")
    pools = {k: {} for k in ["letters", "cased", "phrases", "hyphen", "period", "apostrophe"]}
    with gzip.open(path, "rt", encoding="utf-8") as source:
        for line in source:
            collect_entry(json.loads(line), pools)
    return pools


def frequency_bands(bins):
    require(type(bins) is list, "frequency bins must be an array")
    result = {}
    for band, words in enumerate(bins):
        require(type(words) is list and all(type(w) is str for w in words), "frequency bins must contain strings")
        require(words == sorted(set(words)), "frequency bins must be sorted and unique")
        for word in words:
            require(word not in result, "frequency token occurs in multiple bins")
            result[word] = band
    return result


def read_frequency(path):
    require(file_digest(path) == WHEEL_SHA, "wordfreq wheel SHA-256 mismatch")
    import msgpack
    require(msgpack.__version__ == "1.1.2", "source preparation requires msgpack==1.1.2")
    with zipfile.ZipFile(path) as archive:
        packed = archive.read(MEMBER)
        metadata = archive.read("wordfreq-3.1.1.dist-info/METADATA").decode()
    require(digest(packed) == MEMBER_SHA, "Portuguese frequency member SHA-256 mismatch")
    data = msgpack.unpackb(gzip.decompress(packed), raw=False)
    require(type(data) is list and data and data[0] == {"format": "cB", "version": 1}, "unsupported frequency format")
    require("## License" in metadata, "wordfreq release notices missing")
    return frequency_bands(data[1:]), metadata[metadata.index("## License"):].strip() + "\n"


def priority(word, bands):
    band = bands.get(word.casefold())
    if band is None:
        band = max((bands.get(p.casefold(), 10**9) for p in re.split("[ .’'-]", word) if p), default=10**9)
    return band, word


def observed_letter(word):
    # Do not reserve repeated laughter / keyboard filler as long-word practice.
    return (literal(word) and word == word.lower() and letters(word)
            and re.fullmatch(r"(.{1,3})\1{2,}", word) is None)


def ranked(pool, bands, minimum, maximum):
    return sorted((w for w in pool if minimum <= len(w) <= maximum), key=lambda w: priority(w, bands))


def take(values, needed, label):
    require(type(needed) is int and needed >= 0 and len(values) >= needed,
            "insufficient attested " + label + "; never pad")
    return values[:needed]


def retain_longest(chosen, available):
    require(bool(chosen) and bool(available), "long-word section is empty")
    # Available candidates are already ranked; a stable tie keeps the most
    # frequent attested spelling instead of an arbitrary alphabetic long form.
    longest = max(available, key=len)
    if len(longest) > max(map(len, chosen)):
        chosen[-1] = longest


def choose_letters(dictionary, observations, needed):
    chosen = take(dictionary, min(needed, len(dictionary)), "dictionary letter forms")
    if len(chosen) < needed:
        chosen += take(observations, needed - len(chosen), "observed letter forms")
    return chosen


def select(pools, bands, scale):
    require(scale in COUNTS, "unsupported scale")
    large = scale in ["320k", "550k"]
    minimum = 2 if large else 1
    lower = dict(pools["letters"])
    observed_additions = set()
    if large:
        for word in bands:
            if word not in lower and observed_letter(word):
                lower[word] = None
                observed_additions.add(word)
    available = ranked(lower, bands, minimum, LETTER_LIMITS[scale])
    punctuation = dict(pools["hyphen"])
    if large:
        punctuation.update(pools["period"])
        punctuation.update(pools["apostrophe"])
        require(all(w in punctuation for w in TRAILING_PREFIXES), "literal open prefixes missing")
    else:
        punctuation = {w: v for w, v in punctuation.items() if w.count("-") == 1 and not w.endswith("-")}
    punctuated = ranked(punctuation, bands, minimum, PUNCTUATION_LIMITS[scale])
    chosen_punctuation = take(punctuated, min(PUNCTUATION_TARGETS[scale], len(punctuated)), "punctuation")
    retain_longest(chosen_punctuation, punctuated)
    chosen_phrases = []
    if PHRASES[scale]:
        limit, fields, field_limit = (23, 5, 9) if large else (19, 3, 11)
        phrases = {w: owner for w, owner in pools["phrases"].items()
                   if len(w.split(" ")) <= fields and max(map(len, w.split(" "))) <= field_limit}
        available_phrases = ranked(phrases, bands, minimum, limit)
        chosen_phrases = take(available_phrases, PHRASES[scale], "multiword headwords")
        retain_longest(chosen_phrases, available_phrases)
        if max(len(w.split(" ")) for w in chosen_phrases) < fields:
            candidate = next((w for w in available_phrases if len(w.split(" ")) == fields), None)
            require(candidate is not None, "literal phrase field boundary missing")
            # Keep the independently reserved longest phrase as well.
            slot = next(i for i, w in enumerate(chosen_phrases) if len(w) < max(map(len, chosen_phrases)))
            chosen_phrases[slot] = candidate
    names = ["Portugal"] if scale == "5k" else []
    require(all(w in pools["cased"] for w in names), "literal proper name missing")
    technical = UNIT_EXAMPLES if large else ([TECHNICAL_OBSERVATION] if scale == "5k" else [])
    if scale == "5k":
        require(TECHNICAL_OBSERVATION in bands, "technical observation missing")
    needed = COUNTS[scale] - len(chosen_punctuation) - len(chosen_phrases) - len(names) - len(technical)
    dictionary_available = ranked(pools["letters"], bands, minimum, LETTER_LIMITS[scale])
    observations = [w for w in available if w in observed_additions]
    chosen_lower = choose_letters(dictionary_available, observations, needed)
    retain_longest(chosen_lower, dictionary_available)
    words = chosen_lower + chosen_punctuation + chosen_phrases + names + technical
    require(len(words) == len(set(words)) == COUNTS[scale], "selection must be exact and unique")
    evidence = {}
    for word in words:
        if word in UNIT_EXAMPLES:
            row = ["authoredSIUnit", "Typebar", SI_SOURCE]
        elif word == TECHNICAL_OBSERVATION or word in observed_additions:
            row = ["frequencyObservation", "wordfreq", MEMBER]
        else:
            owners = [pool[word] for pool in pools.values() if word in pool]
            require(bool(owners), "dictionary owner missing")
            row = ["dictionaryLiteral", "pt", min(owners, key=lambda t: (len(t), t))]
        evidence[word] = row + [str(bands.get(word.casefold(), "-"))]
    return sorted(words, key=lambda w: priority(w, bands)), evidence


def native_source(scales):
    text = ("// Generated by Scripts/prepare-portuguese-corpus.py; do not edit.\n"
            "// Independent dictionary / observed forms; two declared SI writing examples.\n"
            "// CC BY-SA 4.0 adapted selection; full notices / evidence map accompany the app.\n"
            "enum PortugueseCorpus {\n" + f'  static let revision = "{REVISION}"\n')
    for scale, words in scales.items():
        text += f'  static let words{scale}: [String] = """\n' + "\n".join(words) + '\n""".split(separator: "\\n").map(String.init)\n'
    return (text + "}\n").encode()


def shape(words):
    return {"count": len(words), "uniqueCount": len(set(words)), "minimumLength": min(map(len, words)),
            "maximumLength": max(map(len, words)), "uppercaseCount": sum(any(c.isupper() for c in w) for w in words),
            "punctuationCount": sum(any(unicodedata.category(c).startswith("P") for c in w) for w in words),
            "nonLetterCount": sum(not w.isalpha() for w in words), "spaceCount": sum(" " in w for w in words),
            "digitCount": sum(any(c.isnumeric() for c in w) for w in words),
            "controlCount": sum(any(unicodedata.category(c).startswith("C") for c in w) for w in words),
            "nonASCIICount": sum(not w.isascii() for w in words),
            "maximumLetterLength": max((len(w) for w in words if letters(w)), default=0),
            "maximumPunctuationLength": max((len(w) for w in words if any(unicodedata.category(c).startswith("P") for c in w)), default=0),
            "maximumPhraseFields": max((len(w.split(" ")) for w in words if " " in w), default=0),
            "maximumHyphens": max(w.count("-") for w in words)}


def check_attribution_pins(hashes):
    require(set(ATTRIBUTION_PINS) == {str(NOTICES), str(SOURCES)}
            and all(hashes.get(n) == sha for n, sha in ATTRIBUTION_PINS.items()),
            "published attribution pin mismatch; mutable manifest hashes are insufficient")


def artifacts(pools, bands, release_notices):
    scales, evidence = {}, {}
    for k in COUNTS:
        words, rows = select(pools, bands, k)
        scales[k] = words
        for word, row in rows.items():
            require(word not in evidence or evidence[word] == row, "cross-scale evidence conflict")
            evidence[word] = row
    sources = ("# Practice spelling\tEvidence kind\tProvider / edition\tEntry title / observation member / notation authority\tWhole-form frequency band or -\n"
               "# pt page: https://pt.wiktionary.org/wiki/<URL-encoded title>\n"
               "# pt contributors: https://pt.wiktionary.org/w/index.php?title=<URL-encoded title>&action=history\n"
               "# Observation bands are not dictionary attestations; unit examples are authored, unranked notation.\n"
               + "".join(w + "\t" + "\t".join(evidence[w]) + "\n" for w in sorted(evidence))).encode()
    notices = ("Typebar independent Portuguese corpus — revision 1\n"
               "Portuguese-language Wikcionário contributors, extracted by Kaikki.org /\n"
               "Wiktextract; independent Portuguese observations from wordfreq 3.1.1.\n"
               "Selection and two SI writing examples adapted by Typebar contributors (2026),\n"
               "CC BY-SA 4.0. https://creativecommons.org/licenses/by-sa/4.0/\n"
               "https://pt.wiktionary.org/wiki/Wikcionário:Direitos_autorais\n\n"
               "Raw dictionary snapshot retrieved 2026-10-29:\n" + SOURCE_URL + "\nSHA-256: " + SOURCE_SHA + "\n"
               "https://kaikki.org/dictionary/rawdata.html\n\n"
               "Changes: literal NFC Latin-letter forms, real hyphenated inflections,\n"
               "headword phrases, period abbreviations and apostrophe forms; lang_code=pt.\n"
               "Exclude template / romanization / error tags, spaces in ordinary words and\n"
               "control characters. Literal Portugal keeps the 5k name practice. Reserve\n"
               "actual longest eligible words, punctuation and phrase field boundaries.\n"
               "Prefer dictionary letter forms; only supplement a capacity gap with literal\n"
               "wordfreq observations, excluding short repeated-pattern filler. Unreviewed\n"
               "observations never displace otherwise available dictionary letter forms.\n"
               "2d is an observed technical token; m² and m³ are explicitly authored unit\n"
               "writing examples, not dictionary spellings or measured usage frequencies.\n"
               "Their notation follows BIPM SI Brochure 9th edition, 2026: " + SI_SOURCE + "\n"
               "No BIPM artwork, tables or prose are bundled. No broken C1 control bytes\n"
               "are retained, and no dollar symbol is invented to imitate their statistics.\n"
               "PortugueseCorpusSources.txt records dictionary entry titles / contributor\n"
               "history templates, observation members / bands and unit evidence separately.\n"
               "No definitions, examples, audio, images or raw JSONL are bundled.\n"
               "Rank with case-folded observations; missing whole-form ranks use the rarest\n"
               "space / punctuation-delimited component as an estimate, unknown last.\n"
               "Not a pure frequency cutoff, dialect split or quality/difficulty/distribution\n"
               "parity claim. Punctuation coverage remains below the reference; no padding.\n"
               "Data may contain extraction errors, names, loans, archaic or offensive forms.\n"
               "Basic Portuguese / accents practice and captured old results are unchanged.\n\n"
               "Tatu Ylonen, Wiktextract: Wiktionary as Machine-Readable Structured Data,\n"
               "LREC 2022, pp. 1317–1325. https://aclanthology.org/2022.lrec-1.140/\n\n"
               "=== wordfreq 3.1.1 release metadata ===\n" + release_notices).encode()
    generated = {SWIFT: native_source(scales), NOTICES: notices, SOURCES: sources}
    manifest = {"schemaVersion": 1, "revision": REVISION,
                "dictionary": {"url": SOURCE_URL, "sha256": SOURCE_SHA, "languageCode": "pt", "edition": "pt", "retrievedDate": "2026-10-29"},
                "wordfreq": {"version": "3.1.1", "wheelSHA256": WHEEL_SHA, "member": MEMBER, "memberSHA256": MEMBER_SHA},
                "preparation": {"unicodeVersion": "15.0.0", "msgpackVersion": "1.1.2", "runtimeDependencies": []},
                "available": {k: len(v) for k, v in pools.items()},
                "unitExamples": UNIT_EXAMPLES, "technicalObservation": TECHNICAL_OBSERVATION, "notationAuthority": SI_SOURCE,
                "scales": {k: {"shape": shape(w), "wordsSHA256": digest(("\n".join(w) + "\n").encode()),
                               "evidenceCounts": dict(Counter(evidence[word][0] for word in w))} for k, w in scales.items()},
                "sourceMapCount": len(evidence), "filesSHA256": {str(k): digest(v) for k, v in generated.items()},
                "dataLicense": "CC-BY-SA-4.0 adapted selection; retain full notices and evidence map",
                "limits": "Original punctuation coverage, max-hyphen count and distribution remain open; no controls or synthetic filler."}
    generated[MANIFEST] = (json.dumps(manifest, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode()
    return generated


def publish(outputs, root, check):
    check_attribution_pins({str(k): digest(v) for k, v in outputs.items()})
    if check:
        for name, data in outputs.items():
            require((root / name).read_bytes() == data, "artifact mismatch: " + str(name))
    else:
        require(not any((root / name).exists() for name in outputs), "refusing to overwrite artifacts")
        for name, data in outputs.items():
            target = root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)


def verify_bundled(root):
    m = json.loads((root / MANIFEST).read_text())
    require(type(m["schemaVersion"]) is int and m["schemaVersion"] == 1 and m["revision"] == REVISION, "unsupported manifest")
    require(m["dictionary"]["url"] == SOURCE_URL and m["dictionary"]["sha256"] == SOURCE_SHA
            and m["dictionary"]["languageCode"] == "pt" and m["dictionary"]["edition"] == "pt"
            and m["wordfreq"]["wheelSHA256"] == WHEEL_SHA and m["wordfreq"]["member"] == MEMBER
            and m["wordfreq"]["memberSHA256"] == MEMBER_SHA, "source pin mismatch")
    require(set(m["filesSHA256"]) == {str(SWIFT), str(NOTICES), str(SOURCES)}, "file inventory mismatch")
    check_attribution_pins(m["filesSHA256"])
    for name, sha in m["filesSHA256"].items():
        require(file_digest(root / name) == sha, "bundled file hash mismatch: " + name)
    text = (root / SWIFT).read_text()
    matches = re.findall(r'  static let words(1k|3k|5k|320k|550k): \[String\] = """\n(.*?)"""', text, re.S)
    scales = {k: body.splitlines() for k, body in matches}
    require(len(matches) == len(scales) == len(COUNTS) and list(scales) == list(COUNTS)
            and native_source(scales) == text.encode() and set(m["scales"]) == set(COUNTS), "native template mismatch")
    require(m["unitExamples"] == UNIT_EXAMPLES and m["technicalObservation"] == TECHNICAL_OBSERVATION
            and m["notationAuthority"] == SI_SOURCE, "technical evidence changed")
    rows = [r.split("\t") for r in (root / SOURCES).read_text().splitlines() if not r.startswith("#")]
    require(all(len(r) == 5 and all(r) for r in rows), "invalid evidence mapping")
    evidence = {r[0]: r[1:] for r in rows}
    require(len(rows) == len(evidence) == m["sourceMapCount"]
            and set(evidence) == {w for words in scales.values() for w in words}, "evidence coverage mismatch")
    for word, row in evidence.items():
        require(row[0] in {"dictionaryLiteral", "frequencyObservation", "authoredSIUnit"}, "unknown evidence kind")
        if row[0] == "authoredSIUnit":
            require(word in UNIT_EXAMPLES and row == ["authoredSIUnit", "Typebar", SI_SOURCE, "-"], "invalid unit evidence")
        elif row[0] == "frequencyObservation":
            require(row[1] == "wordfreq" and row[2] == MEMBER and row[3].isdigit(), "invalid observation evidence")
        else:
            require(row[1] == "pt", "invalid dictionary edition")
    for k, words in scales.items():
        expected = m["scales"][k]
        require(len(words) == len(set(words)) == COUNTS[k] and shape(words) == expected["shape"]
                and digest(("\n".join(words) + "\n").encode()) == expected["wordsSHA256"], "native data mismatch")
        require(all(literal(w) and all(c.isalpha() or c in " -.'’²³2" for c in w) for w in words)
                and shape(words)["controlCount"] == 0, "invalid native character")
        require(shape(words)["spaceCount"] == PHRASES[k] and shape(words)["uppercaseCount"] == (1 if k == "5k" else 0), "practice section changed")
        require(dict(Counter(evidence[w][0] for w in words)) == expected["evidenceCounts"], "evidence counts changed")
        require(("Portugal" in words) == (k == "5k"), "proper name practice changed")
        require((TECHNICAL_OBSERVATION in words) == (k == "5k")
                and set(UNIT_EXAMPLES).issubset(words) == (k in ["320k", "550k"]), "technical practice changed")
    print("Portuguese bundled integrity passed (five pools; source reproduction is stronger)")


class Contracts(unittest.TestCase):
    def pools(self):
        return {k: {} for k in ["letters", "cased", "phrases", "hyphen", "period", "apostrophe"]}

    def test_language_gate_and_metadata_rejection(self):
        p = self.pools()
        collect_entry({"word": "coração", "lang_code": "pt", "pos": "noun", "forms": [
            {"form": "corações"}, {"form": "filler", "tags": ["error-unrecognized-form"]},
            {"form": "metadata", "tags": ["table-tags"]}]}, p)
        collect_entry({"word": "heart", "lang_code": "en", "pos": "noun"}, p)
        self.assertEqual(p["letters"], {"coração": "coração", "corações": "coração"})

    def test_literal_phrases_punctuation_and_case_are_not_manufactured(self):
        p = self.pools()
        for w in ["por favor", "por  favor", "segunda-feira", "anti-", "d'água", "etc.", "Portugal"]:
            collect_entry({"word": w, "lang_code": "pt", "pos": "noun"}, p)
        self.assertEqual(set(p["phrases"]), {"por favor"})
        self.assertEqual(set(p["hyphen"]), {"segunda-feira", "anti-"})
        self.assertEqual(p["cased"], {"Portugal": "Portugal"})
        self.assertEqual(set(p["apostrophe"]), {"d'água"})
        self.assertEqual(set(p["period"]), {"etc."})

    def test_observation_filter_preserves_nfc_and_rejects_repeated_filler(self):
        self.assertTrue(observed_letter("coração"))
        for w in ["corac\u0327a\u0303o", "hahahahaha", "kkkkkk", "mp3", "Portugal"]:
            self.assertFalse(observed_letter(w), w)

    def test_source_shortage_and_boolean_counts_never_pad(self):
        for n in [True, -1, 2]:
            with self.assertRaises(ValueError):
                take(["real"], n, "fixture")

    def test_reserved_longest_is_an_existing_word(self):
        chosen = ["real"]
        retain_longest(chosen, ["real", "verdadeiro"])
        self.assertEqual(chosen, ["verdadeiro"])
        chosen = ["real"]
        retain_longest(chosen, ["cotidiano", "abacatear"])
        self.assertEqual(chosen, ["cotidiano"])
        with self.assertRaises(ValueError):
            retain_longest([], ["real"])

    def test_observations_fill_only_a_dictionary_capacity_gap(self):
        self.assertEqual(choose_letters(["casa", "pessoa"], ["the", "novo"], 2), ["casa", "pessoa"])
        self.assertEqual(choose_letters(["casa"], ["novo"], 2), ["casa", "novo"])
        with self.assertRaisesRegex(ValueError, "never pad"):
            choose_letters(["casa"], [], 2)

    def test_frequency_bins_reject_order_types_and_duplicates(self):
        for bins in [[[1]], [["b", "a"]], [["a", "a"]], [["a"], ["a"]], "invalid"]:
            with self.assertRaises(ValueError):
                frequency_bands(bins)

    def test_component_rank_is_explicit_estimate(self):
        self.assertEqual(priority("por favor", {"por": 1, "favor": 4})[0], 4)
        self.assertEqual(priority("d'água", {"d'água": 3, "água": 1})[0], 3)

    def test_unit_examples_are_unranked_not_control_or_dollar_filler(self):
        self.assertEqual(UNIT_EXAMPLES, ["m²", "m³"])
        self.assertEqual(shape(UNIT_EXAMPLES)["digitCount"], 2)
        self.assertEqual(shape(UNIT_EXAMPLES)["controlCount"], 0)
        self.assertEqual(SI_SOURCE, "https://doi.org/10.59161/AUEZ1291")

    def test_attribution_cannot_be_redefined_by_manifest(self):
        check_attribution_pins(dict(ATTRIBUTION_PINS))
        for n in ATTRIBUTION_PINS:
            with self.assertRaises(ValueError):
                check_attribution_pins(dict(ATTRIBUTION_PINS, **{n: "0" * 64}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dictionary", type=Path)
    parser.add_argument("--wordfreq-wheel", type=Path)
    parser.add_argument("--output-root", type=Path, default=Path.cwd())
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--self-test", action="store_true")
    mode.add_argument("--check-bundled", action="store_true")
    mode.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return 0 if unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(Contracts)).wasSuccessful() else 1
    if args.check_bundled:
        verify_bundled(args.output_root)
        return 0
    require(args.dictionary is not None and args.wordfreq_wheel is not None, "provide --dictionary and --wordfreq-wheel")
    bands, notices = read_frequency(args.wordfreq_wheel)
    publish(artifacts(read_dictionary(args.dictionary), bands, notices), args.output_root, args.check)
    print("Portuguese source reproduction " + ("checked" if args.check else "prepared"))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, KeyError, OSError) as error:
        print("Portuguese preparation failed: " + str(error), file=sys.stderr)
        raise SystemExit(1)
