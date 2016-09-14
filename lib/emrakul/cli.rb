require 'thor'
require 'pathname'
require 'yaml'

require 'emrakul'

module Emrakul
  class Cli < Thor
    desc "run EMBULK_CONFIG [EMBULK_CONFIG EMBULK_CONFIG ...]", "execute embulk run on EMR cluster"
    map "run" => "_run"
    method_option :identity_file, type: :string, required: true, aliases: "-i"
    method_option :emr_config, type: :string, required: true, aliases: "-e"
    method_option :gemfile, type: :string, required: true, aliases: "-g"
    method_option :user, type: :string, aliases: "-u"
    method_option :embulk_path, type: :string
    method_option :aws_access_key_id, type: :string
    method_option :aws_secret_access_key, type: :string
    method_option :aws_region, type: :string
    method_option :additional_scripts, type: :string, banner: "SCRIPT[,SCRIPT,SCRIPT...]"
    method_option :additional_uploads, type: :string, banner: "UPLOAD_FILE[,UPLOAD_FILE,UPLOAD_FILE...]"
    def _run(*embulk_configs)
      run_options = options.reject { |_, v| v.nil? }.map { |k, v| [k.to_sym, v] }.to_h

      ec2_key_path = run_options.delete(:identity_file)
      gemfile_path = run_options.delete(:gemfile)
      emr_config_path = run_options.delete(:emr_config)
      emr_config = YAML.load_file(emr_config_path)

      run_options[:additional_scripts] = run_options[:additional_scripts].split(",").map(&:strip)
      run_options[:additional_uploads] = run_options[:additional_uploads].split(",").map(&:strip)

      Emrakul.run_emr(embulk_configs, gemfile_path, ec2_key_path, emr_config: emr_config, **run_options)
    end
  end
end
