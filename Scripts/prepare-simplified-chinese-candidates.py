#!/usr/bin/env python3
"""Stage independent, literal Chinese candidates; does not install a practice pool."""
import argparse
from collections import Counter
import gzip
import hashlib
import json
from pathlib import Path
import re
import tempfile
import unittest
import zipfile

SOURCE_SHA = "06d0d0e23362867f00ed399a634af016954d14cf3e074b1a937088db6837fb74"
RAW_SHA = "727d728364b8dbb14880f21a242d9a1c3591b855bfb8841d06afa1f2a068cf0d"
WHEEL_SHA = "4b1c6ecffc6198be3396d5cf871c4423ca71c907c231348d352dd54d62b97473"
MEMBER = "wordfreq/data/large_zh.msgpack.gz"
MEMBER_SHA = "e079d7aaff1cfb92874850cb3ffbc7b611af939d9d671c1cbda932d968467cdd"
SOURCE_URL = "https://www.mdbg.net/chinese/export/cedict/cedict_1_0_ts_utf-8_mdbg.txt.gz"
LEGACY = "晨光 窗边 纸张 远山 微风 练习 专注 慢慢 清晰 湖面 街角 木桌 灯影 旅程 耐心 片刻 城市 雨声 安静 方向 星光 消息 花园 呼吸 日常 节奏".split()
ROW = re.compile(r"(\S+) (\S+) \[([^\]]+)\] /(.+)/")
VARIANT = re.compile(r"^(?:(?:old|archaic|erroneous|nonstandard) )?variant of\b|^erroneous form of\b", re.I)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def parse_row(line):
    match = ROW.fullmatch(line)
    require(match is not None, "invalid CC-CEDICT row")
    traditional, simplified, pinyin, meanings = match.groups()
    senses = meanings.split("/")
    require(all(senses) and not any(c in line for c in "\t\r\n\0"), "invalid entry fields")
    return traditional, simplified, pinyin, senses


def eligible(simplified, senses):
    return (2 <= len(simplified) <= 9
            and all("\u3400" <= c <= "\u9fff" for c in simplified)
            and any(not VARIANT.match(sense) for sense in senses))


def read_source(path):
    packed = path.read_bytes()
    require(sha(packed) == SOURCE_SHA, "dictionary archive pin mismatch")
    raw = gzip.decompress(packed)
    require(sha(raw) == RAW_SHA, "dictionary text pin mismatch")
    text = raw.decode("utf-8")
    lines = text.splitlines()
    require("#! entries=125324" in lines and "#! license=https://creativecommons.org/licenses/by-sa/4.0/" in lines,
            "dictionary metadata mismatch")
    candidates, rows = {}, 0
    for number, line in enumerate(lines, 1):
        if not line or line.startswith("#"):
            continue
        traditional, simplified, pinyin, senses = parse_row(line)
        rows += 1
        if eligible(simplified, senses):
            # Keep one actual source row, not a synthesized combination of readings.
            candidates.setdefault(simplified, (traditional, pinyin, number))
    require(rows == 125324, "dictionary entry count mismatch")
    return candidates


def read_frequency(path):
    import msgpack
    require(msgpack.__version__ == "1.1.2", "requires msgpack 1.1.2")
    require(sha(path.read_bytes()) == WHEEL_SHA, "frequency wheel pin mismatch")
    with zipfile.ZipFile(path) as archive:
        packed = archive.read(MEMBER)
    require(sha(packed) == MEMBER_SHA, "frequency member pin mismatch")
    bins = msgpack.unpackb(gzip.decompress(packed), raw=False)
    require(bins[0] == {"format": "cB", "version": 1}, "frequency format mismatch")
    bands = {}
    for index, words in enumerate(bins[1:]):
        require(type(words) is list and all(type(w) is str for w in words)
                and words == sorted(set(words)), "invalid frequency bin")
        for word in words:
            require(word not in bands, "duplicate frequency key")
            bands[word] = index
    return bands


