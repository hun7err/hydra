defmodule Hydra do
  # cohort:
  #   sudo docker run --net=hydra0 -i -t trenpixster/elixir /bin/bash -c '(export IP_ADDR=`ip a | tail -4 | head -1 | tr -s " " | cut -d" " -f3 | cut -d/ -f1` && iex --name "cohort@$IP_ADDR" --cookie test)'
  # coordinator:
  #   iex --name "coordinator@172.18.0.1" --cookie test

  defp get_servers(relative_config_path) do
    full_path = File.cwd! |> Path.join(relative_config_path)
    %{"servers" => servers,
      "instances_per_node" => instances_per_node} = YamlElixir.read_from_file full_path
    servers
  end

  def deploy(script, config_path \\ "config.yml") do
  end
end
