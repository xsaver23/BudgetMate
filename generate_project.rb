#!/usr/bin/env ruby
# frozen_string_literal: true

# This command intentionally validates the checked-in project in place. It is
# not a project generator: it must never delete, recreate, or save the project.

require "json"
require "open3"
require "pathname"

root = Pathname.new(__dir__).realpath
project = root.join("BudgetMate.xcodeproj")
project_file = project.join("project.pbxproj")

fail_with = lambda do |message|
  abort "Project integrity validation failed: #{message}"
end

fail_with.call("#{project} is missing") unless project.directory?
fail_with.call("#{project_file} is missing") unless project_file.file?

required_paths = [
  "BudgetMate.xcodeproj/xcshareddata/xcschemes/BudgetMate.xcscheme",
  "BudgetMate.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
  "BudgetMate/Assets.xcassets",
  "BudgetMate/Config/Supabase.xcconfig",
  "BudgetMate/Info.plist"
]

missing_paths = required_paths.reject { |relative_path| root.join(relative_path).exist? }
fail_with.call("required project files are missing: #{missing_paths.join(", ")}") unless missing_paths.empty?

begin
  stdout, stderr, status = Open3.capture3(
    "xcodebuild",
    "-project",
    project.to_s,
    "-disableAutomaticPackageResolution",
    "-list",
    "-json",
    chdir: root.to_s
  )
rescue SystemCallError => error
  fail_with.call("could not run xcodebuild -list -json: #{error.message}")
end

unless status.success?
  detail = stderr.strip
  detail = "xcodebuild exited with status #{status.exitstatus}" if detail.empty?
  fail_with.call(detail)
end

begin
  project_info = JSON.parse(stdout).fetch("project")
rescue JSON::ParserError => error
  fail_with.call("xcodebuild returned invalid JSON: #{error.message}")
rescue KeyError
  fail_with.call("xcodebuild JSON did not contain project inventory")
end

expected_inventory = {
  "configurations" => %w[Debug Release],
  "name" => "BudgetMate",
  "schemes" => ["BudgetMate"],
  "targets" => %w[BudgetMate BudgetMateTests BudgetMateUITests]
}

expected_inventory.each do |key, expected|
  actual = project_info.fetch(key, [])
  actual = actual.sort if actual.is_a?(Array)
  fail_with.call("#{key} changed: expected #{expected.inspect}, got #{actual.inspect}") unless actual == expected
end

project_text = project_file.read
required_project_fragments = [
  "PRODUCT_BUNDLE_IDENTIFIER = com.xsaver23.budgetmate;",
  "PRODUCT_BUNDLE_IDENTIFIER = com.xsaver23.budgetmate.tests;",
  "PRODUCT_BUNDLE_IDENTIFIER = com.xsaver23.budgetmate.uitests;",
  "XCRemoteSwiftPackageReference \"supabase-swift\"",
  "Assets.xcassets",
  "BudgetMate/Info.plist",
  "Supabase.xcconfig",
  "IPHONEOS_DEPLOYMENT_TARGET = 17.0;",
  "TARGETED_DEVICE_FAMILY = \"1,2\";"
]

missing_fragments = required_project_fragments.reject { |fragment| project_text.include?(fragment) }
unless missing_fragments.empty?
  fail_with.call("project settings or references are missing: #{missing_fragments.join(", ")}")
end

package_lock = root.join("BudgetMate.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
expected_package_identities = %w[
  supabase-swift
  swift-asn1
  swift-clocks
  swift-concurrency-extras
  swift-crypto
  swift-http-types
  xctest-dynamic-overlay
]

begin
  pins = JSON.parse(package_lock.read).fetch("pins")
rescue JSON::ParserError => error
  fail_with.call("Package.resolved is invalid JSON: #{error.message}")
rescue KeyError
  fail_with.call("Package.resolved does not contain pins")
end

actual_package_identities = pins.map { |pin| pin["identity"] }.sort
unless actual_package_identities == expected_package_identities.sort
  fail_with.call(
    "Swift package identities changed: expected #{expected_package_identities.sort.inspect}, " \
      "got #{actual_package_identities.inspect}"
  )
end

supabase_pin = pins.find { |pin| pin["identity"] == "supabase-swift" }
fail_with.call("Package.resolved does not pin supabase-swift") unless supabase_pin
fail_with.call("supabase-swift pin has no revision") if supabase_pin.dig("state", "revision").to_s.empty?

puts "Project integrity validation passed."
puts "Project: #{project}"
puts "Targets: #{expected_inventory.fetch("targets").join(", ")}"
puts "Configurations: #{expected_inventory.fetch("configurations").join(", ")}"
puts "Scheme: BudgetMate"
puts "Swift package pins: #{pins.length} (supabase-swift #{supabase_pin.dig("state", "version") || "revision-only"})"
