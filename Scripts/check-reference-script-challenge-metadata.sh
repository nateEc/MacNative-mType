#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
fixture="$project_root/Compatibility/official-script-challenges.json"
challenge_fixture="$project_root/Compatibility/official-challenges.json"

(( $# == 1 )) || { print -u2 -- "usage: $0 /absolute/path/to/monkeytype-reference"; exit 1; }
reference_root="$1"
[[ "$reference_root" = /* ]] || { print -u2 -- "reference path must be absolute"; exit 1; }
[[ -f "$fixture" && -f "$challenge_fixture" ]] || {
  print -u2 -- "script challenge metadata fixture is missing"
  exit 1
}
expected_commit="$(jq -er '.referenceCommit' "$challenge_fixture")"
actual_commit="$(git -C "$reference_root" rev-parse HEAD)"
[[ "$actual_commit" == "$expected_commit" ]] || {
  print -u2 -- "reference commit differs from the pinned challenge fixture"
  exit 1
}

ruby -rjson -rdigest -e '
  fixture, challenge_fixture, reference_root = ARGV
  specs = JSON.parse(File.read(fixture))
  official = JSON.parse(File.read(challenge_fixture)).fetch("officialNames")
  names = specs.map { |spec| spec.fetch("legacyName") }
  abort "script metadata names are duplicated or unknown" unless
    names.uniq.length == 11 && (names - official).empty?
  specs.each do |spec|
    file_name = spec.fetch("fileName")
    abort "unsafe script file name" unless /\A[a-z0-9]+\.txt\z/.match?(file_name)
    path = File.join(reference_root, "frontend/static/challenges", file_name)
    source = File.binread(path).force_encoding("UTF-8")
    abort "invalid reference UTF-8: #{file_name}" unless source.valid_encoding?
    normalized = source.strip.gsub(/[\n\r\t ]/, " ").gsub(/ +/, " ")
    abort "byte count drift: #{file_name}" unless source.bytesize == spec.fetch("byteCount")
    abort "normalized length drift: #{file_name}" unless normalized.length == spec.fetch("normalizedCharacterCount")
    abort "normalized digest drift: #{file_name}" unless
      Digest::SHA256.hexdigest(normalized) == spec.fetch("normalizedSHA256")
  end
  puts "reference script challenge metadata check passed (#{specs.length} pinned fingerprints)"
' "$fixture" "$challenge_fixture" "$reference_root"
