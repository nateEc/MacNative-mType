#!/usr/bin/env python3
"""Prepare independent Italian corpus tokens; no reference words or downloads.

msgpack==1.1.2 is preparation-only. --check-bundled uses the standard library.
"""
import argparse
import gzip
import hashlib
import json
from itertools import groupby
from pathlib import Path
import re
import unicodedata
import zipfile

WHEEL_SHA = "4b1c6ecffc6198be3396d5cf871c4423ca71c907c231348d352dd54d62b97473"
MEMBER = "wordfreq/data/large_it.msgpack.gz"
MEMBER_SHA = "0b5500e425a50e0f1fefb256d9125e74f586ac6b2f2a6e41bc96634bd5613cc7"
COUNTS = {"1k": 1159, "7k": 7154, "60k": 60442, "280k": 279833}
LIMITS = {"1k": 14, "7k": 18, "60k": 18, "280k": 25}
REVISION = "wordfreq-3.1.1-it-v2"
SWIFT = Path("Sources/Typebar/ItalianFrequencyCorpus.generated.swift")
MANIFEST = Path("Compatibility/italian-frequency-corpus.json")
NOTICES = Path("Resources/ItalianFrequencyCorpusNotices.txt")
NOTICE_MARKER = "=== wordfreq 3.1.1 release metadata ===\n"
EXCLUDED = frozenset("the of and with you your www http com it st ii iii".split())
# Independently authored expressions and geographic case variants. Observed
# frequency belongs to lowercase source tokens, not separately measured names.
PROPER = {word.lower(): word for word in ["Italia", "Roma", "Milano", "Napoli", "Sicilia"]}
ADDITIONS = []
OBSERVED_COUNT = max(COUNTS.values()) - len(ADDITIONS)
PUNCTUATED_BAND_MAXIMUM = 450
# Common technical names, explicitly unranked editorial data for the 60k
# punctuation/symbol practice path. Never claim measured Italian frequency.
TECHNICAL_NAMES = ["C++", "C#"]


def digest(data):
    return hashlib.sha256(data).hexdigest()


def eligible(word):
    return (word == unicodedata.normalize("NFC", word) and len(word) <= 25
            and re.fullmatch(r"(?:[a-zàèéìîòù]{2,}|[aeioè])", word) is not None
            and word not in EXCLUDED)


def select(bins, count=OBSERVED_COUNT):
    if type(count) is not int or count < 1 or not isinstance(bins, list):
        raise ValueError("invalid selection request")
    words, bands, seen = [], [], set()
    for band, tokens in enumerate(bins):
        if (not isinstance(tokens, list) or any(type(x) is not str for x in tokens)
                or tokens != sorted(tokens) or len(set(tokens)) != len(tokens)):
            raise ValueError("frequency bins must contain sorted unique strings")
        for word in tokens:
            if word in seen:
                raise ValueError("token occurs in multiple frequency bins")
            seen.add(word)
            if eligible(word):
                words.append(word); bands.append(band)
    if len(words) < count:
        raise ValueError("insufficient observed tokens; never pad")
    return words[:count], bands[:count], len(words)


def read_source(wheel):
    if digest(wheel.read_bytes()) != WHEEL_SHA:
        raise ValueError("wordfreq wheel SHA-256 mismatch")
    import msgpack
    if msgpack.__version__ != "1.1.2":
        raise ValueError("preparation requires msgpack==1.1.2")
    with zipfile.ZipFile(wheel) as archive:
        packed = archive.read(MEMBER)
        if digest(packed) != MEMBER_SHA:
            raise ValueError("Italian member SHA-256 mismatch")
        decoded = msgpack.unpackb(gzip.decompress(packed), raw=False)
        if not isinstance(decoded, list) or not decoded or decoded[0] != {"format": "cB", "version": 1}:
            raise ValueError("unexpected frequency format")
        metadata = archive.read("wordfreq-3.1.1.dist-info/METADATA").decode("utf-8")
    return decoded[1:], metadata[metadata.index("## License"):].strip() + "\n"


def curate(words):
    return [PROPER.get(word, word) for word in words]


def punctuated_observations(bins):
    return [[word, band] for band, tokens in enumerate(bins) if band <= PUNCTUATED_BAND_MAXIMUM
            for word in tokens if len(word) <= 18 and word == unicodedata.normalize("NFC", word)
            and re.fullmatch(r"[a-zàèéìîòù]+(?:[-'][a-zàèéìîòù]+)+", word)]


def scale_words(raw, count, punctuated=None):
    limit = LIMITS[next(name for name, size in COUNTS.items() if size == count)]
    extras = [row[0] for row in punctuated] + TECHNICAL_NAMES if count == COUNTS["60k"] and punctuated is not None else []
    return curate([word for word in raw if len(word) <= limit][:count - len(extras)]) + extras


