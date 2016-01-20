defmodule Deploy do
  def containerParams(version) do
    { "/bin/bash",
      ["-c",
       "(export IP_ADDR=`ip a | tail -4 | head -1 | tr -s \" \" | cut -d\" \" -f3 | cut -d/ -f1` && epmd -daemon && iex -e \"Node.start :\\\"cohort@$IP_ADDR\\\"; Node.set_cookie :test; Node.connect :\\\"coordinator@172.18.0.1\\\"\" -S mix run -e \"pid = :global.whereis_name :coordinator; send pid, {:sync," <> to_string(version) <> ",self}\")"],
      "hydra-elixir",
      "hydra0"
    }
  end

  def sendAll(list, message) when list != [] do
    [pid|tail] = list
    ret = send pid, message

    [ret|sendAll(tail, message)]
  end
  def sendAll(list, _) when list == [], do: []

  def runScript(name, content) do
    path = "/tmp/" <> name <> ".run"
    File.rm path
    File.touch path

    {:ok, script} = File.open path, [:write]
    IO.binwrite script, content
    File.close script

    {out, code} = System.cmd "chmod", ["+x", path]
    
    case code do
      0 ->
        {:error, out}
      _ ->
        {out, code} = System.cmd path, []
        case code do
          0 ->
            {:ok, out}
          _ ->
            {:error, out}
        end
    end
  end

  defmodule Cohort do
    defp cleanup(cleanup_script) do
      Deploy.runScript "cleanup", cleanup_script
      File.rm "/tmp/cleanup.run"
    end

    def loop(version, coordinator, cleanup_script \\ "", state \\ :initial) do
      receive do
        {:commit_request, version_number, deploy_script} -> 
          if version == version_number do
            IO.puts "commit request nr " <> to_string version_number

            case Deploy.runScript("deploy", deploy_script) do
              {:ok, _} ->
                send coordinator, {:agreed_req, version, self}

                loop version, coordinator, cleanup_script, :waiting
              {:error, reason} ->
                send coordinator, {:abort_req, version, reason}

                loop version, coordinator, cleanup_script, :abort
            end # case Deploy.runScript
          else
            loop version, coordinator, cleanup_script, state
          end # if version == version_number
        {:abort, version_number} ->
          if version == version_number do
            IO.puts "abort nr " <> to_string version_number
            cleanup(cleanup_script)

            :abort
          else
            loop version, coordinator, cleanup_script, state
          end
        {:prepare, version_number} -> 
          if version == version_number do
            IO.puts "prepare nr " <> to_string version_number
            send(coordinator, {:prepare_ack, version})

            loop version, coordinator, cleanup_script, :prepare
          else
            loop version, coordinator, cleanup_script, state
          end
        {:commit, version_number} ->
          if version == version_number do
            File.rm "/tmp/deploy.run"
            File.rm "/tmp/cleanup.run"

            :commit
          else
            loop version, coordinator, cleanup_script, state
          end
      after
        30_000 -> # timeout
          case state do
            st when st in [:waiting, :abort] ->
              cleanup(cleanup_script)
          end # case state do
      end # receive do
    end # def loop
  end # def loop

  defmodule Coordinator do
    defp gatherNodes(node_count, version, acc) when length(acc) < node_count do
      receive do
        {:sync, vr, pid} ->
          if vr == version, do:
            gatherNodes(node_count, version, [pid|acc]),
          else:
            gatherNodes(node_count, version, acc)
      after
        15_000 ->
          raise "[!] Container synchronisation timeout"
      end
    end
    defp gatherNodes(node_count, _, acc) when length(acc) == node_count, do: acc

    defp syncAfterCommitRequest(node_count, version, acc) when length(acc) < node_count do
      receive do
        {:agreed_req, vr, pid} ->
          if vr == version, do:
            syncAfterCommitRequest(node_count, version, [pid|acc]),
          else:
            syncAfterCommitRequest(node_count, version, acc)
        {:abort_req, vr, reason} ->
          if vr == version, do:
            {:error, reason},
          else:
            syncAfterCommitRequest(node_count, version, acc)
      after
        30_000 ->
          {:error, "node timeout (commit request)"}
      end
    end
    defp syncAfterCommitRequest(node_count, _, acc) when length(acc) == node_count, do: {:ok, acc}

    def syncAfterPrepare(node_count, version, counter \\ 0) when counter < node_count do
      receive do
        {:prepare_ack, vr} ->
          if vr == version do
            syncAfterPrepare(node_count, version, counter+1)
          else
            syncAfterPrepare(node_count, version, counter)
          end
      after
        30_000 ->
          {:error, "node timeout (prepare)"}
      end
    end
    def syncAfterPrepare(node_count, _, counter) when counter == node_count, do: :ok

    def init(cluster, container_names, version, deploy_script \\ "", cleanup_script \\ "") do
      nodes = for host <- cluster, do: %Hive.Node{host: host}
      cluster = %Hive.Cluster{nodes: nodes}

      Node.start :"coordinator@172.18.0.1"
      Node.set_cookie :test
      :global.register_name :coordinator, self()
 
      command_outputs = for container_name <- container_names do
        {command, args, image, network} = Deploy.containerParams version
        Hive.Cluster.run cluster, container_name, nil, image, [command | args], network
      end

      node_count = length command_outputs
      gatherNodes length(command_outputs), version, []  # simple synchronization barrier

      nodes = for {_, container} <- command_outputs do
        ip_addr = Hive.Docker.containerInfo(container)
          |> Dict.fetch!("NetworkSettings")
          |> Dict.fetch!("Networks")
          |> Dict.fetch!("hydra0")
          |> Dict.fetch!("IPAddress")

        node = String.to_atom("cohort@" <> ip_addr)
        Node.spawn_link node, Deploy.Cohort, :loop, [version, self, cleanup_script]
      end

      IO.puts "[*] All nodes spawned, synchronizing..."

      loop version, nodes, node_count, :initial, deploy_script
    end

    def loop(version, nodes, node_count, state \\ :initial, param \\ "") do
      case state do
        :initial ->
          Deploy.sendAll nodes, {:commit_request, version, param}
          loop version, nodes, node_count, :waiting, param
        :waiting ->
          case syncAfterCommitRequest node_count, version, [] do
            {:error, reason} ->
              loop version, nodes, node_count, :abort, reason
            {:ok, _} ->
              loop version, nodes, node_count, :commit, param

              Deploy.sendAll nodes, {:prepare, version}
              case syncAfterPrepare(node_count, version) do
                {:error, reason} ->
                  loop version, nodes, node_count, :abort, reason
                :ok ->
                  loop version, nodes, node_count, :commit, param
              end # case syncAfterPrepare
          end # case syncAfterCommitRequest
        :commit ->
          IO.puts "[+] Deploy finished successfully"
          :ok
        :abort ->
          Deploy.sendAll nodes, {:abort, version}
          IO.puts "[!] Deploy failed due to at least one node failing. Reason: \"" <> param <> "\""
          {:error, param}
      end # case state do
    end # def loop
  end # defmodule Coordinator
end
