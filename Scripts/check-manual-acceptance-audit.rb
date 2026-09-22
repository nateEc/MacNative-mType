#!/usr/bin/env ruby
# frozen_string_literal: true

require "tmpdir"

DEFAULT_DOCUMENT = File.expand_path("../MANUAL_ACCEPTANCE.md", __dir__)
MINIMUM_SCENARIO_COUNT = 500
SCENARIO_ID = /\A[A-Z][A-Z0-9]*(?:-[A-Z0-9]+)*\z/
ALLOWED_STATUS = /\A(?:已验收|待验收|部分验收)(?:（.*）)?\z/
REQUIRED_SINGLE_INSTANCE_RULES = [
  "一次只运行一个 Typebar 图形实例",
  "pgrep -alf -x \"$process_name\"",
  "swift-frontend",
  "swift-driver",
  "swiftc"
].freeze

def audit(path, minimum_scenarios:, output: $stderr)
  unless File.file?(path)
    output.puts "manual acceptance audit failed: missing document #{path}"
    return false
  end

  document = File.read(path, encoding: "UTF-8")
  errors = []

  REQUIRED_SINGLE_INSTANCE_RULES.each do |rule|
    errors << "missing single-instance rule: #{rule}" unless document.include?(rule)
  end

  scenarios = []
  document.each_line.with_index(1) do |line, line_number|
    cells = line.chomp.split("|", -1)
    next unless cells.length >= 7 && cells.first.empty? && cells.last.empty?

    identifier = cells[1].strip
    next unless identifier.match?(SCENARIO_ID) && identifier != "ID"

    status = cells[-2].strip
    scenarios << { id: identifier, line: line_number, status: status }
  end

  if scenarios.length < minimum_scenarios
    errors << "expected at least #{minimum_scenarios} scenario rows, found #{scenarios.length}"
  end

  scenarios.each do |scenario|
    next if scenario[:status].match?(ALLOWED_STATUS)

    errors << "#{scenario[:id]} on line #{scenario[:line]} has an unsupported status: #{scenario[:status]}"
  end

  scenarios.group_by { |scenario| scenario[:id] }.each do |identifier, rows|
    next if rows.length == 1

    lines = rows.map { |row| row[:line] }.join(", ")
    errors << "duplicate scenario ID #{identifier} on lines #{lines}"
  end

  if errors.empty?
    output.puts "manual acceptance audit passed (#{scenarios.length} unique scenarios)" if output
    true
  else
    errors.each { |error| output.puts "manual acceptance audit failed: #{error}" } if output
    false
  end
end

def self_test
  Dir.mktmpdir("typebar-manual-acceptance-audit-") do |directory|
    valid_path = File.join(directory, "valid.md")
    valid_document = <<~MARKDOWN
      # Typebar 人工验收记录

      一次只运行一个 Typebar 图形实例。
      `pgrep -alf -x "$process_name"` 会在启动前检查 Typebar。
      `swift-frontend`、`swift-driver` 和 `swiftc` 也必须全部退出。

      | ID | 场景 | 操作 | 期望结果 | 状态 |
      | --- | --- | --- | --- | --- |
      | DEMO-01 | 演示 | 检查 | 可追溯 | 待验收 |
      | DEMO-02 | 已验收演示 | 检查 | 可追溯 | 已验收 |
      | DEMO-03 | 部分验收演示 | 检查 | 可追溯 | 部分验收 |
    MARKDOWN
    File.write(valid_path, valid_document)
    raise "valid fixture unexpectedly failed" unless audit(valid_path, minimum_scenarios: 3, output: nil)

    duplicate_path = File.join(directory, "duplicate.md")
    File.write(duplicate_path, valid_document + "| DEMO-01 | 重复 | 检查 | 应拒绝 | 已验收 |\n")
    raise "duplicate fixture unexpectedly passed" if audit(duplicate_path, minimum_scenarios: 3, output: nil)
  end

  puts "manual acceptance audit self-test passed"
end

if ARGV == ["--self-test"]
  self_test
elsif ARGV.empty? || ARGV.length == 1
  path = ARGV.first ? File.expand_path(ARGV.first) : DEFAULT_DOCUMENT
  exit(audit(path, minimum_scenarios: MINIMUM_SCENARIO_COUNT) ? 0 : 1)
else
  warn "usage: ruby Scripts/check-manual-acceptance-audit.rb [MANUAL_ACCEPTANCE.md] | --self-test"
  exit 64
end
