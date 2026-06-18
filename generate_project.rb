#!/usr/bin/env ruby

require "xcodeproj"
require "fileutils"

project_path = File.join(__dir__, "BudgetMate.xcodeproj")
FileUtils.rm_rf(project_path) if File.exist?(project_path)
project = Xcodeproj::Project.new(project_path)

app_target = project.new_target(
  :application,
  "BudgetMate",
  :ios,
  "17.0"
)

app_target.build_configurations.each do |config|
  config.build_settings["PRODUCT_BUNDLE_IDENTIFIER"] = "com.budgetmate.app"
  config.build_settings["SWIFT_VERSION"] = "5.0"
  config.build_settings["CODE_SIGN_STYLE"] = "Automatic"
  config.build_settings["GENERATE_INFOPLIST_FILE"] = "YES"
  config.build_settings["INFOPLIST_KEY_UIApplicationSceneManifest_Generation"] = "YES"
  config.build_settings["INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents"] = "YES"
  config.build_settings["INFOPLIST_KEY_UILaunchScreen_Generation"] = "YES"
end

main_group = project.main_group
app_group = main_group.new_group("BudgetMate", "BudgetMate")

["Models", "Views", "ViewModels", "Services", "Components", "Utilities"].each do |folder|
  app_group.new_group(folder, "BudgetMate/#{folder}")
end

Dir.glob(File.join(__dir__, "BudgetMate", "**", "*.swift")).sort.each do |file_path|
  relative_path = Pathname.new(file_path).relative_path_from(Pathname.new(File.join(__dir__, "BudgetMate"))).to_s
  file_ref = app_group.new_file(relative_path)
  app_target.add_file_references([file_ref])
end

project.save
