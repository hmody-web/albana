require 'xcodeproj'

project_path = 'ios/Runner.xcodeproj'
project = Xcodeproj::Project.open(project_path)

target_name = 'NotificationService'
bundle_id = 'com.majidalbana.app.NotificationService'

runner = project.targets.find { |t| t.name == 'Runner' }

abort 'Runner target not found' unless runner

target = project.targets.find { |t| t.name == target_name }

unless target
  puts 'Creating NotificationService target...'

  target = project.new_target(
    :app_extension,
    target_name,
    :ios,
    '15.0'
  )

  group = project.main_group.find_subpath('NotificationService', true)
  group.set_source_tree('<group>')
  group.set_path('NotificationService')

  swift_file =
    group.files.find { |f| f.path == 'NotificationService.swift' } ||
    group.new_file('NotificationService.swift')

  plist_file =
    group.files.find { |f| f.path == 'Info.plist' } ||
    group.new_file('Info.plist')

  target.add_file_references([swift_file])

  target.build_configurations.each do |config|
    config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = bundle_id
    config.build_settings['PRODUCT_NAME'] = 'NotificationService'
    config.build_settings['PRODUCT_MODULE_NAME'] = 'NotificationService'
    config.build_settings['EXECUTABLE_NAME'] = '$(PRODUCT_NAME)'
    config.build_settings['INFOPLIST_FILE'] = 'NotificationService/Info.plist'
    config.build_settings['GENERATE_INFOPLIST_FILE'] = 'NO'
    config.build_settings['SWIFT_VERSION'] = '5.0'
    config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
    config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
    config.build_settings['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
    config.build_settings['SKIP_INSTALL'] = 'YES'
    config.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  end

else
  puts 'NotificationService target already exists.'
end

copy_phase = runner.copy_files_build_phases.find do |phase|
  phase.name == 'Embed App Extensions'
end

unless copy_phase
  puts 'Creating Embed App Extensions phase...'
  copy_phase = runner.new_copy_files_build_phase('Embed App Extensions')
  copy_phase.dst_subfolder_spec = '13'
end

unless copy_phase.files_references.include?(target.product_reference)
  build_file = copy_phase.add_file_reference(target.product_reference)

  build_file.settings = {
    'ATTRIBUTES' => [
      'CodeSignOnCopy',
      'RemoveHeadersOnCopy'
    ]
  }
end

project.save

puts 'NotificationService configuration complete.'
puts "Bundle ID: #{bundle_id}"