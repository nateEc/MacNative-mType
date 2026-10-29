#!/usr/bin/env python3
"""Independent Norsk ordbank / Språkbanken unigram selection. QA only.
No downloads, reference words, dependencies or native runtime processing.
"""
import argparse
from collections import Counter, defaultdict
import csv
import hashlib
import io
import json
from pathlib import Path
import re
import sys
import tarfile
import unicodedata
import unittest
import zipfile

REVISION = "ordbank-20220201-nb-unigrams-norwegian-v1"
BASE = "https://www.nb.no/sbfil/"
INPUTS = {
    "nob": {
        "dictionaryURL": BASE + "leksikalske_databaser/ordbank/20220201_norsk_ordbank_nob_2005.tar.gz",
        "dictionarySHA256": "57d91cb3f17b85befa50a3b56fcaed9800ca665b39486fe97b668add914d5f60",
        "dictionaryMember": "fullformsliste.txt",
        "dictionaryMemberSHA256": "45a648b51ed22741acc3e4fc8d17178dfcce0e9622ea2ce12204f11d8c6bcfaf",
        "frequencyURL": BASE + "tekst/1gram_nob_f1_freq.zip",
        "frequencySHA256": "cda1477a11fc98bcf61e8152fe1a09a4d5f9ae04b16c4ed9dc86ee224c2284e3",
        "frequencyMember": "1gram_nob_f1_freq.frk",
        "frequencyMemberSHA256": "acb8b7c20d61628f10a4a9b229dffdea0d43ab285f97ac93b7b1e3ddb717e44d",
        "dictionaryCatalogue": "https://www.nb.no/sprakbanken/ressurskatalog/oai-nb-no-sbr-5/",
        "frequencyCatalogue": "https://www.nb.no/sprakbanken/ressurskatalog/oai-nb-no-sbr-12/",
    },
    "nno": {
        "dictionaryURL": BASE + "leksikalske_databaser/ordbank/20220201_norsk_ordbank_nno_2012.tar.gz",
        "dictionarySHA256": "32987494b77c54b5c3890e891b99e35d5a45a16643a5c1820cd5e02fd55b1b8d",
        "dictionaryMember": "fullformer_2012.txt",
        "dictionaryMemberSHA256": "654bcfcf11374947a0be0d27173a94a4f7d75671d792de439bea1fba07ef8e36",
        "frequencyURL": BASE + "tekst/1gram_nno_f1_freq.zip",
        "frequencySHA256": "2c53d0073b0b7036e94029251e51e58fc98d7e1adbc1d390f191e5d30c291cee",
        "frequencyMember": "1gram_nno_f1_f.frk",
        "frequencyMemberSHA256": "375a5726670950500bd94e4baea3ede88aeab8e3f366926a43cf9a269068ead6",
        "dictionaryCatalogue": "https://www.nb.no/sprakbanken/ressurskatalog/oai-nb-no-sbr-41/",
        "frequencyCatalogue": "https://www.nb.no/sprakbanken/ressurskatalog/oai-nb-no-sbr-8/",
    },
}
# Per input class: count, minimum/maximum characters, maximum fields/field length.
# These are aggregate input contracts, never reference word values.
SPECS = {
    "nob1k": {"L": (1000, 1, 15, 1, 15)},
    "nob5k": {"L": (5000, 1, 28, 1, 28)},
    "nob10k": {"L": (9999, 1, 28, 1, 28), "C": (1, 8, 8, 1, 8)},
    "nob150k": {"L": (141691, 1, 30, 1, 30), "CP": (100, 5, 17, 1, 17),
                "P": (1146, 4, 26, 1, 26), "PN": (1, 16, 16, 1, 16)},
    "nob600k": {"L": (600063, 1, 33, 1, 33), "C": (5194, 2, 23, 1, 23),
                "CN": (10, 2, 3, 1, 3), "CP": (4966, 4, 29, 1, 29),
                "CPN": (121, 6, 17, 1, 17), "N": (3, 2, 3, 1, 3),
                "P": (4604, 3, 28, 1, 28), "PN": (9, 8, 18, 1, 18)},
    "nno1k": {"L": (1000, 1, 18, 1, 18)},
    "nno5k": {"L": (5000, 1, 27, 1, 27)},
    "nno10k": {"L": (9939, 1, 27, 1, 27)},
    "nno100k": {"L": (104068, 1, 28, 1, 28), "C": (1, 5, 5, 1, 5),
                "CP": (27, 5, 19, 1, 19), "P": (648, 4, 29, 1, 29),
                "PN": (1, 17, 17, 1, 17)},
    "nno400k": {"L": (401404, 1, 31, 1, 31), "C": (5254, 2, 23, 1, 23),
                "CN": (13, 2, 3, 1, 3), "CP": (1384, 3, 22, 1, 22),
                "CPN": (123, 5, 17, 1, 17), "N": (3, 2, 3, 1, 3),
                "P": (2515, 3, 31, 1, 31), "PN": (4, 17, 19, 1, 19),
                "PS": (14, 15, 23, 3, 18), "S": (5, 4, 12, 3, 7)},
}
RESERVED = {"nob": ["ikke", "menneske", "språk", "lærer", "øvelse"],
            "nno": ["ikkje", "menneske", "språk", "lærar", "øving"]}