def expand_band_runs(runs):
    if not isinstance(runs, list):
        raise ValueError("invalid frequency band runs")
    bands, previous = [], -1
    for run in runs:
        if (not isinstance(run, list) or len(run) != 2
                or any(type(x) is not int for x in run)):
            raise ValueError("invalid frequency band run")
        band, count = run
        if band <= previous or count <= 0 or len(bands) + count > OBSERVED_COUNT:
            raise ValueError("invalid frequency band order or size")
        bands.extend([band] * count)
        previous = band
    if len(bands) != OBSERVED_COUNT:
        raise ValueError("incomplete frequency band runs")
    return bands


def statistics(words):
    return {"count": len(words), "uniqueCount": len(set(words)),
            "minimumLength": min(map(len, words)), "maximumLength": max(map(len, words)),
            "uppercaseCount": sum(any(c.isupper() for c in word) for word in words),
            "nonLetterCount": sum(any(not c.isalpha() for c in word) for word in words),
            "punctuationCount": sum(any(unicodedata.category(c).startswith("P") for c in word) for word in words),
            "symbolCount": sum(any(unicodedata.category(c).startswith("S") for c in word) for word in words),
            "multiwordCount": sum(" " in word for word in words),
            "nonASCIICount": sum(not word.isascii() for word in words),
            "wordsSHA256": digest(("\n".join(words)+"\n").encode())}


def artifacts(raw, bands, candidate_count, source_notices, punctuated):
    if (len(raw) != OBSERVED_COUNT or len(set(raw)) != OBSERVED_COUNT or not all(map(eligible, raw))
            or len(bands) != OBSERVED_COUNT or bands != sorted(bands)
            or any(type(x) is not int or x < 0 for x in bands)
            or type(candidate_count) is not int or candidate_count < OBSERVED_COUNT):
        raise ValueError("invalid observed Italian data")
    if (not isinstance(punctuated, list) or not punctuated
            or any(not isinstance(row, list) or len(row) != 2
                   or type(row[0]) is not str or type(row[1]) is not int
                   or not 0 <= row[1] <= PUNCTUATED_BAND_MAXIMUM
                   or len(row[0]) > 18 or row[0] != unicodedata.normalize("NFC", row[0])
                   or not re.fullmatch(r"[a-zàèéìîòù]+(?:[-'][a-zàèéìîòù]+)+", row[0])
                   for row in punctuated)
            or punctuated != sorted(punctuated, key=lambda row: (row[1], row[0]))
            or len({row[0] for row in punctuated}) != len(punctuated)):
        raise ValueError("invalid punctuated observations")
    observed = curate(raw)
    scales = {name: scale_words(raw, count, punctuated) for name, count in COUNTS.items()}
    if any(len(words) != COUNTS[name] or len(set(words)) != COUNTS[name] for name, words in scales.items()):
        raise ValueError("Italian scale count or uniqueness mismatch")
    swift = ("// Generated by Scripts/prepare-italian-frequency-corpus.py; do not edit.\n"
             "// Independent wordfreq data and Typebar editorial contributions, CC BY-SA 4.0.\n"
             "// Attribution: Resources/ItalianFrequencyCorpusNotices.txt. No Monkeytype data.\n"
             "enum ItalianFrequencyCorpus {\n"
             f'  static let revision = "{REVISION}"\n'
             '  static let observedWords: [String] = """\n' + "\n".join(observed) + '\n""".split(separator: "\\n").map(String.init)\n')
    swift += ('  static let punctuatedWords: [String] = """\n' + "\n".join(row[0] for row in punctuated)
              + '\n""".split(separator: "\\n").map(String.init)\n'
              + '  static let technicalEditorialNames = ["C++", "C#"]\n')
    for name, count in COUNTS.items():
        # Small choices must not initialize the full 280k array on first use.
        if name in ("1k", "7k"):
            swift += f'  static let words{name}: [String] = """\n' + "\n".join(scales[name]) + '\n""".split(separator: "\\n").map(String.init)\n'
            continue
        selection = f'observedWords.filter {{ $0.count <= {LIMITS[name]} }}' if name != '280k' else 'observedWords'
        if name == '60k':
            swift += f'  static let words{name} = Array({selection}.prefix({count} - punctuatedWords.count - technicalEditorialNames.count)) + punctuatedWords + technicalEditorialNames\n'
        else:
            swift += f'  static let words{name} = Array({selection}.prefix({count}))\n'
    swift += "}\n"
    notices = ("Typebar Italian corpus tokens, revision 2\n"
               "Adapted selection and editorial contributions by Typebar contributors (2026), CC BY-SA 4.0.\n"
               "https://creativecommons.org/licenses/by-sa/4.0/\n"
               "Source: Robyn Speer / wordfreq 3.1.1\nhttps://pypi.org/project/wordfreq/3.1.1/\n"
               "Changes: select NFC lowercase Italian-letter tokens of at most 25 characters;\n"
               "single a/e/i/o/è only; preserve frequency-band order and apply explicit exclusions.\n"
               "Independently authored geographic case variants refer to lowercase source\n"
               "frequency evidence. Caps: 1k at 14 characters; 7k and 60k at 18; 280k at 25.\n"
               "The 60k selection reserves room for observed Italian apostrophe/hyphen tokens\n"
               "in frequency bands up to 450, plus C++ and C# as explicitly unranked technical\n"
               "editorial names. These are not measured frequency claims. No padding tokens.\n"
               "Editorial contributions share the data license.\n"
               "Names, loans, brands and colloquial/vulgar tokens may remain. Not a certified\n"
               "dictionary or equivalent reference distribution. No reference words or assets.\n"
               "The data license is CC BY-SA 4.0, not wordfreq code's Apache license.\n\n"
               + NOTICE_MARKER + source_notices)
    manifest = {"schemaVersion": 2, "revision": REVISION, "observedCount": len(raw),
                "candidateCount": candidate_count,
                "observedFrequencyBandRuns": [[band, sum(1 for _ in items)] for band, items in groupby(bands)],
                "selectionLengthCaps": LIMITS,
                "selection": "NFC lowercase Italian letters; maximum 25; single a/e/i/o/è; explicit exclusions; frequency-bin order",
                "excludedTokens": sorted(EXCLUDED), "properNameVariants": PROPER,
                "unrankedEditorialAdditions": ADDITIONS,
                "punctuatedObservations60k": punctuated,
                "punctuatedBandMaximum": PUNCTUATED_BAND_MAXIMUM,
                "technicalEditorialNames60k": TECHNICAL_NAMES,
                "qualityBoundary": "observed corpus tokens and explicit editorial forms, not dictionary certification or reference parity",
                "scales": {name: statistics(words) for name, words in scales.items()},
                "wordfreq": {"version": "3.1.1", "wheelSHA256": WHEEL_SHA,
                             "member": MEMBER, "memberSHA256": MEMBER_SHA},
                "preparationDependency": "msgpack==1.1.2 (build-time only)",
                "dataLicense": "CC-BY-SA-4.0; retain full wordfreq source credits",
                "swiftSHA256": digest(swift.encode()), "noticesSHA256": digest(notices.encode())}
    return {SWIFT: swift.encode(), NOTICES: notices.encode(),
            MANIFEST: (json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True)+"\n").encode()}