def stage(source, frequency, output):
    require(not output.exists(), "refusing to overwrite staged evidence")
    candidates = read_source(source)
    bands = read_frequency(frequency)
    ordered = sorted(candidates, key=lambda word: (word not in bands, bands.get(word, 0), word))
    rows = "word\ttraditional\tpinyin\tsourceLine\trawWholeTokenBand\n"
    rows += "".join("\t".join([word, candidates[word][0], candidates[word][1],
                              str(candidates[word][2]), str(bands[word]) if word in bands else "-"]) + "\n"
                    for word in ordered)
    report = dict(status="staged-not-installed", sourceURL=SOURCE_URL, archiveSHA256=SOURCE_SHA,
                  rawSHA256=RAW_SHA, frequencyMember=MEMBER, frequencyMemberSHA256=MEMBER_SHA,
                  candidateCount=len(candidates), observedWholeKeys=sum(w in bands for w in candidates),
                  byMaximum={n: sum(len(w) <= n for w in candidates) for n in [3, 5, 6, 7, 9]},
                  legacyDictionaryAttested=[w for w in LEGACY if w in candidates],
                  legacyAuthoredWithoutDictionaryEvidence=[w for w in LEGACY if w not in candidates],
                  rowsSHA256=sha(rows.encode()),
                  observationScope="Exact raw whole keys; no segmentation/preprocessing parity or invented unknown frequency",
                  qualityScope="Only explicit all-variant/error senses excluded; not a semantic or normative review",
                  license="CC BY-SA 4.0; source attribution and complete notices required before distribution")
    output.mkdir(parents=True)
    (output / "candidate-sources.tsv").write_text(rows, encoding="utf-8")
    (output / "audit.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return report


def select_pools(source, frequency, output):
    """Select full-size pools with explicit authored/adapted source identities."""
    candidates = read_source(source)
    bands = read_frequency(frequency)
    packed = source.read_bytes()
    require(sha(packed) == SOURCE_SHA, "boundary source pin mismatch")
    records = {}
    for number, line in enumerate(gzip.decompress(packed).decode("utf-8").splitlines(), 1):
        if line and not line.startswith("#"):
            traditional, word, pinyin, senses = parse_row(line)
            if any(not VARIANT.match(sense) for sense in senses):
                records.setdefault(word, number)
    additions = {}
    for original, adapted in [("卡拉OK", "卡拉ＯＫ"), ("阿Q", "阿Ｑ")]:
        require(original in records, "width-adaptation source absent")
        additions[adapted] = dict(sourceForm=original, sourceLine=records[original],
                                  change="explicit fullwidth Latin writing adaptation", targetBand=bands.get(adapted))
    comma = sorted(w for w in records if 2 <= len(w) <= 9 and "，" in w
                   and all("\u3400" <= c <= "\u9fff" or c == "，" for c in w))[0]
    additions[comma] = dict(sourceForm=comma, sourceLine=records[comma], change="literal", targetBand=bands.get(comma))
    ascii_comma = comma.replace("，", ",")
    additions[ascii_comma] = dict(sourceForm=comma, sourceLine=records[comma],
                                 change="explicit ASCII-comma writing adaptation", targetBand=bands.get(ascii_comma))
    middle = sorted(w for w in records if 2 <= len(w) <= 9 and "·" in w
                    and all("\u3400" <= c <= "\u9fff" or c == "·" for c in w))
    require(len(middle) >= 9, "literal middle-dot sources insufficient")
    for word in middle[:9]:
        additions[word] = dict(sourceForm=word, sourceLine=records[word], change="literal", targetBand=bands.get(word))
    rank = lambda word: (word not in bands, bands.get(word, 0), word)
    ranked = sorted(candidates, key=rank)
    selected = list(LEGACY)
    require(len(set(selected)) == 26 and all(len(w) == 2 for w in selected), "legacy starter contract changed")
    selected.append(next(w for w in ranked if len(w) == 3))
    for word in ranked:
        if len(selected) == 200:
            break
        if len(word) == 2 and word not in selected:
            selected.append(word)
    pools = {"basic": selected.copy()}
    for name, count, maximum, minimum_alphabet in [("1k", 1000, 5, 770), ("5k", 5000, 6, 1840), ("10k", 10000, 7, 2572), ("50k", 50000, 9, 4833)]:
        protected = set(selected)
        if name == "50k":
            selected.extend(additions)
            protected.update(additions)
        if not any(len(w) == maximum for w in selected):
            selected.append(next(w for w in ranked if len(w) == maximum and w not in selected))
        present = set(selected)
        for word in ranked:
            if len(selected) == count:
                break
            if len(word) <= maximum and word not in present:
                present.add(word)
                selected.append(word)
        letters = Counter("".join(selected))
        for word in ranked:
            if len(letters) >= minimum_alphabet:
                break
            if word in present or word not in bands or len(word) > maximum or set(word) <= letters.keys():
                continue
            for index in range(len(selected) - 1, -1, -1):
                removed = selected[index]
                if removed in protected or len(removed) == maximum:
                    continue
                counts = Counter(removed)
                if all(letters[c] > amount for c, amount in counts.items()):
                    letters.subtract(counts)
                    letters.update(word)
                    selected[index] = word
                    present.remove(removed)
                    present.add(word)
                    break
            else:
                raise ValueError("no replaceable word without losing existing character coverage")
        require(len(letters) >= minimum_alphabet, "independent character coverage insufficient")
        require(len(selected) == count and len(set(selected)) == count, "pool capacity/uniqueness failure")
        require(min(map(len, selected)) == 2 and max(map(len, selected)) == maximum, "pool length failure")
        pools[name] = selected.copy()
    report = dict(status="selected-not-installed", writingAdaptationsAndLiteralBoundaries=additions,
                  legacyAuthoredWithoutDictionaryEvidence=[w for w in LEGACY if w not in candidates],
                  pools={})
    for name, words in pools.items():
        content = "\n".join(words) + "\n"
        (output / (name + ".txt")).write_text(content, encoding="utf-8")
        report["pools"][name] = dict(count=len(words), minimum=min(map(len, words)), maximum=max(map(len, words)),
                                    alphabetCount=len(set("".join(words))),
                                    exactWholeFrequencyKeys=sum(w in bands for w in words),
                                    punctuationTokens=sum(any(c in ",，·" for c in w) for w in words),
                                    uppercaseTokens=sum(any(c.isupper() for c in w) for w in words), sha256=sha(content.encode()))
    require(report["pools"]["50k"]["punctuationTokens"] == 11, "punctuation boundary contract failed")
    require(report["pools"]["50k"]["uppercaseTokens"] == 2, "uppercase boundary contract failed")
    (output / "selection.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return report


def emit_native(source, frequency, output):
    selection = json.loads((output / "selection.json").read_text(encoding="utf-8"))
    words = (output / "50k.txt").read_text(encoding="utf-8").splitlines()
    require(sha((output / "50k.txt").read_bytes()) == selection["pools"]["50k"]["sha256"], "selected pool hash mismatch")
    for name, count in [("basic", 200), ("1k", 1000), ("5k", 5000), ("10k", 10000)]:
        require(words[:count] == (output / (name + ".txt")).read_text(encoding="utf-8").splitlines(), "native prefix differs from selected pool")
    revision = "cedict-20261029-wordfreq-3.1.1-v1"
    swift = "// Independent CC-CEDICT selection and explicitly attributed writing adaptations.\n// CC BY-SA 4.0; see SimplifiedChineseCorpusNotices.txt and per-word sources.\nenum SimplifiedChineseCorpus {\n"
    swift += '  static let revision = "' + revision + '"\n'
    swift += '  static let allWords: [String] = """\n' + "\n".join(words) + '\n""".split(separator: "\\n").map(String.init)\n'
    swift += "  static let basic = Array(allWords.prefix(200))\n  static let words1k = Array(allWords.prefix(1_000))\n  static let words5k = Array(allWords.prefix(5_000))\n  static let words10k = Array(allWords.prefix(10_000))\n}\n"
    candidates = read_source(source)
    bands = read_frequency(frequency)
    rows = "word\tkind\tsourceForm\tsourceLine\ttargetWholeTokenBand\n"
    for word in words:
        if word in selection["writingAdaptationsAndLiteralBoundaries"]:
            entry = selection["writingAdaptationsAndLiteralBoundaries"][word]
            kind, original, number = entry["change"], entry["sourceForm"], entry["sourceLine"]
        elif word in candidates:
            kind, original, number = "literal", word, candidates[word][2]
        else:
            require(word in LEGACY, "word lacks independent source")
            kind, original, number = "Typebar authored legacy", word, "-"
        rows += "\t".join([word, kind, original, str(number), str(bands[word]) if word in bands else "-"]) + "\n"
    with zipfile.ZipFile(frequency) as archive:
        metadata = archive.read("wordfreq-3.1.1.dist-info/METADATA").decode("utf-8")
    require("## License" in metadata, "frequency license absent")
    header = "\n".join(line for line in gzip.decompress(source.read_bytes()).decode("utf-8").splitlines() if line.startswith("#"))
    notice = ("Typebar independent simplified Chinese practice selection\nRevision: " + revision
              + "\nSource: " + SOURCE_URL + "\nArchive SHA-256: " + SOURCE_SHA
              + "\nSelection and writing adaptations: CC BY-SA 4.0.\n"
              + "Seven older entries are Typebar-authored, not dictionary-attested.\n"
              + "Three explicitly attributed writing adaptations change Latin width or comma style.\n"
              + "Target whole-token bands are raw observations; - means unknown, not zero.\n"
              + "Original spellings, source line numbers and adaptation kinds are in SimplifiedChineseCorpusSources.txt.\n"
              + "No source-project words or assets are used. No identical frequency, vocabulary or normative quality is claimed.\n\n"
              + header + "\n\nwordfreq 3.1.1 — Robyn Speer and contributors\nWheel SHA-256: " + WHEEL_SHA
              + "\nChinese member SHA-256: " + MEMBER_SHA + "\n\n" + metadata[metadata.index("## License"):])
    files = {"SimplifiedChineseCorpus.generated.swift": swift, "SimplifiedChineseCorpusSources.txt": rows,
             "SimplifiedChineseCorpusNotices.txt": notice}
    for name, text in files.items():
        require(not (output / name).exists(), "refusing to overwrite native artifact")
        (output / name).write_text(text, encoding="utf-8")
    (output / "native-files.json").write_text(json.dumps({n: sha(t.encode()) for n, t in files.items()}, indent=2) + "\n")


class ReaderTests(unittest.TestCase):
    def test_literal_fields_and_pronunciation_are_not_normalized(self):
        self.assertEqual(parse_row("測試 测试 [ce4 shi4] /test/"), ("測試", "测试", "ce4 shi4", ["test"]))

    def test_malformed_rows_are_rejected(self):
        for line in ["测试 [ce4 shi4] /test/", "測試 测试 [ce4] //", "測試 测试 [ce4] /test/\t"]:
            with self.assertRaises(ValueError):
                parse_row(line)

    def test_all_variants_rejected_but_independent_sense_retained(self):
        self.assertFalse(eligible("测试", ["old variant of 測試", "variant of 測試"]))
        self.assertTrue(eligible("测试", ["variant of 測試", "test"]))

    def test_length_script_and_width_are_not_silently_converted(self):
        for word in ["字", "字" * 10, "ＯＫ", "OK", "测试，", "测 试"]:
            self.assertFalse(eligible(word, ["test"]))
        self.assertTrue(eligible("测试", ["test"]))

    def test_pin_guard_remains_active(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "changed.gz"
            path.write_bytes(gzip.compress(b"changed dictionary"))
            with self.assertRaisesRegex(ValueError, "archive pin mismatch"):
                read_source(path)

    def test_existing_output_is_never_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            sentinel = output / "existing.txt"
            sentinel.write_bytes(b"keep")
            with self.assertRaisesRegex(ValueError, "refusing to overwrite"):
                stage(output / "missing-source", output / "missing-wheel", output)
            self.assertEqual(sentinel.read_bytes(), b"keep")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--select", action="store_true", help="also stage five selected pools; never installs them")
    parser.add_argument("--emit-native", action="store_true", help="emit native source and full notices outside the repository")
    parser.add_argument("--source", type=Path)
    parser.add_argument("--frequency-wheel", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if args.self_test:
        unittest.main(argv=[__file__])
    else:
        require(all([args.source, args.frequency_wheel, args.output]), "source, frequency wheel and output required")
        result = stage(args.source, args.frequency_wheel, args.output)
        if args.select:
            selection = select_pools(args.source, args.frequency_wheel, args.output)
            print(json.dumps(dict(status=selection["status"], pools=selection["pools"])))
            if args.emit_native:
                emit_native(args.source, args.frequency_wheel, args.output)
        else:
            require(not args.emit_native, "native emission requires selection")
        print(json.dumps({k: result[k] for k in ["status", "candidateCount", "observedWholeKeys", "rowsSHA256"]}))
