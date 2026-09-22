#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "pathname"

PINNED_COMMIT = "91bd24bb8513785c7364cbea29296ff7adafac41"
EXPECTED_COUNTS = {
  official: 94,
  mapped: 92,
  partial: 1,
  not_applicable: 1,
  unimplemented: 0,
  untracked: 0,
}.freeze

# These groups describe Typebar's independently authored implementation
# surfaces. They are kept here rather than inferred from the compatibility
# table so the generated fixture remains the single, reproducible contract
# consumed by the native coverage tests.
NATIVE_EVIDENCE_GROUPS = {
  "test" => {
    "keys" => %w[punctuation numbers words time mode quoteLength language burstHeatmap],
    "nativeFiles" => %w[
      Sources/Typebar/TypingEngine.swift
      Sources/Typebar/TypebarApp.swift
      Sources/Typebar/PresetApplicationPolicy.swift
    ],
  },
  "behavior" => {
    "keys" => %w[
      difficulty quickRestart repeatQuotes resultSaving blindMode
      alwaysShowWordsHistory singleListCommandLine minWpm minWpmCustomSpeed
      minAcc minAccCustom minBurst minBurstCustomSpeed britishEnglish funbox
      customLayoutfluid customPolyglot
    ],
    "nativeFiles" => %w[
      Sources/Typebar/AppSettings.swift
      Sources/Typebar/TypingEngine.swift
      Sources/Typebar/PresetApplicationPolicy.swift
    ],
  },
  "input" => {
    "keys" => %w[
      freedomMode strictSpace oppositeShiftMode stopOnError deleteOnError
      confidenceMode quickEnd indicateTypos compositionDisplay hideExtraLetters
      lazyMode layout codeUnindentOnBackspace
    ],
    "nativeFiles" => %w[
      Sources/Typebar/AppSettings.swift
      Sources/Typebar/NativeTypingInput.swift
      Sources/Typebar/KeyboardGuide.swift
      Sources/Typebar/PresetApplicationPolicy.swift
    ],
  },
  "sound" => {
    "keys" => %w[soundVolume playSoundOnClick playSoundOnError playTimeWarning],
    "nativeFiles" => %w[
      Sources/Typebar/AppSettings.swift
      Sources/Typebar/TypingFeedbackSound.swift
      Sources/Typebar/PresetApplicationPolicy.swift
    ],
  },
  "caret" => {
    "keys" => %w[
      smoothCaret caretStyle paceCaret paceCaretCustomSpeed paceCaretStyle repeatedPace
    ],
    "nativeFiles" => %w[
      Sources/Typebar/AppSettings.swift
      Sources/Typebar/PromptCaretOverlay.swift
      Sources/Typebar/PaceGuide.swift
      Sources/Typebar/PresetApplicationPolicy.swift
    ],
  },
  "appearance" => {
    "keys" => %w[
      timerStyle liveSpeedStyle liveAccStyle liveBurstStyle timerColor timerOpacity
      highlightMode typedEffect tapeMode tapeMargin smoothLineScroll showAllLines
      alwaysShowDecimalPlaces typingSpeedUnit startGraphsAtZero maxLineWidth
      fontSize fontFamily keymapMode keymapLayout keymapStyle keymapLegendStyle
      keymapKeys keymapSize
    ],
    "nativeFiles" => %w[
      Sources/Typebar/AppSettings.swift
      Sources/Typebar/TypebarApp.swift
      Sources/Typebar/KeyboardGuide.swift
      Sources/Typebar/NativePracticeFont.swift
      Sources/Typebar/PresetApplicationPolicy.swift
    ],
  },
  "theme" => {
    "keys" => %w[
      flipTestColors colorfulMode customBackground customBackgroundSize
      customBackgroundFilter autoSwitchTheme themeLight themeDark randomTheme
      favThemes theme customTheme customThemeColors
    ],
    "nativeFiles" => %w[
      Sources/Typebar/AppSettings.swift
      Sources/Typebar/AppTheme.swift
      Sources/Typebar/PresetApplicationPolicy.swift
    ],
  },
  "hideElements" => {
    "keys" => %w[showKeyTips showOutOfFocusWarning capsLockWarning showAverage showPb],
    "nativeFiles" => %w[
      Sources/Typebar/AppSettings.swift
      Sources/Typebar/TypebarApp.swift
      Sources/Typebar/PresetApplicationPolicy.swift
    ],
  },
  "hidden" => {
    "keys" => %w[accountChart monkey monkeyPowerLevel],
    "nativeFiles" => %w[
      Sources/Typebar/AppSettings.swift
      Sources/Typebar/ResultsAnalytics.swift
      Sources/Typebar/TypingCompanion.swift
      Sources/Typebar/PresetApplicationPolicy.swift
    ],
  },
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
font_schema_relative_path = "packages/schemas/src/fonts.ts"
audit_relative_path = "OFFICIAL_CONFIG_AUDIT.md"
schema_source = reference_root.join(schema_relative_path).read
font_schema_source = reference_root.join(font_schema_relative_path).read
audit_source = repository_root.join(audit_relative_path).read

schema_match = schema_source.match(
  /export const ConfigSchema = z\s*\.object\(\{(.*?)\}\s+satisfies Record<string, ZodSchema>/m)
fail_audit("could not locate ConfigSchema object") unless schema_match
official_keys = schema_match[1].scan(/^\s{4}([A-Za-z][A-Za-z0-9]*):/).flatten
fail_audit("official keys are not unique") unless official_keys.uniq.length == official_keys.length

audited_enum_schema_names = {
  "playSoundOnClick" => "PlaySoundOnClick",
  "playSoundOnError" => "PlaySoundOnError",
  "playTimeWarning" => "PlayTimeWarning",
  "caretStyle" => "CaretStyle",
  "paceCaretStyle" => "CaretStyle",
  "timerStyle" => "TimerStyle",
  "liveSpeedStyle" => "LiveSpeedAccBurstStyle",
  "liveAccStyle" => "LiveSpeedAccBurstStyle",
  "liveBurstStyle" => "LiveSpeedAccBurstStyle",
  "timerColor" => "TimerColor",
  "timerOpacity" => "TimerOpacity",
  "highlightMode" => "HighlightMode",
  "typedEffect" => "TypedEffect",
  "tapeMode" => "TapeMode",
  "keymapMode" => "KeymapMode",
  "keymapStyle" => "KeymapStyle",
  "keymapLegendStyle" => "KeymapLegendStyle",
  "keymapKeys" => "KeymapKeys",
  "typingSpeedUnit" => "TypingSpeedUnit",
  "monkeyPowerLevel" => "MonkeyPowerLevel",
}
official_choices = audited_enum_schema_names.to_h do |config_key, schema_name|
  enum_match = schema_source.match(
    /export const #{schema_name}Schema = z\s*\.enum\(\[(.*?)\]\)/m)
  fail_audit("could not locate #{schema_name}Schema enum") unless enum_match
  choices = enum_match[1].scan(/"([^"]+)"/).flatten
  fail_audit("#{schema_name}Schema choices are not unique") unless choices.uniq.length == choices.length
  [config_key, choices]
end
quote_length_match = schema_source.match(
  /export const QuoteLengthSchema = z\.union\(\[(.*?)\]\);/m)
fail_audit("could not locate QuoteLengthSchema union") unless quote_length_match
quote_length_choices = quote_length_match[1].scan(/z\.literal\((-?\d+)\)/).flatten
fail_audit("QuoteLengthSchema choices are not unique") unless
  quote_length_choices.uniq.length == quote_length_choices.length
official_choices["quoteLength"] = quote_length_choices
official_choice_counts = official_choices.transform_values(&:length)

font_schema_match = font_schema_source.match(
  /export const KnownFontNameSchema = z\s*\.enum\(\s*\[(.*?)\]\s*,/m)
fail_audit("could not locate KnownFontNameSchema enum") unless font_schema_match
official_known_font_family_ids = font_schema_match[1].scan(/"([^"]+)"/).flatten
fail_audit("KnownFontNameSchema choices are empty") if official_known_font_family_ids.empty?
fail_audit("KnownFontNameSchema choices are not unique") unless
  official_known_font_family_ids.uniq.length == official_known_font_family_ids.length

official_boolean_keys = [
  "smoothLineScroll",
  "showAllLines",
  "alwaysShowDecimalPlaces",
  "startGraphsAtZero",
  "monkey",
]
official_boolean_keys.each do |config_key|
  fail_audit("#{config_key} is not a boolean ConfigSchema key") unless schema_match[1].match?(
    /^\s{4}#{config_key}:\s*z\.boolean\(\),/)
end

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

native_evidence_keys = NATIVE_EVIDENCE_GROUPS.values.flat_map { |group| group.fetch("keys") }
fail_audit("native evidence keys are not unique") unless
  native_evidence_keys.uniq.length == native_evidence_keys.length
expected_native_evidence_keys = partitions.fetch(:mapped).keys + partitions.fetch(:partial).keys
fail_audit("native evidence groups do not cover every mapped or partial key") unless
  native_evidence_keys.sort == expected_native_evidence_keys.sort
NATIVE_EVIDENCE_GROUPS.each do |group_name, group|
  native_files = group.fetch("nativeFiles")
  fail_audit("#{group_name} has no native evidence files") if native_files.empty?
  native_files.each do |native_file|
    fail_audit("#{group_name} references a missing native file: #{native_file}") unless
      repository_root.join(native_file).file?
  end
end

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
  nativeEvidenceGroups: NATIVE_EVIDENCE_GROUPS,
  officialChoices: official_choices,
  officialChoiceCounts: official_choice_counts,
  officialBooleanKeys: official_boolean_keys,
  officialKnownFontFamilyIDs: official_known_font_family_ids,
  sourceFiles: [schema_relative_path, font_schema_relative_path, audit_relative_path],
  method: "metadata only; official keys, selected enum choices, selected boolean types, and known font family IDs come from ConfigSchema or KnownFontNameSchema, while statuses, mapping labels, and evidence remain in the compatibility table",
}

output_path.write(JSON.pretty_generate(fixture) + "\n")
puts "wrote #{output_path} (#{actual_counts})"
