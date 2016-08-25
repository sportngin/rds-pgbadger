#!/usr/bin/env ruby

require 'rbconfig'
require 'optparse'
require 'yaml'
require 'ox'
require 'aws-sdk-core'

options = {}
options[:logs_directory] = "logs"
options[:reports_directory] = "reports"
options[:parallel] = true
options[:pgbadger] = 'pgbadger'
options[:pgbadger_args] = ''
OptionParser.new do |opts|
    opts.banner = 'Usage: rds-pgbadger.rb [options]'

    opts.on('-e', '--env NAME', 'Environement name') { |v| options[:env] = v }
    opts.on('-i', '--instance-id NAME', 'RDS instance identifier') { |v| options[:instance_id] = v }
    opts.on('-r', '--region REGION', 'RDS instance region') { |v| options[:region] = v }
    opts.on('-d', '--date DATE', 'Filter logs to given date in format YYYY-MM-DD.') { |v| options[:date] = v }
    opts.on('--logs-directory DIRECTORY', "Download logs to this directory (Default: ./#{options[:logs_directory]})") { |v| options[:logs_directory] = v }
    opts.on('--reports-directory DIRECTORY', "Generate PGBadger report html in this directory (Default: ./#{options[:reports_directory]})") { |v| options[:reports_directory] = v }
    opts.on('-p', '--[no-]parallel', 'Run PGBadger in parallel mode. (Default: true)') { |v| options[:parallel] = v }
    opts.on('--view', 'View results in your browser? Useful when running from a workstation. (Default: false)') { |v| options[:view] = true }
    opts.on('--pgbadger /PATH/TO/PGBADGER', 'Path to PGBadger executable') { |v| options[:pgbadger] = v }
    opts.on('--pgbadger-args a,b,c', 'Arguments for PGBadger') { |v| options[:pgbadger_args] = v }
end.parse!

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

creds = {}
access_key_id = nil
secret_access_key = nil
fog_file = File.expand_path('~/.fog')
if File.exist?(fog_file)
  creds = YAML.load(File.read(fog_file))
  access_key_id = creds[options[:env]]['aws_access_key_id']
  secret_access_key = creds[options[:env]]['aws_secret_access_key']
end

puts "Instantiating RDS client for #{options[:env]} environment."
rds = Aws::RDS::Client.new(
  region: options[:region],
  access_key_id: access_key_id,
  secret_access_key: secret_access_key,
)
log_files = rds.describe_db_log_files(db_instance_identifier: options[:instance_id], filename_contains: "postgresql.log.#{options[:date]}")[:describe_db_log_files].map(&:log_file_name)

dir_name = "#{options[:instance_id]}"
log_dir = "#{options[:logs_directory]}/#{dir_name}"
report_dir = "#{options[:reports_directory]}/#{dir_name}"
report_file = "#{report_dir}/index.html"

FileUtils.mkdir_p("#{log_dir}/error")
log_files.each do |log_file|
  puts "Downloading log file: #{log_file}"
  open("#{log_dir}/#{log_file}", 'w') do |f|
    rds.download_db_log_file_portion(db_instance_identifier: options[:instance_id], log_file_name: log_file).each do |r|
      print '.'
      f.puts r[:log_file_data]
    end
    puts '.'
  end
  puts "Saved log to #{log_dir}/#{log_file}."
end

if options[:parallel]
  parallel = "-j #{processor_count}"
end

if File.exist?(report_file)
  puts "Running PGBadger in incremental mode"
  incremental = "--incremental"
end

puts 'Generating PG Badger report.'
FileUtils.mkdir_p("#{report_dir}")
`#{options[:pgbadger]} --prefix "%t:%r:%u@%d:[%p]:" #{parallel} #{incremental} --outfile #{report_file} #{log_dir}/error/*.log.*`

if options[:view]
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
end
