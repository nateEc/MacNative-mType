#!/bin/zsh
set -euo pipefail
# QA only; no install hooks, and no dependency enters the application bundle.
(( $# == 0 )) || { print -u2 -- "usage: $0"; exit 1; }
qa_directory=""
keep_directory=0
cleanup() {
  if [[ -n "$qa_directory" && "$keep_directory" == 0 ]]; then rm -rf -- "$qa_directory"; fi
}
trap cleanup EXIT
archive="${TYPEBAR_SOLID_QA_ARCHIVE:-}"
if [[ -n "$archive" ]]; then
  [[ "$archive" == /* && -f "$archive" ]] || { print -u2 -- "QA Solid archive must be an existing absolute file"; exit 1; }
else
  qa_directory="$(mktemp -d "${TMPDIR:-/tmp}/typebar-solid-qa.XXXXXX")"
  archive="$qa_directory/solid-js-1.9.13.tgz"
  curl --fail --silent --show-error --location \
    https://registry.npmjs.org/solid-js/-/solid-js-1.9.13.tgz -o "$archive" || {
      download_exit_code=$?
      print -u2 -- "QA Solid archive download failed"
      exit "$download_exit_code"
    }
fi
[[ "$archive" != *$'\n'* && "$archive" != *$'\r'* ]] || { print -u2 -- "QA archive path must fit on one environment-file line"; exit 1; }
node - "$archive" <<'JS'
const fs = require('node:fs'), crypto = require('node:crypto'), assert = require('node:assert/strict');
const {execFileSync} = require('node:child_process');
const archive = process.argv[2];
assert.equal('sha512-' + crypto.createHash('sha512').update(fs.readFileSync(archive)).digest('base64'),
  'sha512-6hJeJMOcEX8ktqjpDoJZEmld3ijvcvWBDtiXBm7f4332SiFN66QeAQI1REQshvyUoISsSeJ4PHDauKYbwao9JQ==');
const metadata = JSON.parse(execFileSync('tar', ['-xOf', archive, 'package/package.json'], {encoding: 'utf8'}));
assert.equal(metadata.name, 'solid-js'); assert.equal(metadata.version, '1.9.13');
JS
keep_directory=1
print -r -- "$archive"
