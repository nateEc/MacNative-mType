#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

def fail_audit(message)
  warn "theme compatibility audit failed: #{message}"
  exit 1
end

reference_root = ARGV.fetch(0) { fail_audit("provide the absolute reference checkout path") }
fail_audit("reference checkout path must be absolute") unless reference_root.start_with?("/")

project_root = File.expand_path("..", __dir__)
fixture_path = File.join(project_root, "Compatibility/official-themes.json")
audit_path = File.join(project_root, "OFFICIAL_THEME_AUDIT.md")
inventory_path = File.join(project_root, "FUNCTIONAL_INVENTORY.md")
native_path = File.join(project_root, "Sources/Typebar/AppTheme.swift")
source_path = File.join(reference_root, "packages/schemas/src/themes.ts")
[fixture_path, audit_path, inventory_path, native_path, source_path].each do |path|
  fail_audit("missing #{path}") unless File.file?(path)
end

fixture = JSON.parse(File.read(fixture_path))
expected_keys = %w[referenceRepository referenceCommit sourceFile officialCount officialNames nativeBuiltInThemes exactMappings relatedMappings]
fail_audit("fixture includes unexpected fields") unless fixture.keys.sort == expected_keys.sort
fail_audit("unexpected source file") unless fixture.fetch("sourceFile") == "packages/schemas/src/themes.ts"
commit, status = Open3.capture2("git", "-C", reference_root, "rev-parse", "HEAD")
fail_audit("reference checkout is unavailable") unless status.success?
fail_audit("reference commit differs from fixture") unless commit.strip == fixture.fetch("referenceCommit")

schema = File.read(source_path)
names_block = schema.match(/export const ThemeNameSchema = z\.enum\(\s*\[(.*?)\]\s*,/m)
fail_audit("cannot locate ThemeNameSchema") unless names_block
names = names_block[1].scan(/"([^"]+)"/).flatten
fail_audit("duplicate official theme identity") unless names.uniq.length == names.length
fail_audit("official theme count drift") unless names.length == fixture.fetch("officialCount")
fail_audit("official theme identities drift") unless names == fixture.fetch("officialNames")

native = File.read(native_path)
native_block = native.match(/enum AppTheme:.*?\{(.*?)\n\s*var displayName:/m)
fail_audit("cannot locate native AppTheme cases") unless native_block
native_names = native_block[1].scan(/^\s*case\s+(\w+)\s*$/).flatten
fail_audit("native built-in theme identities drift") unless native_names == fixture.fetch("nativeBuiltInThemes")

mappings = fixture.fetch("exactMappings")
fail_audit("exactMappings must be an object") unless mappings.is_a?(Hash)
fail_audit("mapping names are outside fixed schema") unless (mappings.keys - names).empty?
fail_audit("mapping targets are not native built-ins") unless (mappings.values - native_names).empty?
fail_audit("one native theme cannot be exact for multiple official themes") unless mappings.values.uniq == mappings.values

related = fixture.fetch("relatedMappings")
fail_audit("relatedMappings must be an object") unless related.is_a?(Hash)
fail_audit("related names are outside fixed schema") unless (related.keys - names).empty?
fail_audit("related targets are not native built-ins") unless (related.values - native_names).empty?
fail_audit("exact and related mappings overlap") unless (related.keys & mappings.keys).empty?
fail_audit("one native theme cannot represent multiple related identities") unless related.values.uniq == related.values

pending_count = names.length - mappings.length
unmapped_count = pending_count - related.length
audit = File.read(audit_path)
inventory = File.read(inventory_path)
summary = "#{names.length} 个官方主题身份、#{mappings.length} 个已验证精确原生映射、#{pending_count} 个待映射"
fail_audit("theme audit summary drift") unless audit.include?(summary)
fail_audit("functional inventory summary drift") unless inventory.include?(summary)
related_summary = "#{related.length} 个原创相关替代、#{unmapped_count} 个尚无相关替代"
fail_audit("related theme audit summary drift") unless audit.include?(related_summary)
fail_audit("related functional inventory summary drift") unless inventory.include?(related_summary)

puts "theme compatibility audit passed (#{summary}; #{related_summary} at #{commit.strip}; no theme assets)"