SWIFT = Path("Sources/Typebar/NorwegianCorpus.generated.swift")
NOTICES = Path("Resources/NorwegianCorpusNotices.txt")
SOURCES = Path("Resources/NorwegianCorpusSources.txt")
MANIFEST = Path("Compatibility/norwegian-corpus.json")
PUBLISHED = {
    str(SWIFT): "ad94ff044a09eebcd871f7d2e28dfe392c3af0f73c87d14db52cdf149e50f523",
    str(NOTICES): "9f4f38944278f000ce2176fb072e66c6c8d2f68360a8349878f8f2f77a381df7",
    str(SOURCES): "0ac83d52fecc28a648daca9bcdf9c3480b6b474b084abbff8cd8a234d69ad6b3",
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


def eligible(word):
    return (type(word) is str and 1 <= len(word) <= 60 and word == unicodedata.normalize("NFC", word)
            and all(word.split(" ")) and not word.startswith("-") and not word.endswith("-")
            and any(c.isalpha() or c.isnumeric() for c in word)
            and all(c in " -'" or c.isnumeric() or (c.isalpha() and unicodedata.name(c, "").startswith("LATIN ")) for c in word))


def input_class(word):
    return "".join(k for k, yes in [("C", any(c.isupper() for c in word)),
        ("P", any(unicodedata.category(c).startswith("P") for c in word)),
        ("S", " " in word), ("N", any(c.isnumeric() for c in word))] if yes) or "L"


def collect_row(row, forms):
    if row["NORMERING"] != "normert" or row["TILDATO"] != "4000":
        return
    word = row["OPPSLAG"]
    if eligible(word):
        require(row["LEMMA_ID"].isdigit() and row["LOEPENR"].isdigit(), "invalid dictionary identifiers")
        owner = (int(row["LEMMA_ID"]), int(row["LOEPENR"]))
        if word not in forms or owner < forms[word]:
            forms[word] = owner


def read_dictionary(path, language):
    require(unicodedata.unidata_version == "15.0.0", "source preparation requires Unicode 15.0.0")
    source = INPUTS[language]
    require(file_digest(path) == source["dictionarySHA256"], "dictionary snapshot SHA-256 mismatch")
    with tarfile.open(path) as archive:
        # Read the one pinned member; never extract files or execute archive code.
        raw = archive.extractfile(source["dictionaryMember"]).read()
    require(digest(raw) == source["dictionaryMemberSHA256"], "dictionary member SHA-256 mismatch")
    forms, rows = {}, 0
    reader = csv.DictReader(io.StringIO(raw.decode("iso-8859-1")), delimiter="\t")
    require(reader.fieldnames == ["LOEPENR", "LEMMA_ID", "OPPSLAG", "TAG", "PARADIGME_ID", "BOY_NUMMER", "FRADATO", "TILDATO", "NORMERING"], "unexpected dictionary columns")
    for row in reader:
        collect_row(row, forms); rows += 1
    return forms, rows


def components(word):
    return [p for p in re.split("[-' ]", word.casefold()) if p]


def frequency_counts(lines, needed):
    counts, rows, previous = Counter(), 0, None
    for line in lines:
        # The official Bokmål data includes a token of three NBSPs. Parse the
        # ASCII column separator without stripping that literal Unicode token.
        match = re.fullmatch(r"[ \t]*(\d+)[ \t]+(.+)", line.rstrip("\r\n"))
        require(match is not None and int(match[1]) > 1, "invalid unigram row")
        count, word = int(match[1]), match[2]
        require(previous is None or count <= previous, "frequency input is not descending")
        previous = count; rows += 1
        key = unicodedata.normalize("NFC", word).casefold()
        if key in needed:
            counts[key] += count
    return counts, rows


def read_frequency(path, language, forms):
    source = INPUTS[language]
    require(file_digest(path) == source["frequencySHA256"], "frequency snapshot SHA-256 mismatch")
    needed = {w.casefold() for w in forms}
    needed.update(p for w in forms for p in components(w))
    with zipfile.ZipFile(path) as archive:
        raw = archive.read(source["frequencyMember"])
    require(digest(raw) == source["frequencyMemberSHA256"], "frequency member SHA-256 mismatch")
    counts, rows = frequency_counts(io.StringIO(raw.decode("iso-8859-1")), needed)
    return counts, {"rows": rows, "matchedCasefoldKeys": len(counts), "matchedTokenCount": sum(counts.values())}


def rank_evidence(word, counts):
    whole = counts[word.casefold()]
    parts = components(word)
    estimate = min((counts[p] for p in parts), default=0) if len(parts) > 1 else 0
    return whole, estimate


def priority(word, counts):
    whole, estimate = rank_evidence(word, counts)
    return (0, -whole, word.casefold(), word) if whole else ((1, -estimate, word.casefold(), word)
        if estimate else (2, 0, word.casefold(), word))


def fits(word, spec):
    _, minimum, maximum, fields, field_length = spec
    parts = word.split(" ")
    return minimum <= len(word) <= maximum and len(parts) <= fields and max(map(len, parts)) <= field_length


def select_group(candidates, spec, counts, reserved=()):
    count = spec[0]
    require(type(count) is int and count > 0, "invalid quota")
    available = sorted((w for w in candidates if fits(w, spec)), key=lambda w: priority(w, counts))
    require(len(available) >= count, "insufficient literal dictionary forms; never pad")
    required = list(reserved)
    require(all(w in available for w in required), "reserved literal form is absent")
    # Stable ties retain the best-ranked real field rather than fabricated text.
    scores = [lambda w: -len(w), len, lambda w: w.count("-"),
              lambda w: len(w.split(" ")), lambda w: max(map(len, w.split(" ")))]
    boundaries = [(score, max(map(score, available))) for score in scores]
    while True:
        missing = [(score, target) for score, target in boundaries
                   if not any(score(w) == target for w in required)]
        if not missing: break
        # One literal can cover several tied boundaries. Do not consume quota
        # for an arbitrary best-ranked field whose boundary is already covered.
        candidate = max(available, key=lambda w: sum(score(w) == target for score, target in missing))
        required.append(candidate)
    for predicate in [lambda w: "'" in w,
                      lambda w: any(c.isupper() for c in w) and not any("A" <= c <= "Z" for c in w)]:
        candidate = next((w for w in available if predicate(w)), None)
        if candidate is not None and len(set(required + [candidate])) <= count:
            required.append(candidate)
    required = list(dict.fromkeys(required))
    require(len(required) <= count, "quota cannot preserve required field boundaries")
    chosen, protected = available[:count], set(required)
    for word in required:
        if word not in chosen:
            at = next((i for i in range(len(chosen)-1, -1, -1) if chosen[i] not in protected), None)
            require(at is not None, "no room for required literal field")
            chosen[at] = word
    chosen.sort(key=lambda w: priority(w, counts))
    return chosen, len(available)


def shape(words):
    groups = defaultdict(list)
    for word in words: groups[input_class(word)].append(word)
    return {"count": len(words), "uniqueCount": len(set(words)), "minimumLength": min(map(len, words)),
            "maximumLength": max(map(len, words)), "uppercaseEntries": sum(any(c.isupper() for c in w) for w in words),
            "nonLetterEntries": sum(any(not c.isalpha() for c in w) for w in words),
            "punctuationEntries": sum(any(unicodedata.category(c).startswith("P") for c in w) for w in words),
            "numericEntries": sum(any(c.isnumeric() for c in w) for w in words), "spaceEntries": sum(" " in w for w in words),
            "nonASCIIEntries": sum(not w.isascii() for w in words), "maximumHyphens": max(w.count("-") for w in words),
            "punctuationScalars": dict(sorted(Counter(c for w in words for c in w if unicodedata.category(c).startswith("P")).items())),
            "groups": {k: {"count": len(v), "min": min(map(len, v)), "max": max(map(len, v)),
                            "maxFields": max(len(w.split(" ")) for w in v),
                            "maxFieldLength": max(len(p) for w in v for p in w.split(" "))} for k, v in sorted(groups.items())}}


def validate(words, spec):
    require(all(eligible(w) for w in words), "invalid literal form")
    expected = {k: dict(zip(["count", "min", "max", "maxFields", "maxFieldLength"], values)) for k, values in spec.items()}
    require(len(words) == len(set(words)) == sum(v[0] for v in spec.values()) and shape(words)["groups"] == expected,
            "published input-class or field boundary mismatch")


def native_source(scales):
    return ("// Generated by Scripts/prepare-norwegian-corpus.py; do not edit.\n"
            "// Independent Norsk ordbank literal forms, ranked on separate native-standard unigrams.\n"
            "// Full attribution and row provenance: Resources/NorwegianCorpus*.txt.\n"
            "// No reference-project code or word data. Each choice initializes on demand.\n"
            "enum NorwegianCorpus {\n" + f'  static let revision = "{REVISION}"\n'
            + "".join(f'  static let {k}: [String] = """\n' + "\n".join(words)
                       + '\n""".split(separator: "\\n").map(String.init)\n' for k, words in scales.items()) + "}\n").encode()


def artifacts(dictionaries, frequencies, details):
    scales, available, evidence = {}, {}, {}
    for profile, specs in SPECS.items():
        language = profile[:3]; forms, counts = dictionaries[language], frequencies[language]
        pools = defaultdict(list)
        for word in forms: pools[input_class(word)].append(word)
        words, available[profile] = [], {}
        for group, spec in specs.items():
            candidates = pools[group]
            if profile in {"nob150k", "nno100k"}: candidates = [w for w in candidates if "'" not in w]
            chosen, capacity = select_group(candidates, spec, counts, RESERVED[language] if group == "L" else ())
            words += chosen; available[profile][group] = capacity
        words.sort(key=lambda w: priority(w, counts)); validate(words, specs); scales[profile] = words
        for word in words:
            whole, estimate = rank_evidence(word, counts)
            evidence[language, word] = [str(n) for n in (*forms[word], whole, estimate)]
    source = ("# Typebar independent Norwegian dictionary row provenance: " + REVISION + "\n"
              "# language\tword\tlemmaID\tfullformRowID\tcasefoldWholeTokenCount\tminimumComponentEstimate\n"
              "# Look up the pinned dictionary archive/member and LOEPENR/LEMMA_ID columns.\n"
              "# Zero whole-token count means unobserved in the fixed unigram data, not measured zero usage.\n"
              "# A positive component estimate is a ranking estimate, never a whole-word measurement.\n")
    source += "".join("\t".join([language, word] + row) + "\n" for (language, word), row in sorted(evidence.items()))
    notice = ("Typebar independent Norwegian scale corpora\nRevision: " + REVISION + "\n\n"
              "Norsk ordbank: Nasjonalbiblioteket / Språkbanken; Språkrådet and Universitetet i Bergen.\n"
              "Adapted selection under Creative Commons Attribution 4.0 International (CC BY 4.0).\n"
              "https://creativecommons.org/licenses/by/4.0/\n"
              "N-gram unigrams: Nasjonalbiblioteket / Språkbanken, CC0 1.0.\n"
              "https://creativecommons.org/publicdomain/zero/1.0/\n\n"
              "Changes: select literal normert forms with TILDATO=4000 from the fixed 2022-02-01\n"
              "full-form dictionaries (ISO-8859-1); retain lemma and fullform row identifiers.\n"
              "This snapshot is not the current live normative database. Morphologically possible\n"
              "dictionary forms may be very rare or never used. No original-reference words,\n"
              "guessed suffixes, recased pseudo-names or invented numeric/punctuation forms.\n"
              "Each written standard uses its own historical unigram data, never the other standard.\n"
              "NFC/casefold token counts aggregate original case variants. Rank observed whole\n"
              "forms first, then estimates from the least frequent hyphen/apostrophe/space\n"
              "component when all components are observed, then unobserved forms alphabetically.\n"
              "Reserve five letter-practice words, actual shortest/longest fields, maximum\n"
              "hyphens/field counts/field lengths, apostrophes and Unicode-only capitals when available.\n"
              "Quotas preserve aggregate input-class boundaries; this is not a pure frequency\n"
              "cutoff, original-word, language-quality, difficulty or distribution equivalence.\n"
              "Numbers, punctuation, spaces and case are literal source forms; no mechanical padding.\n"
              "NorwegianCorpusSources.txt distinguishes whole-token counts and component estimates.\n"
              "No source archives, full frequency lists, definitions, audio or images bundled.\n"
              "Basic authored pools and captured historical prompts/metrics remain unchanged.\n\n")
    for language, info in INPUTS.items():
        notice += language + " (snapshots retrieved 2026-10-29):\n"
        for key, value in info.items(): notice += key + ": " + value + "\n"
        notice += "\n"
    generated = {SWIFT: native_source(scales), NOTICES: notice.encode(), SOURCES: source.encode()}
    manifest = {"schemaVersion": 1, "revision": REVISION, "inputs": INPUTS,
                "preparation": {"unicodeVersion": "15.0.0", "encoding": "ISO-8859-1", "runtimeDependencies": []},
                "sourceDetails": details, "available": available, "sourceMapCount": len(evidence),
                "scales": {k: {"shape": shape(w), "wordsSHA256": digest(("\n".join(w) + "\n").encode())} for k, w in scales.items()},
                "filesSHA256": {str(k): digest(v) for k, v in generated.items()},
                "limits": "Independent literal forms and aggregate input boundaries do not prove frequency, quality or full behavioral parity."}
    generated[MANIFEST] = (json.dumps(manifest, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode()
    return generated


def verify_pins(hashes):
    require(bool(PUBLISHED) and hashes == PUBLISHED, "published file pin mismatch; mutable manifest hashes are insufficient")


def verify_bundled(root):
    m = json.loads((root / MANIFEST).read_text())
    require(type(m["schemaVersion"]) is int and m["schemaVersion"] == 1 and m["revision"] == REVISION, "unsupported manifest")
    require(m["inputs"] == INPUTS, "source pin mismatch"); verify_pins(m["filesSHA256"])
    for name, sha in m["filesSHA256"].items(): require(file_digest(root / name) == sha, "bundled file hash mismatch: " + name)
    text = (root / SWIFT).read_text()
    matches = re.findall(r'  static let (nob|nno)(1k|5k|10k|100k|150k|400k|600k): \[String\] = """\n(.*?)"""', text, re.S)
    scales = {a+b: body.splitlines() for a, b, body in matches}
    require(len(matches) == len(scales) == len(SPECS) and list(scales) == list(SPECS) and native_source(scales) == text.encode()
            and set(m["scales"]) == set(SPECS), "native template mismatch")
    rows = [line.split("\t") for line in (root / SOURCES).read_text().splitlines() if not line.startswith("#")]
    require(all(len(row) == 6 and all(row) for row in rows), "invalid source mapping")
    evidence = {(row[0], row[1]): row[2:] for row in rows}
    require(len(rows) == len(evidence) == m["sourceMapCount"], "duplicate source mapping")
    expected = set()
    for key, words in scales.items():
        validate(words, SPECS[key]); require(m["scales"][key] == {"shape": shape(words), "wordsSHA256": digest(("\n".join(words) + "\n").encode())}, "native content mismatch")
        for word in words:
            item = (key[:3], word); expected.add(item)
            require(item in evidence and all(s.isdigit() for s in evidence[item]), "missing dictionary row evidence")
    require(set(evidence) == expected, "source mapping coverage mismatch")


def publish(outputs, root, check):
    verify_pins({str(k): digest(v) for k, v in outputs.items() if k != MANIFEST})
    if check:
        for name, data in outputs.items(): require((root / name).read_bytes() == data, "artifact mismatch: " + str(name))
    else:
        require(not any((root / name).exists() for name in outputs), "refusing to overwrite artifacts")
        for name, data in outputs.items():
            target = root / name; target.parent.mkdir(parents=True, exist_ok=True); target.write_bytes(data)


class Contracts(unittest.TestCase):
    def test_literals_keep_real_fields_and_reject_templates_or_unsafe_strings(self):
        for word in ["menneske", "øving", "NATO-land", "3D", "King's", "i lag"]: self.assertTrue(eligible(word))
        for word in ["-a", "a-", "a  b", "a\x92", "a\"b", "a\\b", "字", "e\u0301", "°C"]: self.assertFalse(eligible(word))

    def test_combined_classes(self):
        self.assertEqual(input_class("ABC-2"), "CPN"); self.assertEqual(input_class("i-lag no"), "PS")
        self.assertEqual(input_class("å"), "L"); self.assertEqual(input_class("3d"), "N")

    def test_actual_row_ownership_is_stable_and_unnormed_forms_excluded(self):
        forms = {}; row = dict(NORMERING="normert", TILDATO="4000", OPPSLAG="øving", LEMMA_ID="9", LOEPENR="2")
        collect_row(row, forms); collect_row(dict(row, LEMMA_ID="8", LOEPENR="4"), forms)
        collect_row(dict(row, OPPSLAG="fake", NORMERING="unormert"), forms)
        self.assertEqual(forms, {"øving": (8, 4)})

    def test_casefold_counts_are_real_aggregates(self):
        c, rows = frequency_counts(["10 Å\n", "5 å\n", "2 irrelevant\n"], {"å"})
        self.assertEqual(c, Counter({"å": 15})); self.assertEqual(rows, 3)

    def test_frequency_parser_rejects_wrong_order_or_format(self):
        for lines in [["2 a", "3 b"], ["one a"], ["1 a"], ["2"]]:
            with self.assertRaises(ValueError): frequency_counts(lines, {"a", "b"})

    def test_estimates_are_separate_from_whole_word_counts(self):
        c = Counter({"a": 8, "b": 4})
        self.assertEqual(rank_evidence("a-b", c), (0, 4)); self.assertEqual(rank_evidence("a-c", c), (0, 0))
        self.assertLess(priority("b", c), priority("a-b", c))

    def test_boundaries_are_real_and_reserved_words_not_padding(self):
        words, _ = select_group(["a", "å", "aaa", "bb"], (3, 1, 3, 1, 3), Counter({"bb": 9}), ["å"])
        self.assertEqual(set(words), {"bb", "å", "aaa"})
        self.assertEqual(min(map(len, words)), 1); self.assertEqual(max(map(len, words)), 3)

    def test_single_candidate_quota_does_not_duplicate_equivalent_boundaries(self):
        words, _ = select_group(["AB", "Øv"], (1, 2, 2, 1, 2), Counter({"ab": 10, "øv": 2}))
        self.assertEqual(words, ["AB"])

    def test_nonbreaking_space_token_is_not_stripped_into_a_missing_column(self):
        counts, rows = frequency_counts(["4 \u00a0\u00a0\u00a0\n"], {"a"})
        self.assertEqual(counts, Counter()); self.assertEqual(rows, 1)

    def test_insufficient_literal_capacity_fails(self):
        with self.assertRaises(ValueError): select_group(["a"], (2, 1, 3, 1, 3), Counter())

    def test_field_count_and_field_length_admission(self):
        self.assertTrue(fits("a-b cd e", (1, 4, 12, 3, 3)))
        self.assertFalse(fits("a-b cdef", (1, 4, 12, 3, 3)))

    def test_missing_published_pins_fail(self):
        with self.assertRaises(ValueError): verify_pins({})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for language in INPUTS:
        parser.add_argument("--" + language + "-dictionary", type=Path)
        parser.add_argument("--" + language + "-frequency", type=Path)
    parser.add_argument("--output-root", type=Path, default=Path(__file__).resolve().parents[1])
    for flag in ["check", "check-bundled", "self-test"]: parser.add_argument("--" + flag, action="store_true")
    args = parser.parse_args()
    if args.self_test: return 0 if unittest.TextTestRunner().run(unittest.defaultTestLoader.loadTestsFromTestCase(Contracts)).wasSuccessful() else 1
    if args.check_bundled:
        verify_bundled(args.output_root); print("Norwegian bundled integrity passed (ten pools; source reproduction is stronger)"); return 0
    dictionaries, frequencies, details = {}, {}, {}
    for language in INPUTS:
        dictionary, frequency = getattr(args, language + "_dictionary"), getattr(args, language + "_frequency")
        require(dictionary is not None and frequency is not None, "four fixed source snapshots required")
        dictionaries[language], rows = read_dictionary(dictionary, language)
        frequencies[language], info = read_frequency(frequency, language, dictionaries[language])
        details[language] = {"dictionaryRows": rows, "dictionaryForms": len(dictionaries[language]), "frequency": info}
    publish(artifacts(dictionaries, frequencies, details), args.output_root, args.check)
    print("Norwegian source reproduction checked" if args.check else "Norwegian corpora prepared"); return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError, TypeError) as error:
        print("Norwegian preparation failed: " + str(error), file=sys.stderr)
        raise SystemExit(1)
