#!/usr/bin/env python3
"""Reproduce independent Turkish literal pools; never reads Monkeytype words."""
import argparse
import gzip
import bz2
import heapq
from collections import Counter
from urllib.parse import quote
import hashlib
import json
from pathlib import Path
import re
import unicodedata
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = "https://kaikki.org/dictionary/Turkish/kaikki.org-dictionary-Turkish.jsonl"
SOURCE_SHA = "4adb303b621cdc2d52c7748b137508a946fee7c5f51ffabf404f266f19ee6109"
WHEEL_SHA = "4b1c6ecffc6198be3396d5cf871c4423ca71c907c231348d352dd54d62b97473"
MEMBER = "wordfreq/data/small_tr.msgpack.gz"
MEMBER_SHA = "10980704ee3ac5b52f226579251905412a04ead57092a12182dd0b8be6a765df"
REVISION = "kaikki-en-tr-20261102-literal-wordfreq-v1"
TATOEBA_SOURCE = "https://downloads.tatoeba.org/exports/per_language/tur/tur_sentences_detailed.tsv.bz2"
TATOEBA_SHA = "9809a3f64bc277063e3331ab7c6f77d41af54267af90dcbe45881d41ad857462"
SPECS = {'basic': (299, 11), '1k': (1026, 13), '5k': (5016, 17)}
REFERENCE_KEYS = {'basic': ' abcdefghiklmnoprstuvyzçöüğış', '1k': ' abcdefghijklmnoprstuvyzçöüğış', '5k': ' Habcdefghijklmnoprstuvyzçöüğış'}
CATEGORIES = {'basic': {'0/0/0': 174, '1/0/0': 124, '0/0/1': 1}, '1k': {'0/0/0': 563, '1/0/0': 462, '0/0/1': 1}, '5k': {'1/0/0': 2131, '0/0/0': 2848, '0/0/1': 13, '1/0/1': 22, '1/1/0': 1, '1/0/2': 1}}
LEGACY = 'sabah pencere kağıt kıyı rüzgar alıştırma odak sakin açık göl sokak masa ışık yolculuk sabır an şehir yağmur sessiz yön yıldız not bahçe nefes'.split()
PARTS = set("noun verb adj adv name pron num det conj intj prep postp particle phrase abbrev classifier".split())
BAD = {"misspelling", "proscribed", "nonstandard"}
SWIFT = "Sources/Typebar/TurkishCorpus.generated.swift"
ROWS = "Resources/TurkishCorpusSources.txt"
NOTICE = "Resources/TurkishCorpusNotices.txt"
MANIFEST = "Compatibility/turkish-corpus.json"
PUBLISHED = {
    SWIFT: "f5989eb795197a4d24c9ca41c744cc60888ae53b80fd012c7d3604bbb7883010",
    ROWS: "73db4573ac26711cc1de29ecc723cdd3cd0b83c82a52cce2c199cae1ec8e897d",
    NOTICE: "c9b278dee112d496f8070a9f6e569b722d7534dd6d728cd3793f325f544533c9",
    MANIFEST: "cb728eb133456593c89c2d1aeee3a02ca062fd61668877c6a771415ce67e4134",
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def literal(word):
    if not (type(word) is str and 1 <= len(word) <= 17
            and word == unicodedata.normalize("NFC", word)
            and set(word) <= set("".join(REFERENCE_KEYS.values()))
            and word.count(" ") <= 2
            and all(part and part.isalpha() for part in word.split(" "))):
        return False
    return not any(c.isupper() for c in word) or (word.startswith("H")
        and not any(c.isupper() for c in word[1:]))


def category(word):
    return f"{int(not word.isascii())}/{int(any(c.isupper() for c in word))}/{word.count(' ')}"


def collect(entry, forms):
    require(type(entry) is dict, "invalid dictionary entry")
    if entry.get("lang_code") != "tr" or entry.get("pos") not in PARTS:
        return
    senses = entry.get("senses", [])
    require(type(senses) is list, "invalid senses")
    if not senses or all(BAD.intersection(s.get("tags", [])) for s in senses):
        return
    title = entry.get("word")
    require(type(title) is str and not any(c in title for c in "\t\r\n"), "invalid source title")
    rows = entry.get("forms", [])
    require(type(rows) is list, "invalid forms")
    for row in [{"form": title}] + rows:
        require(type(row) is dict and type(row.get("form")) is str, "invalid form")
        tags = row.get("tags", [])
        require(type(tags) is list and all(type(t) is str for t in tags), "invalid tags")
        if BAD.intersection(tags) or any(t in {"romanization", "table-tags", "inflection-template", "class"}
                                        or t.startswith("error-") for t in tags):
            continue
        # Inflection tables can repeat one phrase in many grammatical forms.
        # Multiword options must instead be literal lexical headwords.
        if " " in row["form"] and row["form"] != title:
            continue
        if literal(row["form"]):
            forms.setdefault(row["form"], ("dictionary", title))


def read_sources(dictionary, wheel):
    require(sha(dictionary.read_bytes()) == SOURCE_SHA, "dictionary pin mismatch")
    forms = {}
    for line in dictionary.open(encoding="utf-8"):
        collect(json.loads(line), forms)
    require(sha(wheel.read_bytes()) == WHEEL_SHA, "wheel pin mismatch")
    import msgpack
    require(msgpack.__version__ == "1.1.2", "requires msgpack 1.1.2")
    with zipfile.ZipFile(wheel) as archive:
        data = archive.read(MEMBER)
        metadata = archive.read("wordfreq-3.1.1.dist-info/METADATA").decode()
    require(sha(data) == MEMBER_SHA, "frequency member pin mismatch")
    bins = msgpack.unpackb(gzip.decompress(data), raw=False)
    require(bins[0] == {"format": "cB", "version": 1}, "invalid frequency format")
    bands = {}
    for index, words in enumerate(bins[1:]):
        require(type(words) is list and words == sorted(set(words)), "invalid frequency bin")
        for word in words:
            require(type(word) is str and word not in bands, "invalid frequency token")
            bands[word] = index
    for word in LEGACY:
        forms.setdefault(word, ("typebar-legacy", "Typebar authored starter vocabulary"))
    return forms, bands, metadata[metadata.index("## License"):].strip() + "\n"


def turkish_lower(text):
    return unicodedata.normalize("NFC", text).replace("I", "ı").replace("İ", "i").lower()


def phrase_matches(text, candidates):
    text = turkish_lower(text)
    spans = []
    start = None
    for index, character in enumerate(text):
        # Keep digits, underscores and combining marks inside token boundaries
        # so a valid phrase cannot match just part of a larger written word.
        part = character.isalnum() or character == "_" or unicodedata.category(character).startswith("M")
        if part and start is None:
            start = index
        elif not part and start is not None:
            spans.append((start, index)); start = None
    if start is not None:
        spans.append((start, len(text)))
    matched = set()
    for offset in range(len(spans)):
        for size in [2, 3]:
            selected = spans[offset:offset + size]
            if len(selected) != size or any(text[a[1]:b[0]] != " " for a, b in zip(selected, selected[1:])):
                continue
            phrase = text[selected[0][0]:selected[-1][1]]
            if phrase in candidates:
                matched.add(phrase)
    return matched


def read_phrase_observations(sentences, candidates):
    require(sha(sentences.read_bytes()) == TATOEBA_SHA, "Tatoeba snapshot pin mismatch")
    counts, first, authors, identifiers = Counter(), {}, set(), set()
    for line in bz2.open(sentences, "rt", encoding="utf-8"):
        fields = line.rstrip("\n").split("\t")
        require(len(fields) == 6 and fields[0].isdigit() and fields[1] == "tur", "invalid Turkish sentence row")
        identifier, _, text, author, _, _ = fields
        require(identifier not in identifiers, "duplicate sentence identifier")
        identifiers.add(identifier)
        author = author if author not in {"", "\\N"} else "(unowned)"
        authors.add(author)
        for phrase in phrase_matches(text, candidates):
            counts[phrase] += 1  # One observation per sentence, not per repetition.
            first.setdefault(phrase, (identifier, author))
    return counts, first, sorted(authors), len(identifiers)


def priority(word, bands, phrases=None):
    if " " in word:
        observed = (phrases or {}).get(word, 0)
        return (observed == 0, -observed, word)
    # H is the only admitted uppercase scalar; i and dotless ı stay unchanged.
    value = bands.get(word.lower())
    return (value is None, value if value is not None else 0, word)


def choose(eligible, required, count, maximum, limits, characters, bands, phrases=None):
    require(required <= eligible, "required literal seed missing")
    chosen = set(required)
    counts = Counter(map(category, chosen))
    require(all(n <= limits.get(k, 0) for k, n in counts.items()), "seed exceeds category quota")

    def fits(word):
        key = category(word)
        return counts[key] < limits.get(key, 0)

    def add(word):
        chosen.add(word)
        counts[category(word)] += 1

    def add_best(candidates, key):
        word = min((w for w in candidates if w not in chosen and fits(w)), key=key, default=None)
        require(word is not None, "insufficient literal forms for required coverage")
        add(word)

    for length in [1, maximum]:
        if not any(len(w) == length for w in chosen):
            add_best((w for w in eligible if len(w) == length and " " not in w), lambda w: priority(w, bands, phrases))
    missing = characters - set("".join(chosen))
    while missing:
        add_best((w for w in eligible if set(w) & missing),
                 lambda w: (-len(set(w) & missing), priority(w, bands, phrases)))
        missing = characters - set("".join(chosen))
    for key, limit in limits.items():
        needed = limit - counts[key]
        selected = heapq.nsmallest(needed,
            (w for w in eligible if w not in chosen and category(w) == key),
            key=lambda w: priority(w, bands, phrases))
        require(len(selected) == needed, "insufficient literal category")
        for word in selected:
            add(word)
    require(len(chosen) == count and dict(counts) == limits, "selection category mismatch")
    require(set("".join(chosen)) == characters, "typing key mismatch")
    return sorted(chosen, key=lambda w: priority(w, bands, phrases))


def select(forms, bands, phrases):
    pools = {}
    for name, (count, maximum) in SPECS.items():
        characters = set(REFERENCE_KEYS[name])
        required = set(LEGACY) | set(pools.get("basic", []))
        eligible = {w for w in forms if len(w) <= maximum and set(w) <= characters}
        pools[name] = choose(eligible, required, count, maximum,
            CATEGORIES[name], characters, bands, phrases)
    return pools


def artifacts(dictionary, wheel, sentences):
    forms, bands, licenses = read_sources(dictionary, wheel)
    candidates = {w for w in forms if " " in w and not any(c.isupper() for c in w)}
    phrases, first, authors, sentence_count = read_phrase_observations(sentences, candidates)
    pools = select(forms, bands, phrases)
    native = "// Independent literal Turkish forms, CC BY-SA 4.0.\n// See bundled per-word provenance; no spelling or numbered-word synthesis.\nenum TurkishCorpus {\n  static let revision = " + json.dumps(REVISION) + "\n"
    for name, words in pools.items():
        native += '  static let ' + ("basic" if name == "basic" else "words" + name) + ': [String] = """\n' + "\n".join(words) + '\n""".split(separator: "\\n").map(String.init)\n'
    native += "}\n"
    union = sorted(set().union(*map(set, pools.values())))
    rows = "# word\tsourceKind\tsourceTitle\twordfreqWholeTokenBand\ttatoebaLookup\ttatoebaWholePhraseSentenceCount\tfirstSentenceID\tfirstSentenceAuthor (NA means unobserved; single words not queried in Tatoeba)\n"
    for word in union:
        kind, title = forms[word]
        value = bands.get(word.lower())
        seen = phrases.get(word)
        identifier, author = first.get(word, ("NA", "NA"))
        rows += "\t".join([word, kind, title, "NA" if value is None else str(value),
            "whole-phrase" if " " in word else "not-queried",
            str(seen) if seen else "NA", identifier, author]) + "\n"
    unattested = sorted(w for w in LEGACY if forms[w][0] == "typebar-legacy")
    notice = f"""Typebar independent Turkish corpus
Revision: {REVISION}
English Wiktionary contributors, extracted by Kaikki.org / Wiktextract.
Source: {SOURCE}
Snapshot SHA-256: {SOURCE_SHA}
Index reports extraction 2026-10-30 from enwiktionary dump 2026-10-01,
using extractor revisions 19f9a30 and 6f96ddf.
Only literal NFC alphabetic titles/forms of lang_code=tr and declared lexical
parts of speech are selected. Phrases must be literal dictionary headwords,
not variants produced by inflection tables. Up to three components use single ASCII spaces.
No recasing, affix synthesis, numbered padding, definitions, examples or
original Monkeytype words. Phrase strings remain whole source options.
Misspelling/proscribed/nonstandard-only senses and tagged extraction/template/
romanization forms are excluded. These filters do not certify linguistic quality.
Per-word contributor page: https://en.wiktionary.org/wiki/ + encoded sourceTitle.
Selection is adapted by filtering/ranking; displayed spellings are unchanged.
All 24 old Typebar authored starter words remain in all three pools.
Legacy words without selected lexical attestation: {', '.join(unattested) or '(none)'}.
This reports lexical selection, not absence of other raw dictionary entries.
Unattested retained starters are marked typebar-legacy, not dictionary forms.
The basic pool is retained in both larger pools. The 1k and 5k pools are not
nested: 1k must cover lowercase j, which is absent from the 5k typing alphabet.
Only the 5k pool admits one uppercase-H, non-ASCII, single-component option.
Its 36 phrase options include exactly one three-component non-ASCII phrase;
there are no invented adjacent spaces. These are not 36 single target fields:
the runtime factory consumes phrase components in consecutive word slots.
Dictionary selection and frequency data: CC BY-SA 4.0 International.
https://creativecommons.org/licenses/by-sa/4.0/
Source mapping: TurkishCorpusSources.txt; reproducible selection in the repository.
Vocabulary, ordering, distribution and linguistic quality are not certified
equivalent to Monkeytype. The original source provides aggregate constraints only.

wordfreq 3.1.1 wheel SHA-256: {WHEEL_SHA}
Member: {MEMBER}
Member SHA-256: {MEMBER_SHA}
Single-word ranking uses whole-token lowercase lookup. H is the only allowed uppercase
scalar, so this lookup never changes Turkish dotted i or dotless ı.
Missing observations remain NA, not zero or an estimate from components.
Bands are observations, not usage counts or runtime Zipf support.

Tatoeba Turkish contributors, phrase observation evidence only.
Source: {TATOEBA_SOURCE}
Snapshot SHA-256: {TATOEBA_SHA}
Sentence rows: {sentence_count}; contributor identifiers: {len(authors)}.
License for sentence data: CC BY 2.0 France.
https://creativecommons.org/licenses/by/2.0/fr/
https://tatoeba.org/en/downloads
Phrase ranking uses matching sentence counts, one count per sentence. Exact
Unicode word boundaries and single ASCII internal spaces are required; no
cross-punctuation, adjacent-space or component-frequency estimates. Turkish
case lookup maps I to ı and İ to i without merging the two lowercase letters.
Sentence IDs/first author accompany observed selected phrases; absent evidence
is NA. Single words are explicitly not queried in this phrase-only source.
No sentence text, translations or audio is bundled. These statistics do not
certify linguistic quality. All contributor identifiers in the processed
snapshot are credited below; unknown/unowned rows retain an explicit label.

""" + "\n".join(author if author == "(unowned)" else
        author + " https://tatoeba.org/en/user/profile/" + quote(author, safe="")
        for author in authors) + "\n\n" + licenses
    output = {SWIFT: native.encode(), ROWS: rows.encode(), NOTICE: notice.encode()}
    doc = {"schemaVersion": 1, "revision": REVISION, "source": SOURCE, "sourceSHA256": SOURCE_SHA,
           "wheelSHA256": WHEEL_SHA, "member": MEMBER, "memberSHA256": MEMBER_SHA,
           "tatoebaSource": TATOEBA_SOURCE, "tatoebaSHA256": TATOEBA_SHA,
           "tatoebaSentenceRows": sentence_count, "tatoebaContributorIdentifiers": len(authors),
           "legacyUnattested": unattested,
           "legacyAttestationScope": "Selected lexical parts of speech; raw romanization entries are excluded.",
           "artifacts": {p: sha(b) for p, b in output.items()}, "pools": {}}
    for name, words in pools.items():
        characters = set("".join(words))
        doc["pools"][name] = {"count": len(words), "minimumLength": min(map(len, words)),
            "maximumLength": max(map(len, words)), "characters": "".join(sorted(characters)),
            "referenceCharacters": REFERENCE_KEYS[name],
            "legacyExtraCharacters": "".join(sorted(characters - set(REFERENCE_KEYS[name]))),
            "nonASCIIOptions": sum(not w.isascii() for w in words),
            "jointCategories": dict(Counter(map(category, words))),
            "phraseHeadwordOptions": sum(" " in w for w in words),
            "tatoebaObservedPhrases": sum(" " in w and w in phrases for w in words),
            "wholeObserved": sum(w.lower() in bands for w in words),
            "wordsSHA256": sha(("\n".join(words) + "\n").encode())}
    output[MANIFEST] = (json.dumps(doc, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode()
    return output


def verify_bundled(root):
    require(bool(PUBLISHED), "immutable artifact pins required")
    for name, digest in PUBLISHED.items():
        require(sha((root / name).read_bytes()) == digest, "artifact pin mismatch: " + name)
    doc = json.loads((root / MANIFEST).read_text())
    require(doc["revision"] == REVISION, "revision mismatch")
    for name, digest in doc["artifacts"].items():
        require(sha((root / name).read_bytes()) == digest, "manifest mismatch")
    pools = {("basic" if name == "basic" else name[5:]): text.splitlines()
             for name, text in re.findall(r'static let (basic|words1k|words5k): \[String\] = """\n(.*?)\n"""',
                                         (root / SWIFT).read_text(), re.S)}
    require(list(pools) == list(SPECS), "missing native pools")
    rows = [line.split("\t") for line in (root / ROWS).read_text().splitlines() if not line.startswith("#")]
    require(all(len(row) == 8 and row[1] in {"dictionary", "typebar-legacy"} and row[2]
                and (row[3] == "NA" or row[3].isdigit())
                and row[4] == ("whole-phrase" if " " in row[0] else "not-queried")
                and ((row[5:8] == ["NA", "NA", "NA"]) or
                     (" " in row[0] and row[5].isdigit() and int(row[5]) > 0
                      and row[6].isdigit() and bool(row[7])))
                and (" " not in row[0] or row[0] == row[2]) for row in rows), "invalid provenance")
    provenance = {row[0]: row for row in rows}
    require(len(rows) == len(provenance) and set(provenance) == set().union(*map(set, pools.values())), "incomplete provenance")
    for name, words in pools.items():
        count, maximum = SPECS[name]
        require(len(words) == len(set(words)) == count and set(LEGACY) <= set(words), "count/legacy mismatch")
        require(set(pools["basic"]) <= set(words), "basic vocabulary not retained")
        require(all(literal(w) for w in words) and min(map(len, words)) == 1
                and max(map(len, words)) == maximum, "literal/length mismatch")
        require(set("".join(words)) == set(REFERENCE_KEYS[name]), "typing key mismatch")
        require(dict(Counter(map(category, words))) == CATEGORIES[name], "category mismatch")
        require(doc["pools"][name]["wordsSHA256"] == sha(("\n".join(words) + "\n").encode()), "pool pin mismatch")
        require(doc["pools"][name]["wholeObserved"] == sum(provenance[w][3] != "NA" for w in words), "observation mismatch")



class ContractTests(unittest.TestCase):
    def test_literal_preserves_turkish_letters_case_and_real_phrase_separators(self):
        for word in ["ışık", "kağıt", "Hüseyin", "bir göz at", "jandarma"]:
            self.assertTrue(literal(word))
        for word in ["e\u0301", "İstanbul", "iki  söz", " üç", "qtr01", "iki-söz", ""]:
            self.assertFalse(literal(word))

    def test_source_filter_rejects_wrong_language_bad_senses_and_romanization(self):
        forms = {}
        entry = {"lang_code": "tr", "pos": "noun", "word": "yağmur", "senses": [{"tags": ["nonstandard"]}]}
        collect(entry, forms)
        self.assertFalse(forms)
        entry["senses"].append({})
        entry["forms"] = [{"form": "abc", "tags": ["romanization"]}, {"form": "iki söz"}]
        collect(entry, forms)
        self.assertEqual(forms, {"yağmur": ("dictionary", "yağmur")})
        collect({"lang_code": "vi", "pos": "noun", "word": "abc", "senses": [{}]}, forms)
        self.assertNotIn("abc", forms)
        collect({"lang_code": "tr", "pos": "phrase", "word": "iki söz", "senses": [{}]}, forms)
        self.assertEqual(forms["iki söz"], ("dictionary", "iki söz"))

    def test_phrase_observations_keep_turkish_case_and_exact_boundaries(self):
        phrases = {"ışık var", "iyi gün", "ne yazık ki"}
        self.assertEqual(turkish_lower("Iİıi"), "ıiıi")
        self.assertEqual(phrase_matches("IŞIK var. İYİ gün! ne yazık ki; ne yazık ki.", phrases), phrases)
        for text in ["Iyi gün", "ne  yazık ki", "ne, yazık ki", "ne\tyazık ki", "ne yazık ki2",
                     "ne yazık kı", "ne yazık ki\u0307", "ne_yazık_ki", "ne yazık kiç"]:
            self.assertFalse(phrase_matches(text, phrases), text)

    def test_phrase_ranking_uses_observations_without_component_estimates(self):
        counts = {"iki söz": 2, "bir söz": 8}
        self.assertLess(priority("bir söz", {}, counts), priority("iki söz", {}, counts))
        self.assertLess(priority("iki söz", {}, counts), priority("üç söz", {}, counts))
        self.assertEqual(priority("üç söz", {"üç": 0, "söz": 0}, {})[0], True)

    def test_selection_preserves_joint_quotas_without_synthesizing_forms(self):
        words = choose({"a", "ab", "b", "ş", "bş"}, {"a"}, 4, 2,
            {"0/0/0": 2, "1/0/0": 2}, set("abş"), {"ş": 0, "b": 1})
        self.assertEqual(len(words), 4)
        self.assertIn("a", words)
        self.assertEqual(set("".join(words)), set("abş"))
        self.assertEqual(category("bir göz at"), "1/0/2")
        self.assertEqual(category("Hüseyin"), "1/1/0")
        self.assertLess(priority("ş", {"ş": 0}), priority("a", {"ş": 0}))
        with self.assertRaises(ValueError):
            choose({"a", "ş"}, set(), 4, 2, {"0/0/0": 2, "1/0/0": 2}, set("abş"), {})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dictionary", type=Path)
    parser.add_argument("--wordfreq-wheel", type=Path)
    parser.add_argument("--sentences", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--check-bundled", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        result = unittest.TextTestRunner().run(unittest.defaultTestLoader.loadTestsFromTestCase(ContractTests))
        raise SystemExit(not result.wasSuccessful())
    if args.check_bundled:
        verify_bundled(ROOT)
        print("Turkish pinned corpus/provenance check passed")
        return
    require(args.dictionary and args.wordfreq_wheel and args.sentences and args.output,
            "dictionary, wheel, sentence snapshot and output directory are required")
    output = artifacts(args.dictionary, args.wordfreq_wheel, args.sentences)
    if PUBLISHED:
        require({name: sha(data) for name, data in output.items()} == PUBLISHED, "reproduction pins mismatch")
    for name, data in output.items():
        path = args.output / name
        if args.check:
            require(path.read_bytes() == data, "source reproduction mismatch: " + name)
        else:
            require(not path.exists(), "refusing to overwrite artifact: " + name)
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
    print("Turkish source reproduction checked" if args.check else "Turkish corpus prepared")


if __name__ == "__main__":
    main()
