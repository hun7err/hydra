defmodule Hydra do
  def init(relative_config_path) do
    full_path = File.cwd! |> Path.join(relative_config_path)
    %{"servers" => servers} = YamlElixir.read_from_file full_path
    servers
  end

  def deploy(script) do
  end
end
