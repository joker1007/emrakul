require "emrakul/version"

require 'tempfile'
require 'yaml'
require 'aws-sdk'
require 'sshkit'

module Emrakul
  class << self
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
      job_flow_id = setup_cluster(
        gemfile_path, ec2_key_path,
        aws_access_key_id: aws_access_key_id, aws_secret_access_key: aws_secret_access_key, aws_region: aws_region,
        user: user,
        emr_config: emr_config,
        embulk_path: embulk_path,
        additional_scripts: additional_scripts,
        additional_uploads: additional_uploads
      )

      run_on_emr(
        configs, job_flow_id, ec2_key_path,
        aws_access_key_id: aws_access_key_id, aws_secret_access_key: aws_secret_access_key, aws_region: aws_region,
        user: user
      )
    end

    def setup_cluster(
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
      raise "Need embulk" if embulk_path.nil? || embulk_path.empty?

      client = emr_client(
        aws_access_key_id: aws_access_key_id,
        aws_secret_access_key: aws_secret_access_key,
        aws_region: aws_region
      )

      job_flow_id = create_cluster(client: client, emr_config: emr_config)
      master_instance = client.list_instances(cluster_id: job_flow_id, instance_group_types: ["MASTER"]).instances[0]

      setup_embulk(user, master_instance, ec2_key_path, embulk_path, gemfile_path,
                   additional_scripts: additional_scripts, additional_uploads: additional_uploads)

      job_flow_id
    end

    def run_on_emr(
      configs,
      job_flow_id,
      ec2_key_path,
      aws_access_key_id: nil,
      aws_secret_access_key: nil,
      aws_region: nil,
      user: "hadoop",
      shutdown: true
    )
      configs = Array(configs)
      tfs = []
      config_paths = configs.each_with_object([]) do |config, arr|
        if config.is_a?(String)
          arr << config
        elsif config.is_a?(Hash)
          tf = Tempfile.new(["emrakul", ".yml"])
          tf.write(YAML.dump(config))
          tf.flush
          arr << tf.path
          tfs << tf
        else
          raise "config is not assigned"
        end
      end

      client = emr_client(
        aws_access_key_id: aws_access_key_id,
        aws_secret_access_key: aws_secret_access_key,
        aws_region: aws_region
      )

      master_instance = client.list_instances(cluster_id: job_flow_id, instance_group_types: ["MASTER"]).instances[0]

      config_paths.each do |config_path|
        run_embulk(user, master_instance, ec2_key_path, config_path)
      end
    ensure
      tfs.each(&:close!) if tfs
      client.terminate_job_flows(job_flow_ids: [job_flow_id]) if job_flow_id && shutdown
    end

    def create_cluster(client:, emr_config:)
      emr_config =
        default_emr_options
        .tap { |o| o.delete(:applications) if emr_config[:applications] }
        .merge(emr_config)
      emr_config[:instances][:keep_job_flow_alive_when_no_steps] = true

      job_flow_id = client.run_job_flow(emr_config).job_flow_id
      puts "Waiting for cluster running ..."
      client.wait_until(:cluster_running, cluster_id: job_flow_id)
      job_flow_id
    end

    def setup_embulk(user, instance, ec2_key_path, embulk_path, gemfile_path, additional_scripts: [], additional_uploads: [])
      on_instance(user, instance, ec2_key_path) do
        home_dir = "/home/#{user}"
        workspace_dir = "#{home_dir}/embulk_workspace"

        upload! embulk_path, "#{home_dir}/embulk"
        execute :sudo, "chmod", "755", "#{home_dir}/embulk"
        execute :sudo, "mv", "#{home_dir}/embulk", "/usr/bin/embulk"

        execute :mkdir, "-p", workspace_dir

        upload! gemfile_path, "#{workspace_dir}/Gemfile"

        within workspace_dir do
          execute :embulk, "bundle", "install"

          additional_uploads.each do |f|
            if f.is_a?(Hash)
              f.each do |k, v|
                upload! k, File.join(workspace_dir, v)
              end
            else
              upload! f, File.join(workspace_dir, File.basename(f))
            end
          end

          additional_scripts.each do |script|
            upload! script, File.join(workspace_dir, File.basename(script))
            execute :chmod, "755", File.basename(script)
            execute "./#{File.basename(script)}"
          end
        end
      end
    end

    def run_embulk(user, instance, ec2_key_path, config_path)
      on_instance(user, instance, ec2_key_path) do
        home_dir = "/home/#{user}"
        workspace_dir = "#{home_dir}/embulk_workspace"

        timestamp = Time.now.strftime("%Y%m%d%H%M%S%6N")
        upload! config_path, "#{workspace_dir}/config_#{timestamp}.yml"

        within workspace_dir do
          execute :embulk, "run", "config_#{timestamp}.yml"
        end
      end
    end

    private

    def default_emr_options
      {
        name: "Embulk-#{Time.now.strftime("%Y%m%d%H%M%S")}",
        release_label: "emr-4.2.0",
        steps: [],
        visible_to_all_users: true,
      }
    end

    def on_instance(user, instance, ec2_key_path, &block)
      host = SSHKit::Host.new("#{user}@#{instance.public_ip_address}")
      host.key = ec2_key_path
      with_debug_log do
        SSHKit::Coordinator.new([host]).each(&block)
      end
    end

    def with_debug_log
      current_output_verbosity = SSHKit.config.output_verbosity
      SSHKit.config.output_verbosity = :debug
      yield
    ensure
      SSHKit.config.output_verbosity = current_output_verbosity
    end

    def emr_client(
      aws_access_key_id: nil,
      aws_secret_access_key: nil,
      aws_region: nil
    )
      client_options = {
        access_key_id: aws_access_key_id,
        secret_access_key: aws_secret_access_key,
        region: aws_region,
      }.reject { |_, v| v.nil? }

      if client_options.empty?
        Aws::EMR::Client.new
      else
        Aws::EMR::Client.new(client_options)
      end
    end
  end
end
