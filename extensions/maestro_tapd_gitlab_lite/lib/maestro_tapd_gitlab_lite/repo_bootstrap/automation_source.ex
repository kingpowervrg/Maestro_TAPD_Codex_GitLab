defmodule MaestroTapdGitlabLite.RepoBootstrap.AutomationSource do
  @moduledoc "Workspace automation assets owned by the Lite repository bootstrap policy."

  @behaviour SymphonyElixir.Workspace.AutomationPack.Source

  def source_dir(_opts) do
    :maestro_tapd_gitlab_lite
    |> :code.priv_dir()
    |> to_string()
    |> Path.join("workspace_automation")
  end
end
