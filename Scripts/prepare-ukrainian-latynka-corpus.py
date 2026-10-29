#!/usr/bin/env python3
"""Independently selected, explicitly adapted Ukrainian Latin practice forms."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
PARENT = ROOT / "Scripts/prepare-ukrainian-corpus.py"
PARENT_SHA = "cc669764a43586326a9997356c34aa9254052510c68f6f7ee50828baa9fb0f13"
PAPER_URL = "https://www.qeios.com/read/VH8DLJ/pdf"
PAPER_SHA = "b1cfb854a93130a2d8f0bea4c08d7e997a8568e8885b7bd1e9a6c520cf601fe0"
EVIDENCE = Path("Compatibility/ukrainian-latynka-boundary-evidence.json")
EVIDENCE_SHA = "9eb303b6217b5906b42ed2474b29c43f2e7abb2235e84ee5446acad26677a6ef"
REVISION = "ukrainian-latynka-vakulenko-modern-a-ascii-apostrophe-v1"
SWIFT = Path("Sources/Typebar/UkrainianLatynkaCorpus.generated.swift")
NOTICE = Path("Resources/UkrainianLatynkaCorpusNotices.txt")
ROWS = Path("Resources/UkrainianLatynkaCorpusSources.txt")
MANIFEST = Path("Compatibility/ukrainian-latynka-corpus.json")
PUBLISHED = {
    str(SWIFT): "d7d132e094293c8833add720ef3cd48cec8a7a736f1d1ab2734f5c6d47b54ad4",
    str(ROWS): "a05734486714c45d357d3262a184a2849deb3fbf4aac2404c5dd451a9cef9d49",
    str(NOTICE): "db53b0d8054b33f20541dd93e85055667f315ee2f33ec73e0498312e90cf9666",
}
MANIFEST_SHA = "709863e534fef4619c12ff87753f5abe1aa01744fefb4ec1773b48f5b5b277df"
LETTERS = "абвгґдеєжзиіїйклмнопрстуфхцчшщьюя"
MAPPING = dict(zip(LETTERS, "a b v ğ g d e je ž z y i ï j k l m n o p r s t u f x c č š ŝ j ju ja".split()))
CONSONANTS = frozenset(LETTERS) - set("аеєиіїйоуюяь")
ALLOWED = frozenset("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZïčğŝšžĞ0123456789'-")
SPECS = {
    "basic": {"LA": (143, 1, 13), "LU": (56, 1, 12)},
    "1k": {"LA": (696, 1, 16), "LU": (288, 1, 13), "PA": (16, 5, 18)},
    "10k": {"LA": (6616, 1, 20), "LU": (3168, 1, 22), "PA": (168, 4, 30), "PU": (46, 5, 21)},
    "50k": {"CA": (4, 2, 4), "CPA": (1, 12, 12), "CPU": (2, 7, 8), "CU": (3, 3, 3),
        "LA": (30098, 1, 23), "LU": (17881, 1, 23), "PA": (1216, 4, 31),
        "PNA": (2, 6, 7), "PU": (784, 5, 30)},
}


def require(ok, message):
    if not ok:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def parent():
    require(sha(PARENT.read_bytes()) == PARENT_SHA, "Ukrainian reader immutable pin mismatch")
    spec = importlib.util.spec_from_file_location("typebar_ukrainian_reader", PARENT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def latin(word):
    """Modern-letter subset of Table 9; apostrophe notation explicitly ASCII."""
    result = []
    for index, c in enumerate(word):
        lower = c.lower()
        following = word[index + 1].lower() if index + 1 < len(word) else ""
        previous = word[index - 1].lower() if index else ""
        if lower not in MAPPING:
            require(c in "0123456789'-", "unsupported source character")
            result.append(c)
            continue
        value = MAPPING[lower]
        if lower == "ь" and previous not in CONSONANTS:
            value = "ĵ"
        elif (lower in "йь" and following in {"а", "е", "у"}) or (lower in CONSONANTS and following == "й"):
            value += "'"
        if c.isupper():
            value = value[0].upper() + value[1:]
        result.append(value)
    return "".join(result)


def group(word, module):
    return module.input_class(word) + ("A" if word.isascii() else "U")


def shape(words, module):
    groups = {}
    for word in words:
        groups.setdefault(group(word, module), []).append(len(word))
    return {key: [len(values), min(values), max(values)] for key, values in sorted(groups.items())}


def native(pools):
    result = "// Independently prepared Ukrainian forms; explicit Latynka adaptation.\n"
    result += "// CC BY-SA 4.0. Original spellings and full notices are retained.\n"
    result += "enum UkrainianLatynkaCorpus {\n  static let revision = " + json.dumps(REVISION) + "\n"
    for name, words in pools.items():
        result += '  static let ' + ("basic" if name == "basic" else "words" + name) + ': [String] = """\n'
        result += "\n".join(words) + '\n""".split(separator: "\\n").map(String.init)\n'
    return (result + "}\n").encode()


