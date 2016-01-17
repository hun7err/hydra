defmodule Deploy do
  def containerParams() do
    { "/bin/bash",
      ["-c",
       "(export IP_ADDR=`ip a | tail -4 | head -1 | tr -s \" \" | cut -d\" \" -f3 | cut -d/ -f1` && epmd -daemon && iex -e \"Node.start :\\\"cohort@$IP_ADDR\\\"; Node.set_cookie :test; Node.connect :\\\"coordinator@172.18.0.1\\\"\" -S mix run -e \"pid = :global.whereis_name :coordinator; send pid, {:sync, self}\")"],
      "hydra-elixir",
      "hydra0"
    }
  end

  # etcd -listen-client-urls  "http://0.0.0.0:2379,http://0.0.0.0:4001" -advertise-client-urls "http://0.0.0.0:2379,http://0.0.0.0:4001"
  # sudo docker run --net=hydra0 -i -t trenpixster/elixir /bin/bash -c '(export IP_ADDR=`ip a | tail -4 | head -1 | tr -s " " | cut -d" " -f3 | cut -d/ -f1` && iex --name "cohort@$IP_ADDR" --cookie test)'

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
    defp gatherNodes(node_count, acc) when length(acc) < node_count do
      receive do
        {:sync, pid} ->
          IO.puts "got sync! currently " <> to_string(length(acc)+1) <> " nodes sync'd"
          gatherNodes(node_count, [pid|acc])
      end
    end
    defp gatherNodes(node_count, acc) when length(acc) == node_count, do: acc

    def init(cluster, container_names, version) do
      nodes = for host <- cluster, do: %Hive.Node{host: host}
      cluster = %Hive.Cluster{nodes: nodes}

      case Node.start :"coordinator@172.18.0.1" do
        {:ok, _} ->
          IO.puts "node started"
        {:error, {:already_started, pid}} ->
          IO.puts "node already started"
      end     
      
      Node.set_cookie :test
      :global.register_name :coordinator, self()
 
      command_outputs = for container_name <- container_names do
        {command, args, image, network} = Deploy.containerParams
        Hive.Cluster.run cluster, container_name, nil, image, [command | args], network
      end

      pids = gatherNodes length(command_outputs), []

      """
      pids = for {_, container} <- command_outputs do
        ip_addr = Hive.Docker.containerInfo(container)
          |> Dict.fetch!("NetworkSettings")
          |> Dict.fetch!("Networks")
          |> Dict.fetch!("hydra0")
          |> Dict.fetch!("IPAddress")

        node = String.to_atom("cohort@" <> ip_addr)
        
        Node.set_cookie :test
        case Node.connect node do
          true ->
            IO.puts "connected"
          false ->
            IO.puts "failed to connect"
          :ignored ->
            IO.puts "connection ignored"
        end
        
        ping_result = Node.ping node
        
        IO.puts "result from ping is :" <> to_string(ping_result)
        #Node.spawn_link String.to_atom("cohort@" <> ip_addr), fn -> Deploy.Cohort.loop(version) end
        Node.spawn_link node, fn -> IO.puts("hello world") end
      end
      """
      #results = for pid <- pids, do: 

      #loop version
    end

    def loop(version, state \\ :initial) do
      receive do
      end
    end
  end
end
