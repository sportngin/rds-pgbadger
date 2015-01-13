# RDS PgBadger

A tool to easily download logs from an AWS RDS instance and generate [pgBadger](http://dalibo.github.io/pgbadger/) reports.

## Dependencies

pgBadger must be installed. Download and install from the [site](http://dalibo.github.io/pgbadger/) or on OSX run `brew install pgbadger`.

Setup your AWS credentials in your `~/.fog` file.  Example:

```
env1:
  aws_access_key_id: tacos
  aws_secret_access_key: foobar
env1:
  aws_access_key_id: cats
  aws_secret_access_key: foobaz
```

If you do not have a fog file, the AWS SDK will try to use its [regular](https://github.com/aws/aws-sdk-core-ruby#credentials) credential resolving methods.

## Usage

Execute the Ruby script proving the target environment and RDS instance identifier.

```
./rds-pgbadger.rb -e env1 -i my-rds-instance
``` 

It will download the log files and generate a report in the out folder named after the instance id and a timestamp of when the script executed.

You can additionally filter the retrieved log files by date:

```
./rds-pgbadger.rb -e env1 -i my-rds-instance -d 2015-01-13
``` 