def read_extra(path, forms, module):
    require(sha(path.read_bytes()) == EVIDENCE_SHA, "Latynka text evidence immutable pin mismatch")
    evidence = json.loads(path.read_text())
    require(evidence["schemaVersion"] == 1 and len(evidence["tokens"]) == 1, "unsupported text evidence")
    require(evidence["url"].startswith("https://uk.wikipedia.org/w/index.php?") and "&oldid=" in evidence["url"], "unpinned text source")
    for word in evidence["tokens"]:
        require(module.spelling(word) == word and re.search(r"(?<![\w'-])" + re.escape(word) + r"(?![\w'-])", evidence["excerpt"]), "literal token absent from excerpt")
        forms.setdefault(word, ("curated-text", evidence["url"], word))
    return evidence


def artifacts(dictionary, russian_dictionary, wheel):
    module = parent()
    forms, source_rows = module.read_dictionary(dictionary, russian_dictionary)
    module.read_boundaries(ROOT / module.EVIDENCE, forms)
    extra = read_extra(ROOT / EVIDENCE, forms, module)
    bands, _ = module.read_frequency(wheel)
    originals = {}
    for word in forms:
        converted = latin(word)
        if not set(converted) <= ALLOWED:
            continue
        require(converted not in originals or originals[converted] == word, "ambiguous adapted spelling")
        originals[converted] = word
    key = lambda value: (*module.priority(originals[value], bands), value)
    pools, details, previous = {}, {}, []
    for name, specs in SPECS.items():
        words, capacities = [], {}
        for kind, (count, minimum, maximum) in specs.items():
            candidates = [v for v, w in originals.items() if group(v, module) == kind and minimum <= len(v) <= maximum]
            if name == "basic":
                candidates = [v for v in candidates if originals[v] in bands and forms[originals[v]][0] != "curated-text" and originals[v] == forms[originals[v]][2]]
            ordered = sorted(candidates, key=key)
            reserved = [latin(w) for w in module.LEGACY] if name == "basic" else previous
            chosen = {v for v in reserved if group(v, module) == kind}
            require(chosen <= set(ordered) and len(chosen) <= count and len(ordered) >= count, "insufficient independently supported class: " + name + "/" + kind)
            for length in {minimum, maximum}:
                if not any(len(v) == length for v in chosen):
                    boundary = next((v for v in ordered if len(v) == length), None)
                    require(boundary is not None, "actual length boundary missing: " + name + "/" + kind)
                    chosen.add(boundary)
            require(len(chosen) <= count, "too many required forms")
            for value in ordered:
                if len(chosen) == count:
                    break
                chosen.add(value)
            words.extend(chosen)
            capacities[kind] = len(ordered)
        words.sort(key=key)
        require(shape(words, module) == {k: list(v) for k, v in specs.items()}, "class shape differs")
        require(set(previous) <= set(words) and len(set(words)) == len(words), "non-nested or duplicate pool")
        pools[name] = words
        details[name] = {"shape": shape(words, module), "eligibleByClass": capacities,
            "sourceCyrillicWholeObserved": sum(module.observation(originals[v], bands)[0] is not None for v in words),
            "sourceStressAdapted": sum(originals[v] != forms[originals[v]][2] for v in words),
            "curatedText": sum(forms[originals[v]][0] == "curated-text" for v in words),
            "wordsSHA256": sha(("\n".join(words) + "\n").encode())}
        previous = words
    rows = "# latinWord\tcyrillicForm\tevidenceKind\tsourceTitleOrURL\toriginalForm\tsourceCyrillicWholeBand\tsourceCyrillicComponentBand\n"
    for value in pools["50k"]:
        word = originals[value]
        whole, component = module.observation(word, bands)
        rows += "\t".join([value, word, *forms[word], "" if whole is None else str(whole), "" if component is None else str(component)]) + "\n"
    base_notice = (ROOT / module.NOTICE).read_bytes()
    require(sha(base_notice) == module.PUBLISHED[str(module.NOTICE)], "parent notice immutable pin mismatch")
    notice = ("Typebar independently prepared Ukrainian Latynka corpus\nRevision: " + REVISION + "\n\n"
        "Every Latin practice form is an explicit adaptation, not an observed Latin usage.\n"
        "Romanization decisions independently implemented from Maksym O. Vakulenko,\n"
        "Reversible transliteration of the historical Ukrainian alphabets, DOI 10.32388/VH8DLJ,\n"
        "Table 9 (modern letters), PDF pages 34-35. " + PAPER_URL + "\n"
        "Research PDF SHA-256: " + PAPER_SHA + "\n"
        "Only modern letters are used. The table's apostrophe notation is explicitly ASCII U+0027;\n"
        "existing ASCII source apostrophes and hyphens are preserved. Isolated soft signs\n"
        "and capital diacritics absent from the supported practice alphabet are excluded.\n"
        "This is a documented practice adaptation, not a claim of certified DSTU compliance.\n"
        "Original Cyrillic forms, source edition and any stress adaptation remain traceable.\n"
        "Frequency bands describe the Cyrillic source only, never observed Latin frequency.\n"
        "A band is not a count; empty fields mean absent observation.\n"
        "Additional literal source: Ukrainian Wikipedia contributors, CC BY-SA 4.0.\n"
        + extra["title"] + "\n" + extra["url"] + "\n"
        "The evidence is a short manually checked excerpt, not a complete article snapshot.\n\n").encode() + base_notice
    outputs = {SWIFT: native(pools), ROWS: rows.encode(), NOTICE: notice}
    document = {"schemaVersion": 1, "revision": REVISION, "parentReaderSHA256": PARENT_SHA,
        "dictionarySHA256": module.SOURCE_SHA, "russianDictionarySHA256": module.RU_SOURCE_SHA,
        "wordfreqWheelSHA256": module.WHEEL_SHA, "sourceRows": source_rows,
        "evidenceSHA256": EVIDENCE_SHA, "paperURL": PAPER_URL, "paperSHA256": PAPER_SHA,
        "mapping": MAPPING, "frequencyBasis": "Cyrillic source observations; all Latin forms are adaptations",
        "pools": details, "artifacts": {str(p): sha(b) for p, b in outputs.items()}}
    outputs[MANIFEST] = (json.dumps(document, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode()
    return outputs


def verify_bundled(root):
    module = parent()
    require(bool(PUBLISHED) and sha((root / MANIFEST).read_bytes()) == MANIFEST_SHA, "immutable manifest pin mismatch")
    d = json.loads((root / MANIFEST).read_text())
    require(d["schemaVersion"] == 1 and d["revision"] == REVISION and d["mapping"] == MAPPING, "unsupported adaptation revision")
    require(d["artifacts"] == PUBLISHED, "untrusted artifact manifest")
    require(sha((ROOT / EVIDENCE).read_bytes()) == EVIDENCE_SHA, "text evidence pin mismatch")
    for p, digest in PUBLISHED.items():
        require(sha((root / p).read_bytes()) == digest, "artifact immutable pin mismatch: " + p)
    text = (root / SWIFT).read_text()
    matches = re.findall(r'static let (basic|words1k|words10k|words50k): \[String\] = """\n(.*?)\n"""', text, re.S)
    pools = {("basic" if k == "basic" else k[5:]): v.splitlines() for k, v in matches}
    require(len(matches) == len(pools) == 4 and list(pools) == list(SPECS) and native(pools) == text.encode(), "native template mismatch")
    previous = set()
    for name, words in pools.items():
        require(shape(words, module) == {k: list(v) for k, v in SPECS[name].items()}, "class boundaries differ")
        require(len(words) == len(set(words)) and previous <= set(words), "duplicate or non-nested pool")
        require(all(set(w) <= ALLOWED for w in words), "unsupported practice alphabet")
        require(sha(("\n".join(words) + "\n").encode()) == d["pools"][name]["wordsSHA256"], "pool pin mismatch")
        previous = set(words)
    rows = [line.split("\t") for line in (root / ROWS).read_text().splitlines() if not line.startswith("#")]
    require(len(rows) == 49991 and all(len(r) == 7 for r in rows), "incomplete source mapping")
    require([r[0] for r in rows] == pools["50k"], "source order mismatch")
    for value, cyrillic, kind, title, raw, whole, component in rows:
        require(module.spelling(raw) == cyrillic and latin(cyrillic) == value, "adaptation trace mismatch")
        require(kind in {"dictionary", "ru-dictionary", "curated-text"} and bool(title), "source edition missing")
        require(all(not x or x.isdigit() for x in [whole, component]), "invalid source frequency band")
    print("Ukrainian Latynka bundled integrity passed")


class Contracts(unittest.TestCase):
    def test_modern_alphabet(self):
        self.assertEqual(latin(LETTERS), "abvğgdeježzyiïjklmnoprstufxcčšŝjjuja")
        self.assertEqual(latin("ГҐЇЄЖЧШЩ"), "ĞGÏJeŽČŠŜ")

    def test_ordinary_forms(self):
        for source, expected in {"берег": "bereğ", "їжа": "ïža", "дощ": "doŝ", "спокій": "spokij", "ясно": "jasno", "ґрунт": "grunt"}.items():
            self.assertEqual(latin(source), expected)

    def test_context_preserves_distinctions(self):
        self.assertEqual(latin("бйа"), "b'j'a")
        self.assertEqual(latin("бья"), "bjja")
        self.assertEqual(latin("йе"), "j'e")
        self.assertEqual(latin("є"), "je")
        self.assertEqual(latin("альфа"), "aljfa")

    def test_isolated_soft_sign_is_explicitly_ineligible(self):
        self.assertEqual(latin("ь"), "ĵ")
        self.assertFalse(set(latin("ь")) <= ALLOWED)

    def test_literal_punctuation_and_digits(self):
        self.assertEqual(latin("п'ять"), "p'jatj")
        self.assertEqual(latin("1990-ті"), "1990-ti")
        self.assertEqual(latin("адміністративно-територіальними"), "administratyvno-terytorialjnymy")

    def test_unsupported_input_is_rejected(self):
        for word in ["test", "мова мова", "ё", "ді́м", "п’ять"]:
            with self.assertRaises(ValueError):
                latin(word)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--self-test", action="store_true")
    p.add_argument("--check-bundled", action="store_true")
    p.add_argument("--check", action="store_true")
    p.add_argument("--dictionary", type=Path)
    p.add_argument("--russian-dictionary", type=Path)
    p.add_argument("--wordfreq-wheel", type=Path)
    p.add_argument("--output-root", type=Path, default=ROOT)
    a = p.parse_args()
    if a.self_test:
        return 0 if unittest.TextTestRunner().run(unittest.defaultTestLoader.loadTestsFromTestCase(Contracts)).wasSuccessful() else 1
    if a.check_bundled:
        verify_bundled(a.output_root)
        return 0
    require(a.dictionary and a.russian_dictionary and a.wordfreq_wheel, "pinned dictionaries and wheel required")
    outputs = artifacts(a.dictionary, a.russian_dictionary, a.wordfreq_wheel)
    require(bool(PUBLISHED) and {str(p): sha(b) for p, b in outputs.items() if p != MANIFEST} == PUBLISHED, "immutable artifact pins required")
    require(sha(outputs[MANIFEST]) == MANIFEST_SHA, "immutable manifest pin mismatch")
    if not a.check:
        require(not any((a.output_root / p).exists() for p in outputs), "refusing to overwrite artifacts")
    for path, data in outputs.items():
        target = a.output_root / path
        if a.check:
            require(target.read_bytes() == data, "source reproduction mismatch: " + str(path))
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
    print("Ukrainian Latynka source reproduction checked" if a.check else "Ukrainian Latynka corpus prepared")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
