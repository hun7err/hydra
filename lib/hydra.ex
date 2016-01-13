defmodule Hydra do
  # cohort:
  #   sudo docker run --net=hydra0 -i -t trenpixster/elixir /bin/bash -c '(export IP_ADDR=`ip a | tail -4 | head -1 | tr -s " " | cut -d" " -f3 | cut -d/ -f1` && iex --name "cohort@$IP_ADDR" --cookie test)'
  # coordinator:
  #   iex --name "coordinator@172.18.0.1" --cookie test

  def parseConfig(relative_config_path) do
    full_path = File.cwd! |> Path.join(relative_config_path)
    config = YamlElixir.read_from_file full_path
  end

  def containerNames(project_name, version, counter, offset \\ 0, acc \\ []) when counter > 0 do
    acc = ["hydra-" <> project_name <> "-v" <> to_string(version) <> "-node" <> to_string(counter+offset) | acc]
    containerNames(project_name, version, counter-1, offset, acc)
  end
  def containerNames(project_name, version, counter, offset, acc) when counter == 0, do: acc

  def init(project_name, deploy_script \\ "", config_path \\ "config.yml") do
    config = parseConfig config_path
    servers = Dict.fetch!(Dict.fetch!(config, "hive"), "servers")

    project_name = String.replace project_name, " ", "_"
    containers = containerNames project_name, 1, Dict.fetch!(config, "instances_per_node")
    Deploy.Coordinator.init servers, containers, 1
  end

  def deploy(script, config_path \\ "config.yml") do
  end
end
