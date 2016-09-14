# Emrakul

This gem helps to run embulk on AWS-EMR.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'emrakul'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install emrakul

## Usage

### Command

```sh
emrakul run embulk_config.yml -e emr_config.yml -i ~/emr-ec2-key.pem -g embulk_gemfile --additional-scripts=install_jars.sh --additional-uploads=google_api_key.json
```

```
Usage:
  emrakul run EMBULK_CONFIG [EMBULK_CONFIG EMBULK_CONFIG ...] -e, --emr-config=EMR_CONFIG -g, --gemfile=GEMFILE -i, --identity-file=IDENTITY_FILE

Options:
  -i, --identity-file=IDENTITY_FILE
  -e, --emr-config=EMR_CONFIG
  -g, --gemfile=GEMFILE
  -u, [--user=USER]
      [--embulk-path=EMBULK_PATH]
      [--aws-access-key-id=AWS_ACCESS_KEY_ID]
      [--aws-secret-access-key=AWS_SECRET_ACCESS_KEY]
      [--aws-region=AWS_REGION]
      [--additional-scripts=SCRIPT[,SCRIPT,SCRIPT...]]
      [--additional-uploads=UPLOAD_FILE[,UPLOAD_FILE,UPLOAD_FILE...]]
```

### Ruby

```ruby
Emrakul.run("embulk_config.yml", "embulk_gemfile", "~/emr-ec2-key.pem", emr_config: emr_config.yml, additional_scripts: ["install_jars.sh"], additional_uploads: ["google_api_key.json"])
```

```ruby
    def run(
      configs,
      gemfile_path,
      ec2_key_path,
      aws_access_key_id: nil,
      aws_secret_access_key: nil,
      aws_region: nil,
      user: "hadoop",
      emr_config: {},
      embulk_path: `which embulk`.chomp,
      additional_scripts: [],
      additional_uploads: []
    )

    # ...
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/joker1007/emrakul.

