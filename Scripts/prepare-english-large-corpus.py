#!/usr/bin/env python3
"""Prepare independent English 450k data. No reference words or downloads.

msgpack==1.1.2 is preparation-only. Bundled verification and self-tests use
the standard library. Never install packages or add runtime Python dependencies.
"""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import re
import sqlite3
import subprocess
import sys
import tempfile
import unittest
import zipfile

SCOWL_COMMIT = "7e99edab8e32f9f9ea2b15f249ca8d4d67237410"
WHEEL_SHA = "4b1c6ecffc6198be3396d5cf871c4423ca71c907c231348d352dd54d62b97473"
MEMBER = "wordfreq/data/large_en.msgpack.gz"
MEMBER_SHA = "dffae8066b78dce0a6667cf5f58e567054f902674667090a7ac8a8a44628b05c"
REVISION = "scowl95-wordfreq-3.1.1-english450k-v2"
COUNT, CAPS, QUOTAS = 450029, 33021, (44, 44, 88)
SCOWL_COPYRIGHT_SHA = "090575a131b4260926c7a6b30a90aca0f5db5fbb5c46778e0c5855227bf6ebc3"
SWIFT = Path("Sources/Typebar/EnglishLargeCorpus.generated.swift")
MANIFEST = Path("Compatibility/english-large-corpus.json")
NOTICES = Path("Resources/EnglishLargeCorpusNotices.txt")
SCOWL_MARKER = "=== Complete SCOWL Copyright ===\n"
WORDFREQ_MARKER = "=== wordfreq 3.1.1 release metadata ===\n"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def frequency_bands(bins):
    require(isinstance(bins, list), "frequency bins must be an array")
    result = {}
    for band, tokens in enumerate(bins):
        require(isinstance(tokens, list) and all(type(w) is str for w in tokens),
                "frequency bin must contain strings")
        require(tokens == sorted(set(tokens)), "frequency bin must be sorted and unique")
        for word in tokens:
            require(word not in result, "frequency token occurs in multiple bands")
            result[word] = band
    return result


def unattested_repetition(word):
    return bool(re.search(r"(.)\1{3,}", word) or re.fullmatch(r"(.{1,5})\1{3,}", word))


def select(dictionary, sizes, bins, count=COUNT, caps=CAPS, quotas=QUOTAS):
    require(type(count) is int and count > 0 and type(caps) is int and 0 <= caps <= count,
            "invalid count or capital quota")
    require(len(quotas) == 3 and all(type(n) is int and n >= 0 for n in quotas),
            "invalid punctuation quotas")
    bands = frequency_bands(bins)
    require(all(type(w) is str for w in dictionary), "dictionary must contain strings")
    forms = {w for w in dictionary if len(w) <= 31 and re.fullmatch(r"[A-Za-z]+(?:['.-][A-Za-z]+)*\.?", w)}
    require(forms <= sizes.keys(), "dictionary spelling is not attested literally in the fixed source")
    require(all(type(sizes[w]) is int and 0 < sizes[w] <= 95 for w in forms),
            "invalid dictionary size metadata")

    def priority(word):
        return bands.get(word.lower(), 10**9), sizes.get(word, 10**9), word.lower(), word

    def punctuation_priority(word):
        return bands.get(word, 10**9), sizes[word], digest(word.encode()), word

    lower = sorted((w for w in forms if re.fullmatch(r"[a-z]+", w)), key=priority)
    upper = sorted((w for w in forms if w.isalpha() and w != w.lower()), key=priority)
    groups = [
        sorted((w for w in forms if re.fullmatch(r"[a-z]+(?:'[a-z]+)+", w)), key=punctuation_priority),
        sorted((w for w in forms if re.fullmatch(r"[a-z]+(?:-[a-z]+)+", w)), key=punctuation_priority),
        sorted((w for w in forms if re.fullmatch(r"[A-Za-z]+(?:\.[A-Za-z]+)*\.", w)), key=punctuation_priority),
    ]
    require(all(len(group) >= quota for group, quota in zip(groups, quotas)),
            "insufficient real punctuated dictionary forms")
    punctuated = [w for group, quota in zip(groups, quotas) for w in group[:quota]]
    cased_letters = caps - sum(w != w.lower() for w in punctuated)
    require(0 <= cased_letters <= len(upper), "insufficient existing cased dictionary forms")
    keys = {w.lower() for w in forms}
    outside = [w for w in bands if re.fullmatch(r"[a-z]{2,31}|a|i", w) and w not in keys]
    extras = [w for w in outside if not unattested_repetition(w)]
    needed = count - len(lower) - cased_letters - len(punctuated)
    require(0 <= needed <= len(extras), "insufficient real observed tokens; never pad a pool")
    words = sorted(lower + upper[:cased_letters] + punctuated + extras[:needed], key=priority)
    require(len(words) == len(set(words)) == count, "selection is not exact and unique")
    require(sum(w != w.lower() for w in words) == caps, "capital quota was not retained")
    require(sum(not w.isalpha() for w in words) == sum(quotas), "punctuation quota was not retained")
    return words, {
        "available": {"lowerDictionary": len(lower), "casedDictionary": len(upper),
                      "punctuationGroups": list(map(len, groups)), "extraObserved": len(extras)},
        "rejectedUnattestedRepetitions": len(outside) - len(extras),
        "selectedDictionary": len(lower) + cased_letters + len(punctuated),
        "selectedObservedOutsideDictionary": needed,
        "lastOutsideObservationBand": bands[extras[needed - 1]] if needed else None,
    }


