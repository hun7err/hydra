defmodule Deploy do
  def containerParams(container_name) do
    { "/bin/bash",
      ["-c",
       "(export IP_ADDR=`ip a | tail -4 | head -1 | tr -s \" \" | cut -d\" \" -f3 | cut -d/ -f1` && git init && git remote add origin https://github.com/hun7err/hydra.git && git fetch && git checkout -t origin/devel && mix deps.get && iex --name \"cohort@$IP_ADDR\" --cookie test -S mix)"],
      "trenpixster/elixir",
      "hydra0"
    }
  end

  #sudo docker run --net=hydra0 -i -t trenpixster/elixir /bin/bash -c '(export IP_ADDR=`ip a | tail -4 | head -1 | tr -s " " | cut -d" " -f3 | cut -d/ -f1` && iex --name "cohort@$IP_ADDR" --cookie test)'

  defmodule Cohort do
    defp cleanup() do
    end

    def loop(version, state \\ :initial) do # can return :cleanup or
      receive do
        {:commit_request, version_number, deploy_script} ->
          IO.puts "commit request nr " <> to_string version_number
          # here do some deploy stuff (launching the deploy script)
          new_state = :commit # here should be the return code of deploy()
          loop version, new_state
        {:abort, version_number} ->
          :cleanup
        {:prepare, version_number} ->
          loop version, :prepare
        {:commit, version_number} ->
          :commit
      after
        5 -> # timeout
          case state do
            st when st in [:agreed, :abort] ->
              :cleanup
          end
      end
    end
  end

  defmodule Coordinator do
    def init(cluster, container_names, version) do
      nodes = for host <- cluster, do: %Hive.Node{host: host}
      cluster = %Hive.Cluster{nodes: nodes}

      command_outputs = for container_name <- container_names do
        {command, args, image, network} = Deploy.containerParams container_name
        Hive.Cluster.run cluster, container_name, [], image, [command | args], network
      end

      #loop version
    end

    def loop(version, state \\ :initial) do
      receive do
      end
    end
  end
end
