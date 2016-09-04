require "emrakul/version"

require 'tempfile'
require 'yaml'
require 'aws-sdk'
require 'sshkit'

module Emrakul
  class << self
    def run_emr(
      config,
      gemfile_path,
      ec2_key_path,
      access_key_id: nil,
      secret_access_key: nil,
      region: nil,
      user: "hadoop",
      emr_config: {},
      embulk_path: `which embulk`.chomp
    )
      raise "Need embulk" if embulk_path.nil? || embulk_path.empty?

      if config.is_a?(String)
        config_path = config
      elsif config.is_a?(Hash)
        tf = Tempfile.new(["emrakul", ".yml"])
        tf.write(YAML.dump(config))
        tf.flush
        config_path = tf.path
      else
        raise "config is not assigned"
      end

      client = emr_client(
        access_key_id: access_key_id,
        secret_access_key: secret_access_key,
        region: region
      )

      job_flow_id = run_cluster(client: client, emr_config: emr_config)
      master_instance = client.list_instances(cluster_id: job_flow_id, instance_group_types: ["MASTER"]).instances[0]

      setup_embulk(user, master_instance, ec2_key_path, embulk_path, gemfile_path)
      run_embulk(user, master_instance, ec2_key_path, config_path)
    ensure
      tf.close! if tf
      client.terminate_job_flows(job_flow_ids: [job_flow_id]) if job_flow_id
    end

    private

    def run_cluster(client:, emr_config:)
      emr_config =
        default_emr_options
        .tap { |o| o.delete(:applications) if emr_config[:applications] }
        .merge(emr_config)
      emr_config[:instances][:keep_job_flow_alive_when_no_steps] = true

      job_flow_id = client.run_job_flow(emr_config).job_flow_id
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
            upload! f, File.join(workspace_dir, File.basename(f))
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

        upload! config_path, "#{workspace_dir}/config.yml"

        within workspace_dir do
          execute :embulk, "run", "config.yml"
        end
      end
    end

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
      SSHKit::Coordinator.new([host]).each(&block)
    end

    def emr_client(
      access_key_id: nil,
      secret_access_key: nil,
      region: nil
    )
      client_options = {
        access_key_id: access_key_id,
        secret_access_key: secret_access_key,
        region: region,
      }.reject { |_, v| v.nil? }

      if client_options.empty?
        Aws::EMR::Client.new
      else
        Aws::EMR::Client.new(client_options)
      end
    end
  end
end
