#!/bin/zsh
set -euo pipefail
# QA dependency only, never copied into Typebar or the reference checkout.
qa_directory="$(mktemp -d "${TMPDIR:-/tmp}/typebar-config-schema.XXXXXX")"
curl --fail --silent --show-error --location \
  https://registry.npmjs.org/zod/-/zod-3.23.8.tgz -o "$qa_directory/zod.tgz"
node - "$qa_directory/zod.tgz" <<'JS'
const fs = require('node:fs'), crypto = require('node:crypto'), assert = require('node:assert/strict');
const actual = 'sha512-' + crypto.createHash('sha512').update(fs.readFileSync(process.argv[2])).digest('base64');
assert.equal(actual, 'sha512-XBx9AXhXktjUqnepgTiE5flcKIYWi/rme0Eaj+5Y0lftuGBq+jyRu/md4WnuxqgP1ubdpNCsYEYPxrzVHD8d6g==');
JS
tar -xzf "$qa_directory/zod.tgz" -C "$qa_directory"
node - "$qa_directory/package/package.json" <<'JS'
const fs = require('node:fs'), assert = require('node:assert/strict');
const metadata = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
assert.equal(metadata.name, 'zod'); assert.equal(metadata.version, '3.23.8');
JS
print -r -- "$qa_directory/package"
