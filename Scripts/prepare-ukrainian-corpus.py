#!/usr/bin/env python3
"""Prepare independently sourced Ukrainian spellings, retaining every adaptation."""
import argparse
from collections import Counter
import gzip
import hashlib
import json
from pathlib import Path
import re
import unicodedata
import unittest
import zipfile

SOURCE_URL = "https://kaikki.org/dictionary/Ukrainian/kaikki.org-dictionary-Ukrainian.jsonl"
SOURCE_SHA = "31e8e39f48feae391478f1fe2c37d003053cf88f2dd4f2d97d5d19c7bc432a90"
RU_SOURCE_URL = "https://kaikki.org/dictionary/downloads/ru/ru-extract.jsonl.gz"
RU_SOURCE_SHA = "7e30fc4e4b21ff16cde09a501494f25287ae66f9a0f94e770ae826e5003c7698"
WHEEL_SHA = "4b1c6ecffc6198be3396d5cf871c4423ca71c907c231348d352dd54d62b97473"
MEMBER = "wordfreq/data/large_uk.msgpack.gz"
MEMBER_SHA = "0a7d525ef5b9d2c84cd3ccd1064b02eb6a07232e5d1e465df40cc00168fdaac2"
EVIDENCE = Path("Compatibility/ukrainian-boundary-evidence.json")
EVIDENCE_SHA = "52cc152df8ad908bd34da16258cb74b5f0d1b5213ab79794208944249f5bfc7d"
REVISION = "kaikki-en-uk-20261030-stress-trace-wordfreq-v1"
LOWER = frozenset("абвгґдеєжзиіїйклмнопрстуфхцчшщьюя")
ALPHABET = LOWER | {c.upper() for c in LOWER} | set("0123456789'-")
VOWELS = frozenset("аеєиіїоуюяАЕЄИІЇОУЮЯ")
PARTS = set("noun name verb adj adv article pron det conj intj interj prep postp num particle phrase abbrev participle gerund contraction onomatopoeia onomatopeia prep_phrase".split())
SPECS = {
    "basic": {"L": (199, 1, 12)},
    "1k": {"L": (985, 1, 16), "P": (15, 4, 18)},
    "10k": {"L": (9788, 1, 22), "P": (210, 4, 30)},
    "50k": {"L": (48004, 1, 23), "P": (1975, 4, 31), "C": (7, 2, 4), "PN": (2, 6, 7), "CP": (3, 7, 12)},
}
PUNCTUATION_QUOTAS = {
    "1k": {"'": 13, "-": 2},
    "10k": {"'": 126, "-": 80, "'-": 3, "'--": 1},
    "50k": {"'": 631, "-": 1296, "'-": 25, "'--": 3, "--": 19, "''-": 1},
}
LEGACY = "ранок вікно папір берег вітер вправа увага спокій ясно озеро вулиця стіл світло дорога терпіння хвилина місто дощ тиша напрямок зірка нотатка сад подих їжа єдність ґрунт".split()
RESERVED = list(dict.fromkeys(LEGACY + ["мова", "практика"]))
SWIFT = Path("Sources/Typebar/UkrainianCorpus.generated.swift")
NOTICE = Path("Resources/UkrainianCorpusNotices.txt")
ROWS = Path("Resources/UkrainianCorpusSources.txt")
MANIFEST = Path("Compatibility/ukrainian-corpus.json")
PUBLISHED = {
    str(SWIFT): "321c2e2994779b2a195c9c881acd3f9f61f6192c31ebd33ce0da44fab10dc0bb",
    str(NOTICE): "3535ebf9215e068656825fe9f62949099108d1bca9567559acdabb115c744024",
    str(ROWS): "34cf1897b6864b3b121bac034b8392afbdb2b6f5ae6e3f74d8e89a242a149f89",
}
MANIFEST_SHA = "69738f24cd00ba3fea025ae3677686d763532196d459ec83ee928ee17e1b36ab"


