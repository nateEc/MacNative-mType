#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "pathname"

PINNED_COMMIT = "91bd24bb8513785c7364cbea29296ff7adafac41"
EXPECTED_COUNTS = {
  official: 94,
  mapped: 82,
  partial: 11,
  not_applicable: 1,
  unimplemented: 0,
  untracked: 0,
}.freeze

def fail_audit(message)
  warn "config audit failed: #{message}"
  exit 1
end

repository_root = Pathname.new(__dir__).parent
reference_root = ARGV[0] && Pathname.new(ARGV[0]).expand_path
output_path = ARGV[1] ? Pathname.new(ARGV[1]).expand_path :
  repository_root.join("Compatibility/official-configs.json")
fail_audit("usage: #{$PROGRAM_NAME} MONKEYTYPE_REFERENCE [OUTPUT]") unless reference_root

commit, status = Open3.capture2("git", "-C", reference_root.to_s, "rev-parse", "HEAD")
fail_audit("could not read reference commit") unless status.success?
fail_audit("reference must be pinned to #{PINNED_COMMIT}") unless commit.strip == PINNED_COMMIT

schema_relative_path = "packages/schemas/src/configs.ts"
audit_relative_path = "OFFICIAL_CONFIG_AUDIT.md"
schema_source = reference_root.join(schema_relative_path).read
audit_source = repository_root.join(audit_relative_path).read

schema_match = schema_source.match(
  /export const ConfigSchema = z\s*\.object\(\{(.*?)\}\s+satisfies Record<string, ZodSchema>/m)
fail_audit("could not locate ConfigSchema object") unless schema_match
official_keys = schema_match[1].scan(/^\s{4}([A-Za-z][A-Za-z0-9]*):/).flatten
fail_audit("official keys are not unique") unless official_keys.uniq.length == official_keys.length

rows = audit_source.scan(/^\| `([^`]+)` \| ([^|]+) \| ([^|]+) \|$/)
tracked = {}
rows.each do |key, typebar_mapping, evidence|
  fail_audit("audit row #{key} is not an official ConfigSchema key") unless official_keys.include?(key)
  fail_audit("duplicate audit row for #{key}") if tracked.key?(key)

  status_name = if evidence.strip.start_with?("已映射")
    :mapped
  elsif evidence.strip.start_with?("部分")
    :partial
  elsif evidence.strip.start_with?("不适用")
    :not_applicable
  elsif evidence.strip.start_with?("未实现")
    :unimplemented
  else
    fail_audit("unknown status for #{key}: #{evidence.strip}")
  end
  mapping = typebar_mapping.strip
  fail_audit("empty Typebar mapping for #{key}") if mapping.empty?
  tracked[key] = [status_name, mapping]
end

partitions = {
  mapped: {},
  partial: {},
  not_applicable: {},
  unimplemented: {},
}
tracked.each do |key, (status_name, mapping)|
  partitions.fetch(status_name)[key] = mapping
end
untracked = official_keys.reject { |key| tracked.key?(key) }

actual_counts = {
  official: official_keys.length,
  mapped: partitions.fetch(:mapped).length,
  partial: partitions.fetch(:partial).length,
  not_applicable: partitions.fetch(:not_applicable).length,
  unimplemented: partitions.fetch(:unimplemented).length,
  untracked: untracked.length,
}
fail_audit("unexpected classification counts: #{actual_counts}") unless actual_counts == EXPECTED_COUNTS

fixture = {
  referenceRepository: "monkeytypegame/monkeytype",
  referenceCommit: PINNED_COMMIT,
  officialCount: official_keys.length,
  officialKeys: official_keys,
  mapped: partitions.fetch(:mapped),
  partial: partitions.fetch(:partial),
  notApplicable: partitions.fetch(:not_applicable),
  unimplemented: partitions.fetch(:unimplemented),
  untrackedOfficialKeys: untracked,
  sourceFiles: [schema_relative_path, audit_relative_path],
  method: "metadata only; statuses and Typebar mapping labels come from the compatibility table, while evidence remains in the audit document",
}

output_path.write(JSON.pretty_generate(fixture) + "\n")
puts "wrote #{output_path} (#{actual_counts})"
