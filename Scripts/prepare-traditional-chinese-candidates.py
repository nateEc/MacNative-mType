#!/usr/bin/env python3
"""Read literal traditional CC-CEDICT forms, never converting the simplified pool."""
import argparse
from collections import Counter
import csv
import gzip
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

SPEC = importlib.util.spec_from_file_location("independent_cedict_reader", Path(__file__).with_name("prepare-simplified-chinese-candidates.py"))
BASE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BASE)
LEGACY = "晨霧 海灣 筆記 微雨 松林 專注 緩步 清楚 河岸 茶香 街燈 木門 書頁 旅途 耐心 片刻 山徑 風鈴 安靜 方向 星群 畫布 庭院 呼吸".split()


def literal(word):
    return 1 <= len(word) <= 9 and all("\u3400" <= c <= "\u9fff" for c in word)


def collect(line, number, bands, candidates):
    traditional, simplified, pinyin, senses = BASE.parse_row(line)
    if not literal(traditional) or all(BASE.VARIANT.match(sense) for sense in senses):
        return
    record = dict(word=traditional, simplifiedSourceForm=simplified, pinyin=pinyin,
                  sourceLine=number, targetRawBand=bands.get(traditional),
                  simplifiedSourceBand=bands.get(simplified))
    previous = candidates.get(traditional)
    # Rank only by an explicitly labelled source-form observation, then source row.
    key = lambda row: (row["simplifiedSourceBand"] is None,
                       row["simplifiedSourceBand"] or 0, row["sourceLine"])
    if previous is None or key(record) < key(previous):
        candidates[traditional] = record