def require(value, message):
    if not value:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def file_sha(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def spelling(raw):
    """Only remove U+0301 directly following a Ukrainian vowel; never fold ї/й."""
    if type(raw) is not str or not raw or len(raw) > 140:
        return None
    result = []
    for index, character in enumerate(raw):
        if character == "\u0301":
            if index == 0 or raw[index - 1] not in VOWELS:
                return None
        else:
            result.append(character)
    word = "".join(result)
    if (1 <= len(word) <= 70 and set(word) <= ALPHABET
        and word == unicodedata.normalize("NFC", word)
        and any(c.lower() in LOWER for c in word)
        and not word.startswith("-") and not word.endswith("-")):
        return word
    return None


def input_class(word):
    return "".join(k for k, yes in [("C", any(c.isupper() for c in word)),
        ("P", any(unicodedata.category(c).startswith("P") for c in word)),
        ("N", any(c.isdigit() for c in word))] if yes) or "L"


def collect_entry(item, forms, edition="dictionary"):
    require(type(item) is dict, "entry must be an object")
    if item.get("lang_code") != "uk" or item.get("pos") not in PARTS:
        return
    lemma = item.get("word")
    require(type(lemma) is str and lemma and not any(c in lemma for c in "\t\r\n"), "invalid dictionary title")
    entries = item.get("forms", [])
    require(type(entries) is list, "invalid forms array")
    for form in [{"form": lemma, "tags": []}] + entries:
        require(type(form) is dict and type(form.get("form")) is str, "invalid form object")
        tags = form.get("tags", [])
        require(type(tags) is list and all(type(t) is str for t in tags), "invalid form tags")
        if any(t in {"table-tags", "inflection-template", "romanization", "class"} or t.startswith("error-") for t in tags):
            continue
        raw = form["form"]
        word = spelling(raw)
        if word is None:
            continue
        candidate = (edition, lemma, raw)
        old = forms.get(word)
        if old is None or (raw != word, lemma != word, len(lemma), lemma, raw, edition) < (old[2] != word, old[1] != word, len(old[1]), old[1], old[2], old[0]):
            forms[word] = candidate


def read_dictionary(path, ru_path):
    require(unicodedata.unidata_version == "15.0.0", "preparation requires Unicode 15.0.0")
    require(file_sha(path) == SOURCE_SHA, "Ukrainian dictionary snapshot mismatch")
    forms, count = {}, 0
    with path.open(encoding="utf-8") as f:
        for line in f:
            collect_entry(json.loads(line), forms)
            count += 1
    require(file_sha(ru_path) == RU_SOURCE_SHA, "Russian-edition snapshot mismatch")
    ru_rows = 0
    with gzip.open(ru_path, "rt", encoding="utf-8") as f:
        for line in f:
            collect_entry(json.loads(line), forms, "ru-dictionary")
            ru_rows += 1
    return forms, {"englishEdition": count, "russianEdition": ru_rows}


def read_boundaries(path, forms):
    require(file_sha(path) == EVIDENCE_SHA, "curated text evidence immutable pin mismatch")
    evidence = json.loads(path.read_text())
    require(evidence["schemaVersion"] == 1, "unsupported curated evidence")
    added = []
    for source in evidence["sources"]:
        require(source["url"].startswith("https://uk.wikipedia.org/w/index.php?") and "&oldid=" in source["url"], "unpinned text source")
        for word in source["tokens"]:
            require(spelling(word) == word and any(re.search(r"(?<![\w'-])" + re.escape(word) + r"(?![\w'-])", excerpt) for excerpt in source["excerpts"]), "token absent from verified excerpt")
            if word not in forms:
                forms[word] = ("curated-text", source["url"], word)
            added.append(word)
    require(len(added) == len(set(added)) == 4, "four independently evidenced boundaries required")
    return evidence


def read_frequency(path):
    require(file_sha(path) == WHEEL_SHA, "wordfreq wheel mismatch")
    import msgpack
    require(msgpack.__version__ == "1.1.2", "preparation requires msgpack 1.1.2")
    with zipfile.ZipFile(path) as archive:
        packed = archive.read(MEMBER)
        metadata = archive.read("wordfreq-3.1.1.dist-info/METADATA").decode()
    require(sha(packed) == MEMBER_SHA, "Ukrainian frequency member mismatch")
    bins = msgpack.unpackb(gzip.decompress(packed), raw=False)
    require(type(bins) is list and bins[0] == {"format": "cB", "version": 1}, "unsupported frequency format")
    bands = {}
    for band, words in enumerate(bins[1:]):
        require(type(words) is list and all(type(w) is str for w in words) and words == sorted(set(words)), "invalid frequency bin")
        for word in words:
            require(word not in bands, "duplicate frequency token")
            bands[word] = band
    require("## License" in metadata, "release license missing")
    return bands, metadata[metadata.index("## License"):].strip() + "\n"


def observation(word, bands):
    whole = bands.get(word.casefold())
    parts = [p for p in re.split("[-']", word.casefold()) if p]
    component = max((bands.get(p, 10**9) for p in parts), default=10**9) if len(parts) > 1 else 10**9
    return whole, component if component != 10**9 else None


def priority(word, bands):
    whole, component = observation(word, bands)
    return (0, whole, word.casefold(), word) if whole is not None else (1, component, word.casefold(), word) if component is not None else (2, 0, word.casefold(), word)


def select_group(candidates, spec, bands, required):
    count, minimum, maximum = spec
    ordered = sorted({w for w in candidates if minimum <= len(w) <= maximum}, key=lambda w: priority(w, bands))
    chosen = set(required)
    require(chosen <= set(ordered) and len(chosen) <= count and len(ordered) >= count, "insufficient real class candidates")
    for length in {minimum, maximum}:
        if not any(len(w) == length for w in chosen):
            boundary = next((w for w in ordered if len(w) == length), None)
            require(boundary is not None, "literal length boundary missing")
            chosen.add(boundary)
    require(len(chosen) <= count, "required boundaries exceed class count")
    for word in ordered:
        if len(chosen) == count:
            break
        chosen.add(word)
    return sorted(chosen, key=lambda w: priority(w, bands)), len(ordered)


def marks(word):
    return "".join(sorted(c for c in word if unicodedata.category(c).startswith("P")))


def select_punctuation(candidates, spec, bands, required, quotas):
    count, minimum, maximum = spec
    ordered = sorted({w for w in candidates if minimum <= len(w) <= maximum}, key=lambda w: priority(w, bands))
    required = set(required)
    require(required <= set(ordered) and len(ordered) >= count, "insufficient real punctuation forms")
    for length in {minimum, maximum}:
        if not any(len(w) == length for w in required):
            boundary = next((w for w in ordered if len(w) == length), None)
            require(boundary is not None, "punctuation length boundary missing")
            required.add(boundary)
    groups = {}
    for word in ordered:
        groups.setdefault(marks(word), []).append(word)
    allocations = {key: min(len(words), max(quotas.get(key, 0), sum(marks(w) == key for w in required))) for key, words in groups.items()}
    require(sum(allocations.values()) <= count, "required punctuation quotas exceed size")
    remaining = count - sum(allocations.values())
    for word in ordered:
        key = marks(word)
        if remaining and allocations[key] < len(groups[key]):
            allocations[key] += 1
            remaining -= 1
    require(remaining == 0, "insufficient punctuation quota capacity")
    selected = []
    for key, words in groups.items():
        chosen = {w for w in required if marks(w) == key}
        for word in words:
            if len(chosen) == allocations[key]:
                break
            chosen.add(word)
        selected.extend(chosen)
    return sorted(selected, key=lambda w: priority(w, bands)), len(ordered)


def shape(words):
    groups = {}
    for word in words:
        key = input_class(word)
        if key not in groups:
            groups[key] = {"count": 0, "min": len(word), "max": len(word)}
        groups[key]["count"] += 1
        groups[key]["min"] = min(groups[key]["min"], len(word))
        groups[key]["max"] = max(groups[key]["max"], len(word))
    return {"count": len(words), "uniqueCount": len(set(words)), "groups": groups,
        "punctuationScalars": dict(sorted(Counter(c for w in words for c in w if unicodedata.category(c).startswith("P")).items())),
        "maximumHyphens": max((w.count("-") for w in words), default=0)}


def native(pools):
    text = ("// Generated by Scripts/prepare-ukrainian-corpus.py; do not edit.\n"
        "// Independent Wiktionary forms with explicit stress-mark adaptations; four traced Wikipedia tokens.\n"
        "// CC BY-SA 4.0. Full notices and original form spellings are retained.\n"
        "enum UkrainianCorpus {\n" + f'  static let revision = "{REVISION}"\n')
    for name, words in pools.items():
        identifier = "basic" if name == "basic" else "words" + name
        text += f'  static let {identifier}: [String] = """\n' + "\n".join(words) + '\n""".split(separator: "\\n").map(String.init)\n'
    return (text + "}\n").encode()


def artifacts(dictionary, ru_dictionary, wheel, evidence_path):
    forms, source_rows = read_dictionary(dictionary, ru_dictionary)
    evidence = read_boundaries(evidence_path, forms)
    bands, frequency_notice = read_frequency(wheel)
    pools, details, previous = {}, {}, []
    for name, specs in SPECS.items():
        words, capacity = [], {}
        for key, spec in specs.items():
            candidates = [w for w in forms if input_class(w) == key]
            if name == "basic":
                candidates = [w for w in candidates if forms[w][0] != "curated-text" and forms[w][2] == w and w in bands]
            if key == "CP":
                candidates = [w for w in candidates if marks(w) == "-"]
            required = [w for w in (RESERVED if name == "basic" else previous) if input_class(w) == key]
            selected, capacity[key] = (select_punctuation(candidates, spec, bands, required, PUNCTUATION_QUOTAS[name])
                if key == "P" else select_group(candidates, spec, bands, required))
            words.extend(selected)
        words.sort(key=lambda w: priority(w, bands))
        expected = {key: {"count": spec[0], "min": spec[1], "max": spec[2]} for key, spec in specs.items()}
        require(shape(words)["groups"] == expected, "published class boundaries differ")
        require(len(set(words)) == len(words), "duplicate published spelling")
        pools[name] = words
        details[name] = {"shape": shape(words), "eligibleByClass": capacity,
            "stressAdapted": sum(forms[w][0] != "curated-text" and w != forms[w][2] for w in words),
            "curatedText": sum(forms[w][0] == "curated-text" for w in words),
            "dictionaryEditions": dict(Counter(forms[w][0] for w in words)),
            "punctuationSignatures": dict(Counter(marks(w) for w in words if input_class(w) == "P")),
            "wholeObserved": sum(observation(w, bands)[0] is not None for w in words),
            "wordsSHA256": sha(("\n".join(words) + "\n").encode())}
        previous = words
    rows = "# word\tevidenceKind\tsourceTitleOrURL\toriginalForm\twholeTokenBand\tcomponentEstimateBand\n"
    for word in pools["50k"]:
        whole, component = observation(word, bands)
        rows += "\t".join([word, *forms[word], "" if whole is None else str(whole), "" if component is None else str(component)]) + "\n"
    notice = ("Typebar independently prepared Ukrainian corpus\nRevision: " + REVISION + "\n\n"
        "English and Russian Wiktionary contributors; extracted by Kaikki.org / Wiktextract.\n"
        "Source: " + SOURCE_URL + "\nSnapshot SHA-256: " + SOURCE_SHA + "\n"
        "Index reported extraction 2026-10-25, enwiktionary dump 2026-10-01.\n"
        "Additional Russian-edition raw source: " + RU_SOURCE_URL + "\nSHA-256: " + RU_SOURCE_SHA + "\n"
        "Only lang_code=uk entries are selected from both editions, never Russian vocabulary.\n"
        "Entry attribution: https://en.wiktionary.org/wiki/<source title>#Ukrainian\n"
        "or https://ru.wiktionary.org/wiki/<source title> for ru-dictionary rows.\n"
        "Adapted dictionary/text selection: Creative Commons Attribution-ShareAlike 4.0 International.\n"
        "https://creativecommons.org/licenses/by-sa/4.0/\n\n"
        "Changes: remove only vowel-adjacent U+0301 dictionary stress annotations; retain\n"
        "original forms and titles in the per-word mapping. Never strip the letters ї, й, є or ґ,\n"
        "casefold spellings, synthesize suffixes or pad candidate lengths. These adaptations\n"
        "are not represented as unchanged source literals. Basic words use observed literal forms.\n"
        "Four literal text tokens were manually checked in Ukrainian Wikipedia; tokens\n"
        "already present in a dictionary keep their dictionary evidence. These include two\n"
        "long compounds and two numeric forms. The curated evidence contains\n"
        "short transcribed excerpts and pinned revisions, not full downloaded articles.\n")
    for source in evidence["sources"]:
        notice += source["title"] + "\n" + source["url"] + "\n"
    notice += ("\nwordfreq 3.1.1 wheel SHA-256: " + WHEEL_SHA + "\nMember: " + MEMBER
        + "\nMember SHA-256: " + MEMBER_SHA + "\n"
        "Whole-token observations, component estimates and absent observations are distinct.\n"
        "A band is not a usage count; valid inflection tables do not prove real usage.\n"
        "Source/shape matching does not establish original values, frequency distribution,\n"
        "difficulty, modern normative status or language quality. Historical prompts remain literal.\n"
        "No original Monkeytype code, vocabulary values or assets are used in this selection.\n\n"
        "=== wordfreq 3.1.1 release metadata ===\n" + frequency_notice)
    outputs = {SWIFT: native(pools), NOTICE: notice.encode(), ROWS: rows.encode()}
    document = {"schemaVersion": 1, "revision": REVISION, "sourceURL": SOURCE_URL, "sourceSHA256": SOURCE_SHA,
        "sourceRows": source_rows, "literalOrStressAdaptedForms": len(forms), "boundaryEvidenceSHA256": EVIDENCE_SHA,
        "russianEditionSourceURL": RU_SOURCE_URL, "russianEditionSourceSHA256": RU_SOURCE_SHA,
        "referencePunctuationQuotas": PUNCTUATION_QUOTAS,
        "frequencyWheelSHA256": WHEEL_SHA, "frequencyMemberSHA256": MEMBER_SHA, "referenceAggregate": SPECS,
        "pools": details, "retainedAuthored": LEGACY, "runtimeDependencies": [],
        "filesSHA256": {str(k): sha(v) for k, v in outputs.items()}}
    outputs[MANIFEST] = (json.dumps(document, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode()
    return outputs


def verify_pins(hashes):
    require(bool(PUBLISHED) and hashes == PUBLISHED, "immutable published pins required")


def verify_bundled(root):
    require(bool(MANIFEST_SHA) and file_sha(root / MANIFEST) == MANIFEST_SHA, "manifest immutable pin mismatch")
    d = json.loads((root / MANIFEST).read_text())
    require(d["schemaVersion"] == 1 and d["revision"] == REVISION, "unsupported corpus revision")
    verify_pins(d["filesSHA256"])
    for path, digest in PUBLISHED.items():
        require(file_sha(root / path) == digest, "bundled corpus file mismatch: " + path)
    boundary = {}
    read_boundaries(root / EVIDENCE, boundary)
    text = (root / SWIFT).read_text()
    matches = re.findall(r'  static let (basic|words1k|words10k|words50k): \[String\] = """\n(.*?)\n"""', text, re.S)
    names = {"basic": "basic", "words1k": "1k", "words10k": "10k", "words50k": "50k"}
    pools = {names[k]: value.splitlines() for k, value in matches}
    require(len(matches) == len(pools) == 4 and list(pools) == list(SPECS) and native(pools) == text.encode(), "native template mismatch")
    rows = [line.split("\t") for line in (root / ROWS).read_text().splitlines() if not line.startswith("#")]
    require(len(rows) == 49991 and all(len(r) == 6 for r in rows), "incomplete source mapping")
    require([r[0] for r in rows] == pools["50k"], "source row order mismatch")
    mapping = {}
    for word, kind, title, raw, whole, component in rows:
        require(kind in {"dictionary", "ru-dictionary", "curated-text"} and title and spelling(raw) == word, "invalid spelling adaptation trace")
        require(all(not b or b.isdigit() for b in [whole, component]), "invalid observation band")
        if kind == "curated-text":
            require(word in boundary and boundary[word] == (kind, title, raw), "unverified curated text token")
        mapping[word] = (kind, title, raw, whole, component)
    previous = set(LEGACY)
    for name, words in pools.items():
        require(all(spelling(w) == w for w in words) and len(words) == len(set(words)), "invalid modern spelling")
        require(shape(words) == d["pools"][name]["shape"], "content shape mismatch")
        require(shape(words)["groups"] == {k: {"count": v[0], "min": v[1], "max": v[2]} for k, v in SPECS[name].items()}, "class boundary mismatch")
        require(previous <= set(words), "previous authored or smaller pool lost")
        require(d["pools"][name]["wordsSHA256"] == sha(("\n".join(words) + "\n").encode()), "word hash mismatch")
        if name == "basic":
            require(all(mapping[w][0] != "curated-text" and mapping[w][2] == w and mapping[w][3] for w in words), "basic form is not literal/observed")
        previous = set(words)


class Contracts(unittest.TestCase):
    def test_stress_adaptation_retains_ukrainian_letters_and_refuses_other_folds(self):
        self.assertEqual(spelling("ї́жа"), "їжа")
        self.assertEqual(spelling("ґрунт"), "ґрунт")
        self.assertEqual(spelling("йо́го"), "його")
        for word in ["\u0301їжа", "ґ́рунт", "їжа\u0301\u0301", "и\u0306", "ы", "ѣ", "roman", "слово слово"]:
            self.assertIsNone(spelling(word))

    def test_no_padding_and_real_boundaries_required(self):
        with self.assertRaises(ValueError): select_group(["і", "мова"], (3, 1, 4), {}, [])
        with self.assertRaises(ValueError): select_group(["і", "мова"], (2, 1, 5), {}, [])
        self.assertEqual(select_group(["мова", "і"], (2, 1, 4), {"мова": 0}, ["і"])[0], ["мова", "і"])

    def test_romanizations_and_error_forms_do_not_enter_the_dictionary(self):
        forms = {}
        collect_entry({"lang_code": "uk", "pos": "noun", "word": "їжа", "forms": [
            {"form": "їжі́"}, {"form": "їж", "tags": ["error-unrecognized-form"]},
            {"form": "їжаа", "tags": ["romanization"]}]}, forms)
        self.assertEqual(set(forms), {"їжа", "їжі"})
        self.assertEqual(forms["їжі"][2], "їжі́")

    def test_whole_observation_is_not_fabricated_from_components(self):
        self.assertEqual(observation("будь-який", {"будь": 1, "який": 3}), (None, 3))
        self.assertEqual(observation("будь-який", {"будь-який": 8}), (8, None))

    def test_unavailable_punctuation_combination_is_never_invented(self):
        words = ["м'яч", "сім'я", "будь-як", "по-нашому"]
        selected, _ = select_punctuation(words, (3, 4, 9), {}, [], {"'": 1, "-": 1, "''-": 1})
        self.assertEqual(len(selected), 3)
        self.assertTrue(set(selected) <= set(words))
        self.assertNotIn("''-", {marks(w) for w in selected})

    def test_missing_or_mutable_manifest_pins_rejected(self):
        with self.assertRaises(ValueError): verify_pins({})
        with self.assertRaises(ValueError): verify_pins({str(SWIFT): "0" * 64})


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--dictionary", type=Path); p.add_argument("--russian-dictionary", type=Path); p.add_argument("--wordfreq-wheel", type=Path)
    p.add_argument("--boundary-evidence", type=Path, default=Path(__file__).resolve().parents[1] / EVIDENCE)
    p.add_argument("--output-root", type=Path, default=Path(__file__).resolve().parents[1])
    p.add_argument("--self-test", action="store_true"); p.add_argument("--check", action="store_true")
    p.add_argument("--check-bundled", action="store_true")
    a = p.parse_args()
    if a.self_test:
        return 0 if unittest.TextTestRunner().run(unittest.defaultTestLoader.loadTestsFromTestCase(Contracts)).wasSuccessful() else 1
    if a.check_bundled:
        verify_bundled(a.output_root); print("Ukrainian bundled integrity passed"); return 0
    require(a.dictionary and a.russian_dictionary and a.wordfreq_wheel, "two pinned dictionaries and wheel required")
    outputs = artifacts(a.dictionary, a.russian_dictionary, a.wordfreq_wheel, a.boundary_evidence)
    verify_pins({str(k): sha(v) for k, v in outputs.items() if k != MANIFEST})
    require(bool(MANIFEST_SHA) and sha(outputs[MANIFEST]) == MANIFEST_SHA, "manifest immutable pin mismatch")
    if not a.check: require(not any((a.output_root / k).exists() for k in outputs), "refusing to overwrite artifacts")
    for path, data in outputs.items():
        target = a.output_root / path
        if a.check: require(target.read_bytes() == data, "source reproduction mismatch: " + str(path))
        else:
            target.parent.mkdir(parents=True, exist_ok=True); target.write_bytes(data)
    print("Ukrainian source reproduction checked" if a.check else "Ukrainian corpus prepared")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
