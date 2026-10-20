#!/usr/bin/env python3
"""Audit independently authored practice lists; never generate word values.

The optional pinned wordfreq check is QA-only statistical spelling evidence,
not a dictionary or a claim that every expression has been linguistically reviewed.
"""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import re
import sys
import unicodedata
import zipfile

SOURCE = Path("Sources/Typebar/WesternBasicCorpora.swift")
MANIFEST = Path("Compatibility/western-basic-corpora.json")
SPECS = {"spanish": (197, 0, 10, "es"), "french": (174, 2, 12, "fr"), "german": (200, 2, 11, "de"),
         "italian": (199, 0, 13, "it")}
DEFAULT_MIXED = ("spanish", "french", "german")
WHEEL_SHA = "4b1c6ecffc6198be3396d5cf871c4423ca71c907c231348d352dd54d62b97473"


def digest(data):
    return hashlib.sha256(data).hexdigest()


def frequency_key(word):
    # wordfreq 3.1.1 tokens.py normalizes NFC, then case-folds tokens. Our
    # validated subset contains only Latin letters and ASCII word separators.
    return unicodedata.normalize("NFC", word).casefold()


def audit_words(words, expected_count, phrase_count, maximum_length):
    if len(words) != expected_count or len(set(word.casefold() for word in words)) != expected_count:
        raise ValueError("candidate count or uniqueness mismatch")
    if sum(" " in word for word in words) != phrase_count:
        raise ValueError("multiword candidate count mismatch")
    for word in words:
        if (not word or word.strip() != word or "  " in word or len(word) > maximum_length
                or word != unicodedata.normalize("NFC", word)
                or any(char != " " and (not char.isalpha() or "LATIN" not in unicodedata.name(char, ""))
                       for char in word)):
            raise ValueError(f"invalid authored candidate: {word!r}")
    return {"count": len(words), "multiwordCount": phrase_count,
            "minimumLength": min(map(len, words)), "maximumLength": max(map(len, words)),
            "uppercaseCount": sum(any(char.isupper() for char in word) for word in words),
            "wordsSHA256": digest(("\n".join(words) + "\n").encode())}


def read_lists(root):
    raw = (root / SOURCE).read_bytes()
    lists = dict((name, body.splitlines()) for name, body in re.findall(
        r'static let (spanish|french|german|italian): \[String\] = """\n(.*?)\n"""', raw.decode("utf-8"), re.S))
    if set(lists) != set(SPECS):
        raise ValueError("missing authored language data")
    return raw, lists


def manifest(root):
    raw, lists = read_lists(root)
    records = {name: audit_words(lists[name], *SPECS[name][:3]) for name in SPECS}
    english_source = (root / "Sources/Typebar/EnglishFrequencyCorpus.generated.swift").read_text()
    match = re.search(r'static let basicWords: \[String\] = """\n(.*?)\n"""', english_source, re.S)
    if not match:
        raise ValueError("missing independent English basic data")
    english = match.group(1).splitlines()
    if len(english) != 200:
        raise ValueError("default English candidate count mismatch")
    owners = {}
    for language, words in [("english", english)] + [(name, lists[name]) for name in DEFAULT_MIXED]:
        for word in words:
            # Every source is NFC, so Python string keys and native UTF-16 keys
            # have the same equality here. Do not case-fold union ownership.
            owners[word] = language
    return {"schemaVersion": 1, "authoring": "independently authored Typebar vocabulary; no reference word values",
            "source": str(SOURCE), "sourceSHA256": digest(raw), "languages": records,
            "defaultPolyglot": {"rawCandidateCount": len(english) + sum(len(lists[name]) for name in DEFAULT_MIXED),
                                "unionCount": len(owners),
                                "lastOwnerCounts": {name: list(owners.values()).count(name)
                                                    for name in ["english", *DEFAULT_MIXED]}}}


def verify_frequency(root, wheel):
    if digest(wheel.read_bytes()) != WHEEL_SHA:
        raise ValueError("wordfreq 3.1.1 wheel SHA-256 mismatch")
    import msgpack
    if msgpack.__version__ != "1.1.2":
        raise ValueError("QA preparation requires msgpack==1.1.2")
    _, lists = read_lists(root)
    reports = []
    with zipfile.ZipFile(wheel) as archive:
        for name, (_, _, _, code) in SPECS.items():
            member = f"wordfreq/data/large_{code}.msgpack.gz"
            packed = archive.read(member)
            bins = msgpack.unpackb(gzip.decompress(packed), raw=False)
            if not bins or bins[0] != {"format": "cB", "version": 1}:
                raise ValueError("unexpected wordfreq frequency format")
            known = {word for band in bins[1:] for word in band}
            tokens = {frequency_key(word) for candidate in lists[name] for word in candidate.split(" ")}
            missing = sorted(tokens - known)
            if missing:
                raise ValueError(f"{name} spellings lack statistical evidence: {missing}")
            reports.append({"language": name, "distinctComponentSpellings": len(tokens),
                            "attestedSpellings": len(tokens), "member": member, "memberSHA256": digest(packed)})
    return reports


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--emit-manifest", action="store_true")
    parser.add_argument("--wordfreq-wheel", type=Path)
    args = parser.parse_args()
    result = manifest(args.project_root)
    if args.emit_manifest:
        print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
        return
    if json.loads((args.project_root / MANIFEST).read_text()) != result:
        raise ValueError("authored vocabulary manifest mismatch")
    if args.wordfreq_wheel:
        print(json.dumps(verify_frequency(args.project_root, args.wordfreq_wheel), ensure_ascii=False))
    print("Western basic vocabulary integrity passed (not a linguistic-quality or source-distribution parity claim)")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError) as error:
        sys.exit(str(error))
