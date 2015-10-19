#!/usr/bin/env ruby

require 'rbconfig'
require 'optparse'
require 'yaml'
require 'ox'
require 'aws-sdk-core'

options = {}
OptionParser.new do |opts|
    opts.banner = 'Usage: rds-pgbadger.rb [options]'

    opts.on('-e', '--env NAME', 'Environement name') { |v| options[:env] = v }
    opts.on('-i', '--instance-id NAME', 'RDS instance identifier') { |v| options[:instance_id] = v }
    opts.on('-r', '--region REGION', 'RDS instance region') { |v| options[:region] = v }
    opts.on('-d', '--date DATE', 'Filter logs to given date in format YYYY-MM-DD.') { |v| options[:date] = v }
    opts.on('-p', '--parallel', 'Run in parallel') { |v| options[:parallel] = true }

end.parse!

raise OptionParser::MissingArgument.new(:env) if options[:env].nil?
raise OptionParser::MissingArgument.new(:instance_id) if options[:instance_id].nil?
raise OptionParser::MissingArgument.new(:region) if options[:region].nil?

def self.processor_count
  case RbConfig::CONFIG['host_os']
    when /darwin9/
      `hwprefs cpu_count`.to_i
    when /darwin/
      ((`which hwprefs` != '') ? `hwprefs thread_count` : `sysctl -n hw.ncpu`).to_i
    when /linux/
      `cat /proc/cpuinfo | grep processor | wc -l`.to_i
    when /freebsd/
      `sysctl -n hw.ncpu`.to_i
    else
      1
  end
end

creds = YAML.load(File.read(File.expand_path('~/.fog')))

puts "Instantiating RDS client for #{options[:env]} environment."
rds = Aws::RDS::Client.new(
  region: options[:region],
  access_key_id: creds[options[:env]]['aws_access_key_id'],
  secret_access_key: creds[options[:env]]['aws_secret_access_key']
)
log_files = rds.describe_db_log_files(db_instance_identifier: options[:instance_id], filename_contains: "postgresql.log.#{options[:date]}")[:describe_db_log_files].map(&:log_file_name)

dir_name = "#{options[:instance_id]}-#{Time.now.to_i}"

FileUtils.mkdir_p("out/#{dir_name}/error")
log_files.each do |log_file|
  puts "Downloading log file: #{log_file}"
  open("out/#{dir_name}/#{log_file}", 'w') do |f|
    rds.download_db_log_file_portion(db_instance_identifier: options[:instance_id], log_file_name: log_file).each do |r|
      print '.'
      f.puts r[:log_file_data]
    end
    puts '.'
  end
  puts "Saved log to out/#{dir_name}/#{log_file}."
end

parallel = ''
if options[:parallel]
  parallel = "-j #{processor_count}"
end

puts 'Generating PG Badger report.'
`pgbadger --prefix "%t:%r:%u@%d:[%p]:" #{parallel} --outfile out/#{dir_name}/#{dir_name}.html out/#{dir_name}/error/*.log.*`

case RbConfig::CONFIG['host_os']
  when /darwin|mac os/i
    puts "Opening report out/#{dir_name}/#{dir_name}.html."
    `open out/#{dir_name}/#{dir_name}.html`
  when /linux/i
    puts "Opening report out/#{dir_name}/#{dir_name}.html."
    `xdg-open out/#{dir_name}/#{dir_name}.html`
  else
    puts `Generated: out/#{dir_name}/#{dir_name}.html`
end
