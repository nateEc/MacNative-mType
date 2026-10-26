#!/bin/zsh
set -euo pipefail
# QA only. Keep this archive outside the app and the reference checkout.
(( $# == 0 )) || { print -u2 -- "usage: $0"; exit 1; }
qa_directory=""
keep_directory=0
cleanup() {
  if [[ -n "$qa_directory" && "$keep_directory" == 0 ]]; then
    rm -rf -- "$qa_directory"
  fi
}
trap cleanup EXIT
archive="${TYPEBAR_LINE_SCROLL_ANIME_ARCHIVE:-}"
if [[ -n "$archive" ]]; then
  [[ "$archive" == /* && -f "$archive" ]] || { print -u2 -- "QA animation archive must be an existing absolute file"; exit 1; }
else
  qa_directory="$(mktemp -d "${TMPDIR:-/tmp}/typebar-anime-qa.XXXXXX")"
  archive="$qa_directory/animejs-4.2.2.tgz"
  curl --fail --silent --show-error --location \
    https://registry.npmjs.org/animejs/-/animejs-4.2.2.tgz -o "$archive" || {
      download_exit_code=$?
      print -u2 -- "QA animation archive download failed"
      exit "$download_exit_code"
    }
fi
[[ "$archive" != *$'\n'* && "$archive" != *$'\r'* ]] || { print -u2 -- "QA archive path must fit on one environment-file line"; exit 1; }
node - "$archive" <<'JS'
const fs = require('node:fs'), crypto = require('node:crypto'), assert = require('node:assert/strict');
const {execFileSync} = require('node:child_process');
const archive = process.argv[2];
const actual = 'sha512-' + crypto.createHash('sha512').update(fs.readFileSync(archive)).digest('base64');
assert.equal(actual, 'sha512-Ys3RuvLdAeI14fsdKCQy7ytu4057QX6Bb7m4jwmfd6iKmUmLquTwk1ut0e4NtRQgCeq/s2Lv5+oMBjz6c7ZuIg==');
const metadata = JSON.parse(execFileSync('tar', ['-xOf', archive, 'package/package.json'], {encoding: 'utf8'}));
assert.equal(metadata.name, 'animejs'); assert.equal(metadata.version, '4.2.2');
JS
keep_directory=1
print -r -- "$archive"
