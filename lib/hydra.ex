defmodule Hydra do
  # cohort:
  #   sudo docker run --net=hydra0 -i -t trenpixster/elixir /bin/bash -c '(export IP_ADDR=`ip a | tail -4 | head -1 | tr -s " " | cut -d" " -f3 | cut -d/ -f1` && iex --name "cohort@$IP_ADDR" --cookie test)'
  # coordinator:
  #   iex --name "coordinator@172.18.0.1" --cookie test

  # TODO:
  # - create a test application
  # - application deploy script
  # - test container links
  # - haproxy
  # ? distribute containers among nodes

  def parseConfig(relative_config_path) do
    full_path = File.cwd! |> Path.join(relative_config_path)
    YamlElixir.read_from_file full_path
  end

  def containerNames(project_name, version, counter, offset \\ 0, acc \\ []) when counter > 0 do
    acc = ["hydra-" <> project_name <> "-v" <> to_string(version) <> "-node" <> to_string(counter+offset) | acc]
    containerNames(project_name, version, counter-1, offset, acc)
  end
  def containerNames(_, _, counter, _, acc) when counter == 0, do: acc

  def init(project_name, deploy_script \\ "#!/bin/bash\necho 'deploy'", config_path \\ "config.yml") do
    config = parseConfig config_path
    servers = Dict.fetch!(Dict.fetch!(config, "hive"), "servers")
 
    nodes = for host <- servers, do: %Hive.Node{host: host}
    cluster = %Hive.Cluster{nodes: nodes}

    project_name = String.replace project_name, " ", "_"
    containers = containerNames project_name, 1, Dict.fetch!(config, "instances_per_node")
    Deploy.Coordinator.init cluster, containers, 1, deploy_script
  end

  def deploy(project_name, deploy_script \\ "#!/bin/bash\necho 'deploy'", config_path \\ "config.yml") do
    config = parseConfig config_path
    servers = Dict.fetch!(Dict.fetch!(config, "hive"), "servers")

    node_count = Dict.fetch!(config, "instances_per_node")
    project_name = String.replace project_name, " ", "_"
    containers = containerNames project_name, 0, node_count
    
    nodes = for host <- servers, do: %Hive.Node{host: host}
    cluster = %Hive.Cluster{nodes: nodes}
    
    case Deploy.Coordinator.init(cluster, containers, 0, deploy_script) do
      {:error, version, reason} ->
        IO.puts "Deploy failed for version " <> to_string(version) <> ". Reason: " <> reason
      {:ok, version} ->
        names = containerNames project_name, version-1, node_count
        conts = for container <- Hive.Cluster.containers(cluster, false, %{"name": names}), do:
          %Hive.Docker.Container{id: Dict.get(container, "Id"), node: %Hive.Node{}}
        Hive.Docker.remove(conts, true)

        #:ok
    end
  end
end