def stage(source, frequency, output):
    BASE.require(not output.exists(), "refusing to overwrite staged evidence")
    data = source.read_bytes()
    BASE.require(BASE.sha(data) == BASE.SOURCE_SHA, "dictionary archive pin mismatch")
    raw = gzip.decompress(data)
    BASE.require(BASE.sha(raw) == BASE.RAW_SHA, "dictionary text pin mismatch")
    bands = BASE.read_frequency(frequency)
    candidates, count = {}, 0
    for number, line in enumerate(raw.decode("utf-8").splitlines(), 1):
        if line and not line.startswith("#"):
            collect(line, number, bands, candidates)
            count += 1
    BASE.require(count == 125324, "dictionary entry count mismatch")
    records = sorted(candidates.values(), key=lambda row: (
        row["simplifiedSourceBand"] is None, row["simplifiedSourceBand"] or 0, row["word"]))
    rows = "word\tsimplifiedSourceForm\tpinyin\tsourceLine\ttargetRawBand\tsimplifiedSourceBand\n"
    rows += "".join("\t".join(str(row[k]) if row[k] is not None else "-" for k in
        ["word", "simplifiedSourceForm", "pinyin", "sourceLine", "targetRawBand", "simplifiedSourceBand"]) + "\n" for row in records)
    report = dict(status="traditional-candidates-not-installed", sourceURL=BASE.SOURCE_URL,
                  sourceSHA256=BASE.SOURCE_SHA, rawSHA256=BASE.RAW_SHA,
                  frequencyWheelSHA256=BASE.WHEEL_SHA, frequencyMemberSHA256=BASE.MEMBER_SHA,
                  candidateCount=len(records), singleCharacterCandidates=sum(len(w) == 1 for w in candidates),
                  exactTraditionalRawKeys=sum(r["targetRawBand"] is not None for r in records),
                  observedSimplifiedSourceKeys=sum(r["simplifiedSourceBand"] is not None for r in records),
                  legacyDictionaryAttested=[w for w in LEGACY if w in candidates],
                  legacyAuthoredWithoutDictionaryEvidence=[w for w in LEGACY if w not in candidates],
                  rowsSHA256=BASE.sha(rows.encode()),
                  observationScope="Traditional raw key and simplified source-form key are separate; neither is a segmentation/transliteration parity claim")
    output.mkdir(parents=True)
    (output / "candidate-sources.tsv").write_text(rows, encoding="utf-8")
    (output / "audit.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return report


def select_pools(source, frequency, output):
    records = list(csv.DictReader((output / "candidate-sources.tsv").open(encoding="utf-8"), delimiter="\t"))
    candidates = {r["word"]: r for r in records}
    ranked = [r["word"] for r in records]
    target_bands = BASE.read_frequency(frequency)
    basic = [w for w in ranked if len(w) == 1][:60] + list(LEGACY)
    basic += [w for w in ranked if len(w) == 3][:2]
    for word in ranked:
        if len(basic) == 200:
            break
        if len(word) == 2 and word not in basic:
            basic.append(word)
    BASE.require(Counter(map(len, basic)) == {1: 60, 2: 138, 3: 2}, "basic length distribution failure")
    pools = {"basic": basic}
    distributions = {"1k": {2: 986, 3: 11, 4: 2, 5: 1},
                     "5k": {2: 4624, 3: 278, 4: 77, 5: 10, 6: 2},
                     "10k": {2: 9022, 3: 685, 4: 246, 5: 15, 6: 5, 7: 1},
                     "50k": {1: 1, 2: 38062, 3: 6125, 4: 5591, 5: 102, 6: 28, 7: 6, 9: 10}}
    selected = [w for w in basic if len(w) > 1]
    raw = source.read_bytes()
    BASE.require(BASE.sha(raw) == BASE.SOURCE_SHA, "boundary dictionary pin mismatch")
    dictionary = {}
    for line_number, line in enumerate(gzip.decompress(raw).decode("utf-8").splitlines(), 1):
        if line and not line.startswith("#"):
            traditional, simplified, pinyin, senses = BASE.parse_row(line)
            if any(not BASE.VARIANT.match(sense) for sense in senses):
                dictionary.setdefault(traditional, (simplified, line_number))
    boundaries = {}
    def boundary(original, word, kind):
        BASE.require(original in dictionary, "boundary source absent")
        simplified, number = dictionary[original]
        boundaries[word] = dict(sourceForm=original, simplifiedSourceForm=simplified,
                                sourceLine=number, kind=kind, targetRawBand=target_bands.get(word),
                                simplifiedSourceBand=target_bands.get(simplified))
    boundary("卡拉OK", "卡拉ＯＫ", "explicit fullwidth Latin writing adaptation")
    boundary("阿Q", "阿Ｑ", "explicit fullwidth Latin writing adaptation")
    commas = sorted(w for w in dictionary if 2 <= len(w) <= 9 and len(w) != 8 and "，" in w
                    and any(c in "一二三四五六七八九十" for c in w)
                    and all("\u3400" <= c <= "\u9fff" or c == "，" for c in w))
    BASE.require(len(commas) >= 3, "literal comma source capacity insufficient")
    for word in commas[:3]:
        boundary(word, word, "literal")
    boundary(commas[0], commas[0].replace("，", ","), "explicit ASCII-comma writing adaptation")
    dots = sorted(w for w in dictionary if 2 <= len(w) <= 9 and len(w) != 8 and "·" in w
                  and not any(c.isnumeric() for c in w)
                  and all("\u3400" <= c <= "\u9fff" or c == "·" for c in w))
    BASE.require(len(dots) >= 7, "literal middle-dot source capacity insufficient")
    for word in dots[:7]:
        boundary(word, word, "literal")
    for name, count, maximum, alphabet in [("1k", 1000, 5, 779), ("5k", 4991, 6, 1879),
                                           ("10k", 9974, 7, 2652), ("50k", 49925, 9, 4978)]:
        protected = set(selected)
        if name == "50k":
            selected += [basic[0]] + list(boundaries)
            protected.update(boundaries)
            protected.add(basic[0])
        quotas = distributions[name]
        lengths = Counter(map(len, selected))
        BASE.require(all(lengths[n] <= quotas.get(n, 0) for n in lengths), f"{name}: protected lengths {dict(lengths)} exceed {quotas}")
        present = set(selected)
        for word in ranked:
            if len(selected) == count:
                break
            if 2 <= len(word) <= maximum and lengths[len(word)] < quotas.get(len(word), 0) and word not in present:
                selected.append(word)
                present.add(word)
                lengths[len(word)] += 1
        letters = Counter("".join(selected))
        for word in ranked:
            if len(letters) >= alphabet:
                break
            if word in present or len(word) not in quotas or len(word) == 1 or candidates[word]["simplifiedSourceBand"] == "-" or set(word) <= letters.keys():
                continue
            for index in range(len(selected) - 1, -1, -1):
                removed = selected[index]
                counts = Counter(removed)
                if len(removed) == len(word) and removed not in protected and all(letters[c] > n for c, n in counts.items()):
                    letters.subtract(counts)
                    letters.update(word)
                    selected[index] = word
                    present.remove(removed)
                    present.add(word)
                    break
            # A protected or unique-character term may exhaust this length's
            # replacement slots; another real source length can still add coverage.
        BASE.require(len(selected) == len(set(selected)) == count and len(letters) >= alphabet, "pool coverage failure")
        BASE.require(max(map(len, selected)) == maximum and min(map(len, selected)) == (1 if name == "50k" else 2), "pool length failure")
        BASE.require(Counter(map(len, selected)) == quotas, "pool length distribution failure")
        pools[name] = selected.copy()
    report = dict(status="traditional-selected-not-installed", boundarySources=boundaries,
                  legacyAuthoredWithoutDictionaryEvidence=[w for w in LEGACY if w not in candidates], pools={})
    for name, words in pools.items():
        text = "\n".join(words) + "\n"
        (output / (name + ".txt")).write_text(text, encoding="utf-8")
        report["pools"][name] = dict(count=len(words), alphabetCount=len(set("".join(words))),
                                    lengthDistribution=dict(sorted(Counter(map(len, words)).items())),
                                    targetRawObservations=sum(w in target_bands for w in words),
                                    sha256=BASE.sha(text.encode()))
    provenance = ["word\tkind\tsourceForm\tsimplifiedSourceForm\tsourceLine\ttargetRawBand\tsimplifiedSourceBand"]
    for word in dict.fromkeys(pools["50k"] + basic):
        if word in boundaries:
            row = boundaries[word]
        elif word in candidates:
            row = dict(candidates[word], kind="literal", sourceForm=word)
        else:
            BASE.require(word in LEGACY, "unattested term is not authored legacy")
            row = dict(kind="Typebar authored legacy", sourceForm=word, targetRawBand=target_bands.get(word))
        values = [word] + [row.get(k) for k in ["kind", "sourceForm", "simplifiedSourceForm", "sourceLine", "targetRawBand", "simplifiedSourceBand"]]
        provenance.append("\t".join("-" if v is None else str(v) for v in values))
    provenance_text = "\n".join(provenance) + "\n"
    (output / "selected-sources.tsv").write_text(provenance_text, encoding="utf-8")
    report["selectedSourcesSHA256"] = BASE.sha(provenance_text.encode())
    report["uniqueSelectedTerms"] = len(provenance) - 1
    (output / "selection.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return report


def emit_native(source, frequency, output):
    selection = json.loads((output / "selection.json").read_text(encoding="utf-8"))
    pools = {}
    for name, record in selection["pools"].items():
        data = (output / (name + ".txt")).read_bytes()
        BASE.require(BASE.sha(data) == record["sha256"], "selected pool hash mismatch")
        pools[name] = data.decode("utf-8").splitlines()
    for name, count in [("1k", 1000), ("5k", 4991), ("10k", 9974)]:
        BASE.require(pools[name] == pools["50k"][:count], "large native prefix mismatch")
    rows = (output / "selected-sources.tsv").read_bytes()
    BASE.require(BASE.sha(rows) == selection["selectedSourcesSHA256"], "selected provenance hash mismatch")
    BASE.require(BASE.sha(source.read_bytes()) == BASE.SOURCE_SHA, "notice source pin mismatch")
    BASE.read_frequency(frequency)
    revision = "cedict-20261029-traditional-wordfreq-3.1.1-v1"
    swift = "// Independent literal traditional CC-CEDICT selection; no simplified-pool conversion.\n// CC BY-SA 4.0; see TraditionalChineseCorpusNotices.txt and per-word sources.\nenum TraditionalChineseCorpus {\n"
    swift += '  static let revision = "' + revision + '"\n'
    for name, key in [("basic", "basic"), ("allWords", "50k")]:
        swift += '  static let ' + name + ': [String] = """\n' + "\n".join(pools[key]) + '\n""".split(separator: "\\n").map(String.init)\n'
    swift += "  static let words1k = Array(allWords.prefix(1_000))\n  static let words5k = Array(allWords.prefix(4_991))\n  static let words10k = Array(allWords.prefix(9_974))\n}\n"
    with zipfile.ZipFile(frequency) as archive:
        metadata = archive.read("wordfreq-3.1.1.dist-info/METADATA").decode("utf-8")
    BASE.require("## License" in metadata, "frequency license absent")
    header = "\n".join(line for line in gzip.decompress(source.read_bytes()).decode("utf-8").splitlines() if line.startswith("#"))
    notice = ("Typebar independent traditional Chinese practice selection\nRevision: " + revision
              + "\nSource: " + BASE.SOURCE_URL + "\nArchive SHA-256: " + BASE.SOURCE_SHA
              + "\nSelection and writing adaptations: CC BY-SA 4.0.\n"
              + "Six older entries are Typebar-authored, not dictionary-attested.\n"
              + "Two fullwidth Latin adaptations and one ASCII-comma adaptation are explicitly labelled.\n"
              + "Traditional forms are literal dictionary fields, never converted from the simplified pool.\n"
              + "Traditional raw-key and simplified source-form bands are separate observations.\n"
              + "A simplified source-form band is not a measured traditional frequency. - means unknown, not zero.\n"
              + "Original spellings, source line numbers and adaptation kinds are in TraditionalChineseCorpusSources.txt.\n"
              + "No source-project words or assets are used. No identical vocabulary, frequency or normative quality is claimed.\n\n"
              + header + "\n\nwordfreq 3.1.1 — Robyn Speer and contributors\nWheel SHA-256: " + BASE.WHEEL_SHA
              + "\nChinese member SHA-256: " + BASE.MEMBER_SHA + "\n\n" + metadata[metadata.index("## License"):])
    files = {"TraditionalChineseCorpus.generated.swift": swift,
             "TraditionalChineseCorpusSources.txt": rows.decode("utf-8"), "TraditionalChineseCorpusNotices.txt": notice}
    for name, text in files.items():
        BASE.require(not (output / name).exists(), "refusing to overwrite native artifact")
        (output / name).write_text(text, encoding="utf-8")
    (output / "native-files.json").write_text(json.dumps({n: BASE.sha(t.encode()) for n, t in files.items()}, indent=2) + "\n")


class ReaderTests(unittest.TestCase):
    def test_traditional_spelling_and_both_observation_scopes_are_preserved(self):
        result = {}
        collect("測試 测试 [ce4 shi4] /test/", 1, {"测试": 4}, result)
        self.assertEqual(result["測試"]["word"], "測試")
        self.assertIsNone(result["測試"]["targetRawBand"])
        self.assertEqual(result["測試"]["simplifiedSourceBand"], 4)

    def test_multiple_readings_choose_one_real_row_without_mixing_fields(self):
        result = {}
        collect("測試 测试 [ce4 shi4] /test/", 2, {"测试": 4}, result)
        collect("測試 测试 [ce4 shi5] /test/", 3, {"测试": 4}, result)
        self.assertEqual(result["測試"]["sourceLine"], 2)
        self.assertEqual(result["測試"]["pinyin"], "ce4 shi4")

    def test_single_character_allowed_but_bad_or_all_variant_entries_are_rejected(self):
        self.assertTrue(literal("字"))
        self.assertFalse(literal("字" * 10))
        self.assertFalse(literal("Ａ字"))
        result = {}
        collect("測試 测试 [ce4 shi4] /variant of 測試/", 1, {}, result)
        self.assertEqual(result, {})

    def test_changed_source_rejected_before_output_is_created(self):
        with tempfile.TemporaryDirectory() as directory:
            source, output = Path(directory) / "changed.gz", Path(directory) / "out"
            source.write_bytes(gzip.compress(b"changed"))
            with self.assertRaisesRegex(ValueError, "pin mismatch"):
                stage(source, Path(directory) / "missing", output)
            self.assertFalse(output.exists())


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--select", action="store_true")
    parser.add_argument("--emit-native", action="store_true")
    parser.add_argument("--source", type=Path)
    parser.add_argument("--frequency-wheel", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if args.self_test:
        unittest.main(argv=[__file__])
    else:
        BASE.require(all([args.source, args.frequency_wheel, args.output]), "source, frequency wheel and output required")
        result = stage(args.source, args.frequency_wheel, args.output)
        if args.select:
            selection = select_pools(args.source, args.frequency_wheel, args.output)
            print(json.dumps(selection["pools"]))
            if args.emit_native:
                emit_native(args.source, args.frequency_wheel, args.output)
        else:
            BASE.require(not args.emit_native, "native emission requires selection")
        print(json.dumps({k: result[k] for k in ["status", "candidateCount", "exactTraditionalRawKeys", "observedSimplifiedSourceKeys", "rowsSHA256"]}))
