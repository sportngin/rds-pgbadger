#!/usr/bin/env ruby

require 'optparse'
require 'yaml'
require 'aws-sdk-core'

options = {}
OptionParser.new do |opts|
    opts.banner = "Usage: rds-pgbadger.rb [options]"

    opts.on('-e', '--env NAME', 'Environement name') { |v| options[:env] = v }
    opts.on('-i', '--instance-id NAME', 'RDS instance identifier') { |v| options[:instance_id] = v }

end.parse!

raise OptionParser::MissingArgument.new(:env) if options[:env].nil?
raise OptionParser::MissingArgument.new(:instance_id) if options[:instance_id].nil?

creds = YAML.load(File.read(File.expand_path('~/.fog')))

puts "Instantiating RDS client for #{options[:env]} environment."
rds = Aws::RDS::Client.new(
  region: 'us-east-1',
  access_key_id: creds[options[:env]]['aws_access_key_id'],
  secret_access_key: creds[options[:env]]['aws_secret_access_key']
)
log_files = rds.describe_db_log_files(db_instance_identifier: options[:instance_id], filename_contains: "postgresql")[:describe_db_log_files].map(&:log_file_name)

dir_name = "#{options[:instance_id]}-#{Time.now.to_i}"

Dir.mkdir("out/#{dir_name}")
Dir.mkdir("out/#{dir_name}/error")
log_files.each do |log_file|
  puts "Downloading log file: #{log_file}"
  open("out/#{dir_name}/#{log_file}", 'w') do |f|
    rds.download_db_log_file_portion(db_instance_identifier: options[:instance_id], log_file_name: log_file).each do |r|
      print "."
      f.puts r[:log_file_data]
    end
    puts "."
  end
  puts "Saved log to out/#{dir_name}/#{log_file}."
end
puts "Generating PG Badger report."
`pgbadger --prefix "%t:%r:%u@%d:[%p]:" --outfile out/#{dir_name}/#{dir_name}.html out/#{dir_name}/error/*.log.*`
puts "Opening report out/#{dir_name}/#{dir_name}.html."
`open out/#{dir_name}/#{dir_name}.html`