def publish(outputs, root, check=False):
    if check:
        for path, data in outputs.items():
            if not (root/path).is_file() or (root/path).read_bytes() != data:
                raise ValueError(f"generated artifact mismatch: {path}")
    else:
        if any((root/path).exists() for path in outputs):
            raise ValueError("refusing to overwrite artifacts; use --check or a fresh output root")
        for path, data in outputs.items():
            (root/path).parent.mkdir(parents=True, exist_ok=True)
            (root/path).write_bytes(data)


def verify_bundled(root):
    swift = (root/SWIFT).read_text()
    match = re.search(r'static let observedWords: \[String\] = """\n(.*?)\n"""', swift, re.S)
    if not match:
        raise ValueError("missing observed Italian data")
    words = match.group(1).splitlines()
    raw = [word.lower() for word in words]
    if curate(raw) != words:
        raise ValueError("Italian editorial case mismatch")
    manifest = json.loads((root/MANIFEST).read_text())
    notices = (root/NOTICES).read_text().split(NOTICE_MARKER)
    if len(notices) != 2 or not notices[1].startswith("## License\n"):
        raise ValueError("missing Italian source attribution")
    publish(artifacts(raw, expand_band_runs(manifest["observedFrequencyBandRuns"]), manifest["candidateCount"], notices[1],
                      manifest["punctuatedObservations60k"]), root, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--wordfreq-wheel", type=Path)
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--check-bundled", action="store_true")
    args = parser.parse_args()
    if args.check_bundled:
        if args.check or args.wordfreq_wheel:
            parser.error("--check-bundled is a separate offline integrity mode")
        verify_bundled(args.output_root)
        print("Bundled Italian corpus integrity passed (not upstream reproduction)")
    else:
        if not args.wordfreq_wheel:
            parser.error("--wordfreq-wheel is required")
        bins, notices = read_source(args.wordfreq_wheel)
        raw, bands, candidates = select(bins)
        publish(artifacts(raw, bands, candidates, notices, punctuated_observations(bins)), args.output_root, args.check)
        print("Italian corpus source preparation verified" if args.check else "Italian corpus prepared")


if __name__ == "__main__":
    main()
