#!/usr/bin/env python3
"""Prepare independent Spanish corpus tokens, not a certified dictionary.

No downloads or package installation. msgpack==1.1.2 is preparation-only;
--check-bundled needs only the standard library. Never read reference words.
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

WHEEL_SHA = "4b1c6ecffc6198be3396d5cf871c4423ca71c907c231348d352dd54d62b97473"
MEMBER = "wordfreq/data/large_es.msgpack.gz"
MEMBER_SHA = "14f326b4f68d517f9b8b99c1e26ef56a508d2dc8d0ee7a9e6e8732ddab1aa65e"
COUNT = 998
SCALE_COUNT = 9990
SCALE_OBSERVED_COUNT = SCALE_COUNT - 1
BASE_SHA = "19d1313ce798ffcc13d942604a8cb37779da08c0e57ea2303179a0b750d42a0c"
REVISION = "wordfreq-3.1.1-es-v2"
SWIFT = Path("Sources/Typebar/SpanishFrequencyCorpus.generated.swift")
MANIFEST = Path("Compatibility/spanish-frequency-corpus.json")
NOTICES = Path("Resources/SpanishFrequencyCorpusNotices.txt")
NOTICE_MARKER = "=== wordfreq 3.1.1 release metadata ===\n"
# Independent editorial exclusions: frequent foreign function words, selected
# abbreviations/Roman numerals, and common missing-accent spellings. This is
# deliberately explicit, not a hidden claim of exhaustive language detection.
EXCLUDED = frozenset("the of and in pp sr etc ii iii asi dia tambien aqui".split())
# Independently authored proper-name variants. Frequency evidence remains for
# the lowercase observed form, not for a separately measured capitalized form.
PROPER_NAMES = """
Alberto Alejandro Alicia Ana Andrés Antonio Carlos Carmen Cristina Daniel David
Diego Eduardo Elena Enrique Fernando Francisco Gabriel Isabel Javier Jesús Jorge
José Juan Leonardo Luis Manuel María Mario Miguel Pablo Pedro Rafael Ramón Raúl
Ricardo Roberto Rubén Sergio Silvia Teresa Vicente Víctor Álvaro Óscar
Alemania América Argentina Asia Australia Austria Bélgica Bolivia Brasil Canadá
Chile China Colombia Cuba Dinamarca Ecuador Egipto España Europa Finlandia
Francia Grecia Guatemala Honduras India Irlanda Italia Japón Marruecos México
Nicaragua Nigeria Noruega Panamá Paraguay Perú Polonia Portugal Rusia Suecia
Suiza Turquía Ucrania Uruguay Venezuela África
Barcelona Bilbao Bogotá Córdoba Granada Lima Lisboa Londres Madrid Málaga
Montevideo Murcia París Quito Roma Salamanca Santiago Sevilla Toledo Valencia
Zaragoza
""".split()
PROPER_BY_LOWER = {word.lower(): word for word in PROPER_NAMES}
SCALE_EXCLUDED = EXCLUDED | frozenset("espana mexico peru jose maria jesus alvaro".split())
EDITORIAL_COMPOUND = "teórico-práctico"


def digest(data):
    return hashlib.sha256(data).hexdigest()


def eligible(word, scale=False):
    return (word == unicodedata.normalize("NFC", word)
            and re.fullmatch(r"(?:[a-záéíóúüñ]{2,}|[aeouy])", word) is not None
            and word not in (SCALE_EXCLUDED if scale else EXCLUDED)
            and (not scale or len(word) <= 20))


def select(bins, count=COUNT, scale=False):
    if type(count) is not int or count < 1:
        raise ValueError("count must be positive")
    if not isinstance(bins, list):
        raise ValueError("frequency bins must be an array")
    words, bands, seen = [], [], set()
    for band, tokens in enumerate(bins):
        if (not isinstance(tokens, list) or any(type(x) is not str for x in tokens)
                or tokens != sorted(tokens) or len(set(tokens)) != len(tokens)):
            raise ValueError("frequency band must contain sorted unique strings")
        for word in tokens:
            if word in seen:
                raise ValueError("token appears in multiple bands")
            seen.add(word)
            if eligible(word, scale):
                words.append(word)
                bands.append(band)
    if len(words) < count:
        raise ValueError("insufficient eligible observed tokens; never pad")
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
            raise ValueError("Spanish member SHA-256 mismatch")
        decoded = msgpack.unpackb(gzip.decompress(packed), raw=False)
        if not isinstance(decoded, list) or not decoded or decoded[0] != {"format": "cB", "version": 1}:
            raise ValueError("unexpected frequency format")
        metadata = archive.read("wordfreq-3.1.1.dist-info/METADATA").decode("utf-8")
    return decoded[1:], metadata[metadata.index("## License"):].strip() + "\n"


def curate_scale(words):
    return [PROPER_BY_LOWER.get(word, word) for word in words] + [EDITORIAL_COMPOUND]


def artifacts(words, bands, candidate_count, source_notices, scale_raw, scale_bands, scale_candidates):
    body = "\n".join(words) + "\n"
    if digest(body.encode()) != BASE_SHA:
        raise ValueError("existing Spanish 1k data must not drift")
    if (len(scale_raw) != SCALE_OBSERVED_COUNT or len(set(scale_raw)) != SCALE_OBSERVED_COUNT
            or not all(eligible(word, True) for word in scale_raw)
            or len(scale_bands) != SCALE_OBSERVED_COUNT or scale_bands != sorted(scale_bands)
            or any(type(x) is not int or x < 0 for x in scale_bands)
            or type(scale_candidates) is not int or scale_candidates < SCALE_OBSERVED_COUNT):
        raise ValueError("invalid Spanish 10k observed selection")
    if (len(PROPER_NAMES) != len(PROPER_BY_LOWER)
            or any(not eligible(word.lower(), True) or word != unicodedata.normalize('NFC', word)
                   or not word[0].isupper() or not word[1:].islower() for word in PROPER_NAMES)):
        raise ValueError("invalid independent proper-name policy")
    scale_words = curate_scale(scale_raw)
    scale_body = "\n".join(scale_words) + "\n"
    swift = ("// Generated by Scripts/prepare-spanish-frequency-corpus.py; do not edit.\n"
             "// Independent wordfreq data adapted by Typebar contributors, CC BY-SA 4.0.\n"
             "// Attribution: Resources/SpanishFrequencyCorpusNotices.txt. No Monkeytype data.\n"
             "enum SpanishFrequencyCorpus {\n"
             f'  static let revision = "{REVISION}"\n'
             '  static let words: [String] = """\n' + body +
             '""".split(separator: "\\n").map(String.init)\n'
             '  static let extendedWords: [String] = """\n' + scale_body +
             '""".split(separator: "\\n").map(String.init)\n}\n')
    notices = ("Typebar Spanish corpus tokens, revision 2\n"
               "Adapted selection by Typebar contributors (2026), CC BY-SA 4.0.\n"
               "https://creativecommons.org/licenses/by-sa/4.0/\n"
               "Source: Robyn Speer / wordfreq 3.1.1\n"
               "https://pypi.org/project/wordfreq/3.1.1/\n"
               "Changes: retain frequency-band order; select NFC lowercase Spanish-letter\n"
               "tokens; retain single a/e/o/u/y only; apply the explicit editorial\n"
               "exclusions in the preparation script; retain the original 998 base tokens.\n"
               "Spanish 10k: select 9989 observed tokens of at most 20 characters, with\n"
               "additional explicit missing-accent exclusions. Independently authored\n"
               "proper-name variants restore case; their frequency evidence is for the\n"
               "lowercase form. Append the independently authored, unranked compound\n"
               "teórico-práctico. These editorial contributions share the data license.\n"
               "Names, loans, brands and colloquial/vulgar language may remain. This is\n"
               "observed corpus vocabulary, not dictionary certification or source parity.\n"
               "No reference-project values, code or assets are imported.\n"
               "The data license is CC BY-SA 4.0, not wordfreq code's Apache license.\n\n"
               + NOTICE_MARKER + source_notices)
    manifest = {"schemaVersion": 1, "revision": REVISION, "count": len(words),
                "uniqueCount": len(set(words)), "candidateCount": candidate_count,
                "minimumLength": min(map(len, words)), "maximumLength": max(map(len, words)),
                "uppercaseCount": 0, "multiwordCount": 0,
                "nonASCIICount": sum(not word.isascii() for word in words),
                "frequencyBands": bands, "excludedTokens": sorted(EXCLUDED),
                "selection": "NFC lowercase Spanish letters; single a/e/o/u/y only; explicit exclusions; frequency-band order",
                "qualityBoundary": "observed corpus tokens and explicit editorial forms, not dictionary or linguistic certification",
                "scale10k": {
                    "count": len(scale_words), "uniqueCount": len(set(scale_words)),
                    "observedCount": len(scale_raw), "candidateCount": scale_candidates,
                    "observedFrequencyBands": scale_bands,
                    "excludedTokens": sorted(SCALE_EXCLUDED), "maximumAllowedObservedLength": 20,
                    "properNamePolicy": sorted(PROPER_NAMES),
                    "appliedProperNames": [word for word in scale_words if word[0].isupper()],
                    "unrankedEditorialAdditions": [EDITORIAL_COMPOUND],
                    "minimumLength": min(map(len, scale_words)), "maximumLength": max(map(len, scale_words)),
                    "uppercaseCount": sum(any(c.isupper() for c in word) for word in scale_words),
                    "nonASCIICount": sum(not word.isascii() for word in scale_words),
                    "multiwordCount": 0, "punctuationCount": 1,
                    "wordsSHA256": digest(scale_body.encode())},
                "wordfreq": {"version": "3.1.1", "wheelSHA256": WHEEL_SHA,
                             "member": MEMBER, "memberSHA256": MEMBER_SHA},
                "preparationDependency": "msgpack==1.1.2 (build-time only)",
                "dataLicense": "CC-BY-SA-4.0; retain full wordfreq source credits",
                "wordsSHA256": digest(body.encode()), "swiftSHA256": digest(swift.encode()),
                "noticesSHA256": digest(notices.encode())}
    return {SWIFT: swift.encode(), NOTICES: notices.encode(),
            MANIFEST: (json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode()}


def publish(outputs, root, check=False):
    if check:
        for path, data in outputs.items():
            if not (root / path).is_file() or (root / path).read_bytes() != data:
                raise ValueError(f"generated artifact mismatch: {path}")
        return
    if any((root / path).exists() for path in outputs):
        raise ValueError("refusing to replace existing artifacts; use --check or a fresh output root")
    for path, data in outputs.items():
        target = root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)