def read_frequency(wheel):
    require(digest(wheel.read_bytes()) == WHEEL_SHA, "wordfreq wheel SHA-256 mismatch")
    import msgpack
    require(msgpack.__version__ == "1.1.2", "preparation requires msgpack==1.1.2")
    with zipfile.ZipFile(wheel) as archive:
        packed = archive.read(MEMBER)
        metadata = archive.read("wordfreq-3.1.1.dist-info/METADATA").decode("utf-8")
    require(digest(packed) == MEMBER_SHA, "English frequency member SHA-256 mismatch")
    decoded = msgpack.unpackb(gzip.decompress(packed), raw=False)
    require(isinstance(decoded, list) and decoded and decoded[0] == {"format": "cB", "version": 1},
            "unsupported wordfreq format")
    require("## License" in metadata, "wordfreq source notices missing")
    return decoded[1:], packed, metadata[metadata.index("## License"):].strip() + "\n"


def read_dictionary(root):
    def run(*command):
        return subprocess.check_output(command, cwd=root, stderr=subprocess.PIPE)
    require(run("git", "rev-parse", "HEAD").decode().strip() == SCOWL_COMMIT, "SCOWL commit mismatch")
    require(not run("git", "status", "--porcelain", "--untracked-files=normal").strip(),
            "SCOWL checkout must be clean")
    with tempfile.TemporaryDirectory(prefix="typebar-english-large-scowl-") as temporary:
        database = Path(temporary) / "scowl.db"
        run(sys.executable, "combine.py", "create-db", str(database))
        raw = run(sys.executable, "scowl", "--db", str(database), "word-list", "95",
                  "A,B,Z,C", "1", "--categories=", "--hyphen", "--dot=True")
        with sqlite3.connect(database.resolve().as_uri() + "?mode=ro", uri=True) as connection:
            sizes = dict(connection.execute("""select word, min(size) from scowl_v0
                where size <= 95 and variant_level <= 1
                  and spelling in ('A','B','Z','C','_')
                  and region in ('','US','GB','CA') and category = ''
                group by word"""))
    require(not run("git", "status", "--porcelain", "--untracked-files=normal").strip(),
            "SCOWL source changed during preparation")
    copyright_text = (root / "Copyright").read_text(encoding="utf-8")
    require(digest(copyright_text.encode()) == SCOWL_COPYRIGHT_SHA
            and "=== UKACD" in copyright_text and "prominently displayed" in copyright_text,
            "complete large-list SCOWL copyright missing")
    return raw.decode().splitlines(), sizes, raw, copyright_text


