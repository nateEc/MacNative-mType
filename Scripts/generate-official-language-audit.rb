#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "pathname"

PINNED_COMMIT = "91bd24bb8513785c7364cbea29296ff7adafac41"
EXPECTED_COUNTS = { official: 446, independent: 241, related: 205, unmapped: 0 }.freeze
MIXED_TYPEBAR_CASES = %w[mixedEnglishChinese mixedLanguages].freeze
ALIASES = {
  "englishFiveLetter" => "wordle",
  "english1k" => "english_1k",
  "english5k" => "english_5k",
  "english10k" => "english_10k",
  "english25k" => "english_25k",
  "english450k" => "english_450k",
  "spanish1k" => "spanish_1k",
  "spanish10k" => "spanish_10k",
  "spanish650k" => "spanish_650k",
  "oldEnglish" => "english_old",
  "pokemon1k" => "pokemon_1k",
  "arenaStrategy" => "league_of_legends",
  "russianContractions" => "russian_contractions",
  "russianContractions1k" => "russian_contractions_1k",
  "tamilOld" => "tamil_old",
  "englishDoubleLetter" => "english_doubleletter",
  "esperantoXSystem" => "esperanto_x_sistemo",
  "esperantoHSystem" => "esperanto_h_sistemo",
  "maori" => "maori_1k",
  "basque" => "euskera",
  "yoruba" => "yoruba_1k",
  "swahili" => "swahili_1k",
  "portugueseAccents" => "portuguese_acentos_e_cedilha",
  "simplifiedChinese" => "chinese_simplified",
  "traditionalChinese" => "chinese_traditional",
  "ukrainianLatin" => "ukrainian_latynka",
  "codeJavaScript" => "code_javascript",
  "codePython1k" => "code_python_1k",
  "codePython2k" => "code_python_2k",
  "codePython5k" => "code_python_5k",
  "codeFSharp" => "code_fsharp",
  "codeCSharp" => "code_csharp",
  "codeCPP" => "code_c++",
  "codeJavaScript1k" => "code_javascript_1k",
  "codeJavaScriptReact" => "code_javascript_react",
  "codeR2k" => "code_r_2k",
  "codePowerShell" => "code_powershell",
  "codeLaTeX" => "code_latex",
  "codeOpenCL" => "code_opencl",
  "codeSystemVerilog" => "code_systemverilog",
  "codeGDScript" => "code_gdscript",
  "codeGDScript2" => "code_gdscript_2",
  "codeTypeScript" => "code_typescript",
  "codeOCaml" => "code_ocaml",
  "codeABAP1k" => "code_abap_1k",
  "codeYoptaScript" => "code_yoptascript",
  "code6502Assembly" => "code_6502_assembly",
}.freeze

def fail_audit(message)
  warn "language audit failed: #{message}"
  exit 1
end

def snake_case(value)
  value
    .gsub(/([A-Z]+)([A-Z][a-z])/, '\\1_\\2')
    .gsub(/([a-z\d])([A-Z])/, '\\1_\\2')
    .downcase
end

repository_root = Pathname.new(__dir__).parent
reference_root = ARGV[0] && Pathname.new(ARGV[0]).expand_path
output_path = ARGV[1] ? Pathname.new(ARGV[1]).expand_path : repository_root.join("Compatibility/official-languages.json")
fail_audit("usage: #{$PROGRAM_NAME} MONKEYTYPE_REFERENCE [OUTPUT]") unless reference_root

commit, status = Open3.capture2("git", "-C", reference_root.to_s, "rev-parse", "HEAD")
fail_audit("could not read reference commit") unless status.success?
fail_audit("reference must be pinned to #{PINNED_COMMIT}") unless commit.strip == PINNED_COMMIT

schema_path = reference_root.join("packages/schemas/src/languages.ts")
engine_path = repository_root.join("Sources/Typebar/TypingEngine.swift")
schema_source = schema_path.read
engine_source = engine_path.read

schema_match = schema_source.match(/export const LanguageSchema = z\.enum\(\s*\[(.*?)\]\s*,\s*\{/m)
fail_audit("could not locate LanguageSchema enum") unless schema_match
official_ids = schema_match[1].scan(/"([^"]+)"/).flatten
fail_audit("official IDs are not unique") unless official_ids.uniq.length == official_ids.length

engine_match = engine_source.match(/enum TypingLanguage:.*?\{(.*?)^\}/m)
fail_audit("could not locate TypingLanguage enum") unless engine_match
typebar_cases = engine_match[1].scan(/^\s*case\s+([A-Za-z0-9_]+)/).flatten
typebar_cases -= MIXED_TYPEBAR_CASES

independent_by_id = {}
typebar_cases.each do |typebar_case|
  official_id = ALIASES.fetch(typebar_case, snake_case(typebar_case))
  fail_audit("Typebar case #{typebar_case} does not resolve to an official ID") unless official_ids.include?(official_id)
  fail_audit("duplicate independent mapping for #{official_id}") if independent_by_id.key?(official_id)

  independent_by_id[official_id] = typebar_case
end

native_independent = {}
native_related_choice = {}
unmapped_official_ids = []
official_ids.each do |official_id|
  if independent_by_id.key?(official_id)
    native_independent[official_id] = independent_by_id.fetch(official_id)
    next
  end

  family_id = official_id.sub(/_\d+k\z/, "")
  if family_id != official_id && independent_by_id.key?(family_id)
    native_related_choice[official_id] = independent_by_id.fetch(family_id)
  else
    unmapped_official_ids << official_id
  end
end

actual_counts = {
  official: official_ids.length,
  independent: native_independent.length,
  related: native_related_choice.length,
  unmapped: unmapped_official_ids.length,
}
fail_audit("unexpected classification counts: #{actual_counts}") unless actual_counts == EXPECTED_COUNTS

fixture = {
  referenceRepository: "monkeytypegame/monkeytype",
  referenceCommit: PINNED_COMMIT,
  officialCount: official_ids.length,
  officialIDs: official_ids,
  nativeIndependent: native_independent,
  nativeRelatedChoice: native_related_choice,
  unmappedOfficialIDs: unmapped_official_ids,
  sourceFiles: ["packages/schemas/src/languages.ts", "Sources/Typebar/TypingEngine.swift"],
  method: "metadata only; independent means a distinct native choice, related means a numeric-size family represented by another native choice, and unmapped means no native choice",
}

output_path.write(JSON.pretty_generate(fixture) + "\n")
puts "wrote #{output_path} (#{actual_counts})"