def verify_bundled(root):
    swift = (root / SWIFT).read_text()
    match = re.search(r'static let words: \[String\] = """\n(.*?)\n"""', swift, re.S)
    if not match:
        raise ValueError("missing native word data")
    words = match.group(1).splitlines()
    scale_match = re.search(r'static let extendedWords: \[String\] = """\n(.*?)\n"""', swift, re.S)
    if not scale_match:
        raise ValueError("missing native Spanish 10k data")
    scale_words = scale_match.group(1).splitlines()
    if (len(scale_words) != SCALE_COUNT or len(set(scale_words)) != SCALE_COUNT
            or scale_words[-1] != EDITORIAL_COMPOUND):
        raise ValueError("bundled Spanish 10k shape mismatch")
    scale_raw = [word.lower() for word in scale_words[:-1]]
    if curate_scale(scale_raw) != scale_words:
        raise ValueError("bundled Spanish 10k editorial forms mismatch")
    manifest = json.loads((root / MANIFEST).read_text())
    bands = manifest["frequencyBands"]
    if (len(words) != COUNT or len(set(words)) != COUNT or not all(map(eligible, words))
            or len(bands) != COUNT or any(type(x) is not int or x < 0 for x in bands)
            or bands != sorted(bands) or type(manifest["candidateCount"]) is not int
            or manifest["candidateCount"] < COUNT):
        raise ValueError("bundled word/band contract mismatch")
    notices = (root / NOTICES).read_text().split(NOTICE_MARKER)
    if len(notices) != 2 or not notices[1].startswith("## License\n"):
        raise ValueError("missing source attribution")
    scale = manifest["scale10k"]
    publish(artifacts(words, bands, manifest["candidateCount"], notices[1], scale_raw,
                      scale["observedFrequencyBands"], scale["candidateCount"]), root, check=True)


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
        print("Bundled Spanish corpus integrity passed (not upstream reproduction)")
    else:
        if not args.wordfreq_wheel:
            parser.error("--wordfreq-wheel is required for source preparation")
        bins, notices = read_source(args.wordfreq_wheel)
        words, bands, candidates = select(bins)
        scale_words, scale_bands, scale_candidates = select(bins, SCALE_OBSERVED_COUNT, scale=True)
        publish(artifacts(words, bands, candidates, notices, scale_words, scale_bands, scale_candidates), args.output_root, args.check)
        print("Spanish corpus source preparation verified" if args.check else "Spanish corpus artifacts created")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError, zipfile.BadZipFile) as error:
        sys.exit(str(error))