def native_source(words):
    return (
        "// Generated by Scripts/prepare-english-large-corpus.py; do not edit.\n"
        "// Independent SCOWL / wordfreq selection, CC BY-SA 4.0.\n"
        "// Full notices: Resources/EnglishLargeCorpusNotices.txt; UKACD credit must be visible in app.\n"
        "// No reference-project code or word data. Loaded only for the large choice.\n"
        "enum EnglishLargeCorpus {\n"
        f'  static let revision = "{REVISION}"\n'
        '  static let words: [String] = """\n' + "\n".join(words) + '\n'
        '""".split(separator: "\\n").map(String.init)\n}\n'
    ).encode()


def artifacts(words, details, raw, copyright_text, wordfreq_notice):
    text = ("\n".join(words) + "\n").encode()
    require(len(words) == len(set(words)) == COUNT and min(map(len, words)) == 1
            and max(map(len, words)) == 31, "unexpected large English shape")
    require(sum(w != w.lower() for w in words) == CAPS
            and sum(not w.isalpha() for w in words) == sum(QUOTAS), "unexpected large English character classes")
    swift = native_source(words)
    notices = (
        "Typebar independent large English corpus — revision 2\n"
        "Adapted selection by Typebar contributors (2026), CC BY-SA 4.0.\n"
        "https://creativecommons.org/licenses/by-sa/4.0/\n\n"
        "Includes material from the UK Advanced Cryptics Dictionary.\n"
        "The UKACD copyright below must also be prominently displayed in the native app.\n\n"
        "Changes: SCOWL size 95, A/B/Z/C spelling variants at level 1, default category;\n"
        "literal ASCII spellings, internal apostrophes/hyphens and terminal periods,\n"
        "length 1–31; 44 apostrophe, 44 hyphen and 88 terminal-period dictionary entries;\n"
        "33,021 cased entries including punctuation, all lowercase dictionary letters,\n"
        "then existing lowercase English observations outside the dictionary to 450,029.\n"
        "Dictionary forms retain their existing case. Observation tokens are not dictionary-certified.\n"
        "Unattested runs of 4+ identical letters or 4+ repeats of a 1–5-letter pattern are excluded.\n"
        "Existing dictionary-attested spellings are retained without this observation-only filter.\n"
        "Observed bands order known tokens; unknown dictionary frequency is not invented.\n"
        "The large choice remains Zipf-unsupported. Small English corpora are separate.\n\n"
        "SCOWL rel-2026.02.25\n"
        f"https://github.com/en-wl/wordlist/tree/{SCOWL_COMMIT}\n\n" +
        SCOWL_MARKER + copyright_text + "\n" + WORDFREQ_MARKER +
        "wordfreq 3.1.1 — Robyn Speer and contributors\n"
        "https://pypi.org/project/wordfreq/3.1.1/\n"
        "The data license is CC BY-SA 4.0, not the code's Apache license.\n" + wordfreq_notice
    ).encode()
    manifest = {
        "schemaVersion": 1, "revision": REVISION,
        "scowl": {"commit": SCOWL_COMMIT, "size": 95, "spellings": ["A", "B", "Z", "C"],
                  "variantLevel": 1, "categories": [""], "hyphen": True, "dot": True,
                  "rawSHA256": digest(raw), "copyrightSHA256": digest(copyright_text.encode())},
        "wordfreq": {"version": "3.1.1", "wheelSHA256": WHEEL_SHA, "member": MEMBER,
                     "memberSHA256": MEMBER_SHA},
        "preparationDependency": "msgpack==1.1.2; no native runtime dependency",
        "selection": details,
        "shape": {"count": len(words), "uniqueCount": len(set(words)),
                  "casefoldUniqueCount": len({w.lower() for w in words}),
                  "uppercaseEntries": CAPS, "punctuationEntries": sum(QUOTAS),
                  "punctuationGroups": list(QUOTAS), "minimumLength": 1, "maximumLength": 31},
        "wordsSHA256": digest(text), "swiftSHA256": digest(swift), "noticesSHA256": digest(notices),
        "dataLicense": "CC-BY-SA-4.0; retain all source notices, including prominent UKACD credit",
        "limits": "Source observations and matching aggregate shape do not prove language quality, difficulty or distribution parity.",
    }
    return {SWIFT: swift, NOTICES: notices,
            MANIFEST: (json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode()}


def publish(outputs, root, check):
    if check:
        for name, data in outputs.items():
            require((root / name).is_file() and (root / name).read_bytes() == data, "artifact mismatch: " + str(name))
    else:
        require(not any((root / name).exists() for name in outputs), "refusing to overwrite artifacts")
        for name, data in outputs.items():
            destination = root / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(data)


def verify_bundled(root):
    manifest = json.loads((root / MANIFEST).read_text())
    swift = (root / SWIFT).read_bytes()
    notice = (root / NOTICES).read_bytes()
    require(manifest["schemaVersion"] == 1 and manifest["revision"] == REVISION, "unsupported corpus manifest")
    require(manifest["scowl"]["copyrightSHA256"] == SCOWL_COPYRIGHT_SHA
            and manifest["scowl"]["commit"] == SCOWL_COMMIT
            and manifest["wordfreq"]["wheelSHA256"] == WHEEL_SHA
            and manifest["wordfreq"]["memberSHA256"] == MEMBER_SHA, "source pin mismatch")
    require(digest(swift) == manifest["swiftSHA256"] and digest(notice) == manifest["noticesSHA256"],
            "native corpus or notices hash mismatch")
    match = re.search(rb'  static let words: \[String\] = """\n([A-Za-z\'.\-\n]+)"""', swift)
    require(match is not None, "invalid native data section")
    body = match.group(1)
    words = body.decode("ascii").splitlines()
    require(native_source(words) == swift and digest(body) == manifest["wordsSHA256"], "native data template mismatch")
    require(all(re.fullmatch(r"[A-Za-z]+(?:['.-][A-Za-z]+)*\.?", w) and 1 <= len(w) <= 31 for w in words),
            "invalid native spelling")
    expected = {"count": COUNT, "uniqueCount": len(set(words)),
                "casefoldUniqueCount": len({w.lower() for w in words}),
                "uppercaseEntries": sum(w != w.lower() for w in words),
                "punctuationEntries": sum(not w.isalpha() for w in words),
                "punctuationGroups": [sum(re.fullmatch(pattern, w) is not None for w in words)
                                      for pattern in [r"[a-z]+(?:'[a-z]+)+", r"[a-z]+(?:-[a-z]+)+",
                                                      r"[A-Za-z]+(?:\.[A-Za-z]+)*\."]],
                "minimumLength": min(map(len, words)), "maximumLength": max(map(len, words))}
    require(len(words) == COUNT and len(set(words)) == COUNT and expected == manifest["shape"],
            "native corpus shape mismatch")
    require(expected["uppercaseEntries"] == CAPS and expected["punctuationGroups"] == list(QUOTAS)
            and expected["minimumLength"] == 1 and expected["maximumLength"] == 31,
            "large choice limits changed")
    decoded_notice = notice.decode()
    require(SCOWL_MARKER in decoded_notice and WORDFREQ_MARKER in decoded_notice, "source notices missing")
    copyright_text = decoded_notice.split(SCOWL_MARKER, 1)[1].split("\n" + WORDFREQ_MARKER, 1)[0]
    require(digest(copyright_text.encode()) == SCOWL_COPYRIGHT_SHA
            and "prominently displayed" in copyright_text, "SCOWL copyright was truncated")
    print("English large bundled integrity passed (450029 words; upstream reproduction is stronger)")


class SelectionTests(unittest.TestCase):
    def fixture(self):
        dictionary = {"bay", "elm", "node", "Bay", "Oak", "can't", "well-being", "Dr."}
        return dictionary, {w: 20 for w in dictionary}, [["bay", "node"], ["elm", "oak"], ["cedar", "pine"]]

    def choose(self, dictionary=None, sizes=None, bins=None, **kwargs):
        d, s, b = self.fixture()
        return select(d if dictionary is None else dictionary, s if sizes is None else sizes,
                      b if bins is None else bins, count=kwargs.pop("count", 9),
                      caps=kwargs.pop("caps", 2), quotas=kwargs.pop("quotas", (1, 1, 1)), **kwargs)

    def test_literal_case_punctuation_and_outside_observations(self):
        words, detail = self.choose()
        self.assertEqual(set(words), {"bay", "Bay", "elm", "node", "can't", "well-being", "Dr.", "cedar", "pine"})
        self.assertEqual(words[:2], ["Bay", "bay"])
        self.assertEqual(detail["selectedObservedOutsideDictionary"], 2)
        self.assertNotIn("oak", words)
        self.assertNotIn("Dr", words)

    def test_deterministic_dictionary_input_order(self):
        d, _, _ = self.fixture()
        self.assertEqual(self.choose(dictionary=sorted(d)), self.choose(dictionary=sorted(d, reverse=True)))

    def test_insufficient_sources_never_pad(self):
        with self.assertRaisesRegex(ValueError, "insufficient real observed"): self.choose(count=99)
        with self.assertRaisesRegex(ValueError, "insufficient existing cased"): self.choose(caps=8)
        d, s, _ = self.fixture()
        with self.assertRaisesRegex(ValueError, "punctuated"): self.choose(dictionary=d - {"Dr."}, sizes=s)

    def test_unattested_spelling_is_not_silently_normalized(self):
        d, s, _ = self.fixture()
        with self.assertRaisesRegex(ValueError, "attested literally"):
            self.choose(dictionary=d | {"Dr"}, sizes=s)

    def test_bad_frequency_order_duplicates_and_types(self):
        for bins in [[["node", "bay"]], [["bay"], ["bay"]], [[7]], {}]:
            with self.assertRaises(ValueError): self.choose(bins=bins)

    def test_repetition_filter_only_removes_unattested_observations(self):
        bins = [["bay", "node"], ["elm", "oak"], ["aaaa", "cedar", "hahahaha", "pine", "soooo"]]
        words, detail = self.choose(bins=bins)
        self.assertNotIn("aaaa", words)
        self.assertNotIn("hahahaha", words)
        self.assertNotIn("soooo", words)
        self.assertEqual(detail["rejectedUnattestedRepetitions"], 3)
        dictionary, sizes, _ = self.fixture()
        words, detail = self.choose(dictionary=dictionary | {"aaaa"},
                                    sizes=sizes | {"aaaa": 20}, bins=bins, count=10)
        self.assertIn("aaaa", words)
        self.assertEqual(detail["rejectedUnattestedRepetitions"], 2)

    def test_existing_artifact_refusal_is_checked_before_any_write(self):
        with tempfile.TemporaryDirectory(prefix="typebar-large-publish-test-") as temporary:
            root = Path(temporary)
            (root / "existing.txt").write_bytes(b"keep")
            with self.assertRaisesRegex(ValueError, "refusing to overwrite"):
                publish({Path("new.txt"): b"new", Path("existing.txt"): b"replace"}, root, False)
            self.assertFalse((root / "new.txt").exists())
            self.assertEqual((root / "existing.txt").read_bytes(), b"keep")

    def test_invalid_counts_and_punctuation_case_budget(self):
        for count in [0, -1, True, 1.5]:
            with self.assertRaises(ValueError): self.choose(count=count)
        with self.assertRaises(ValueError): self.choose(caps=0)
        with self.assertRaises(ValueError): self.choose(quotas=(-1, 1, 1))
        with self.assertRaises(ValueError): self.choose(count=1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scowl-root", type=Path)
    parser.add_argument("--wordfreq-wheel", type=Path)
    parser.add_argument("--output-root", type=Path, default=Path.cwd())
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--check-bundled", action="store_true")
    mode.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return 0 if unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(SelectionTests)).wasSuccessful() else 1
    if args.check_bundled:
        verify_bundled(args.output_root)
        return 0
    require(args.scowl_root is not None and args.wordfreq_wheel is not None,
            "provide --scowl-root and --wordfreq-wheel")
    bins, _, wordfreq_notice = read_frequency(args.wordfreq_wheel)
    dictionary, sizes, raw, copyright_text = read_dictionary(args.scowl_root)
    words, details = select(dictionary, sizes, bins)
    publish(artifacts(words, details, raw, copyright_text, wordfreq_notice), args.output_root, args.check)
    print("English large source reproduction " + ("checked" if args.check else "prepared") + " (450029 words)")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        print("English large preparation failed: " + str(error), file=sys.stderr)
        raise SystemExit(1)
