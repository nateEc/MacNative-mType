#!/usr/bin/env ruby
# Mechanically project owned historical stored declarations, not an old GUI
# binary. Build serially before XCTest; never target the user's database.
require "fileutils"
require "json"
require "open3"
require "digest"

project = File.expand_path("..", __dir__)
abort "usage: #{$PROGRAM_NAME} /absolute/new/temporary/disk-model-fixtures" unless ARGV.length == 1
destination = ARGV.first
abort "absolute new destination required" unless destination.start_with?("/") && !File.exist?(destination)
parent = File.realpath(File.dirname(destination))
abort "owned temporary parent required" unless File.basename(parent).start_with?("typebar-") &&
  File.stat(parent).uid == Process.uid
destination = File.join(parent, File.basename(destination))

def command!(*arguments)
  output, error, status = Open3.capture3(*arguments)
  abort "#{arguments.first} failed: #{output}\n#{error}" unless status.success?
  output
end

target_info = JSON.parse(command!("xcrun", "swiftc", "-print-target-info")).fetch("target")
abort "native macOS compiler required" unless target_info["platform"] == "macosx" &&
  ["arm64", "x86_64"].include?(target_info["arch"])
compiler_target = "#{target_info.fetch("arch")}-apple-macos14.0"

models = {
  "TestResultRecord" => "Sources/Typebar/ResultPersistence.swift",
  "TestPresetRecord" => "Sources/Typebar/TestPresets.swift",
  "SavedCustomTextRecord" => "Sources/Typebar/SavedTexts.swift",
  "ResultFilterPresetRecord" => "Sources/Typebar/ResultPersistence.swift"
}
versions = {
  "initial" => "bdbfae291c7a20a706a100c62a7c323681dfbf8f",
  "before-elapsed" => "9c5b477c6cd1a2ef5b4d34afbc3ef4013dc21cc7",
  "before-incomplete" => "da972ecfaa6e7109932b9ccd96fcfecdb6b7a92c",
  "current" => command!("git", "-C", project, "rev-parse", "HEAD").strip
}
FileUtils.mkdir(destination)
manifest = {}

versions.each do |label, commit|
  declarations = {}
  models.each do |name, file|
    source = label == "current" ? File.read(File.join(project, file)) :
      command!("git", "-C", project, "show", "#{commit}:#{file}")
    block = source.match(/@Model\s+final class #{name} \{(.*?)\n\s*init/m)&.captures&.first
    abort "stored declarations not found: #{name}" unless block
    fields = block.lines.map do |line|
      next if line.strip.empty? || line.strip.start_with?("//")
      match = line.strip.match(/\A(@Attribute\(\.unique\) )?var (\w+): (UUID|Data|String|Date|TimeInterval|Int|Double)(\?)?( = 0)?\z/)
      abort "unsupported stored declaration: #{line}" unless match
      {name: match[2], type: match[3], optional: !match[4].nil?, declaration: line.strip}
    end.compact
    abort "missing unique identity: #{name}" unless fields.first[:declaration] == "@Attribute(.unique) var id: UUID"
    declarations[name] = fields
  end
  has_elapsed = declarations.fetch("TestResultRecord").any? { |field| field[:name] == "elapsedTimeData" }
  expects_elapsed = ["before-incomplete", "current"].include?(label)
  abort "elapsed field presence does not match version #{label}" unless has_elapsed == expects_elapsed
  has_incomplete = declarations.fetch("TestResultRecord").any? { |field| field[:name] == "incompletePracticeData" }
  abort "incomplete field presence does not match version #{label}" unless has_incomplete == (label == "current")

  code = "import Foundation\nimport SwiftData\n\n"
  declarations.each do |name, fields|
    code += "@Model\nfinal class #{name} {\n"
    code += fields.map { |field| "  #{field[:declaration]}\n" }.join
    code += "  init(values: [String: Any]) throws {\n"
    fields.each do |field|
      parser = field[:optional] ? "optional" : "required"
      code += "    #{field[:name]} = try DiskFixtureValue.#{parser}(values, \"#{field[:name]}\", as: #{field[:type]}.self)\n"
    end
    code += "  }\n}\n\n"
  end
  code += "@MainActor func diskFixtureInsert(_ payload: [String: [[String: Any]]], into context: ModelContext) throws {\n"
  declarations.each_key do |name|
    code += "  for row in payload[\"#{name}\"] ?? [] { context.insert(try #{name}(values: row)) }\n"
  end
  code += "}\n\n@MainActor func diskFixtureRows(_ context: ModelContext) throws -> [String: [[String: Any]]] {\n  return [\n"
  declarations.each do |name, fields|
    code += "    \"#{name}\": try context.fetch(FetchDescriptor<#{name}>()).map { row in [\n"
    fields.each do |field|
      value = field[:optional] ? "row.#{field[:name]}.map { DiskFixtureValue.encode($0) } ?? NSNull()" :
        "DiskFixtureValue.encode(row.#{field[:name]})"
      code += "      \"#{field[:name]}\": #{value},\n"
    end
    code += "    ] },\n"
  end
  code += "  ]\n}\n"
  source_path = File.join(destination, "#{label}-models.swift")
  File.write(source_path, code)
  writer = File.join(destination, "#{label}-fixture-writer")
  command!("xcrun", "swiftc", "-swift-version", "6", "-parse-as-library",
    "-target", compiler_target, "-module-name", "Typebar",
    source_path, File.join(project, "Scripts/Fixtures/DiskFixtureProgram.swift"), "-o", writer)
  manifest[label] = {commit: commit, declarationSHA256: Digest::SHA256.hexdigest(code),
    fields: declarations.transform_values { |fields| fields.map { |field| field[:name] } }}
end
File.write(File.join(destination, "manifest.json"), JSON.pretty_generate(manifest))
puts "disk model fixture writers prepared serially (initial, before-elapsed, before-incomplete, current; no GUI/store opened)"
