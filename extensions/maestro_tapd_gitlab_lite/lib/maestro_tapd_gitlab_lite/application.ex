defmodule MaestroTapdGitlabLite.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    register_core_overrides()

    Supervisor.start_link([], strategy: :one_for_one, name: MaestroTapdGitlabLite.Supervisor)
  end

  defp register_core_overrides do
    if Application.get_env(:maestro_tapd_gitlab_lite, :enabled, true) do
      register_workflow_source()
      register_repo_adapter()
      register_automation_source()
      register_issue_policy()
    end
  end

  defp register_workflow_source do
    update_env(:workflow_runtime_extensions, fn config ->
      sources = config |> Keyword.get(:sources, []) |> List.wrap()
      Keyword.put(config, :sources, Enum.uniq(sources ++ [MaestroTapdGitlabLite.RegistrySource]))
    end)
  end

  defp register_repo_adapter do
    update_env(:repo_provider_adapters, fn adapters ->
      adapters
      |> normalize_map()
      |> Map.put("git", MaestroTapdGitlabLite.Repo.GitlabLiteBackend)
    end)
  end

  defp register_automation_source do
    update_env(:workspace_automation_sources, fn sources ->
      sources = sources |> List.wrap() |> Enum.reject(&(&1 == MaestroTapdGitlabLite.RepoBootstrap.AutomationSource))
      sources ++ [MaestroTapdGitlabLite.RepoBootstrap.AutomationSource]
    end)
  end

  defp register_issue_policy do
    update_env(:issue_policies, fn policies ->
      policies = policies |> List.wrap() |> Enum.reject(&(&1 == MaestroTapdGitlabLite.Tracker.CompanyTapdIssuePolicy))
      policies ++ [MaestroTapdGitlabLite.Tracker.CompanyTapdIssuePolicy]
    end)
  end

  defp update_env(key, update) when is_function(update, 1) do
    current = Application.get_env(:symphony_elixir, key, default_for(key))
    Application.put_env(:symphony_elixir, key, update.(current))
  end

  defp default_for(:workflow_runtime_extensions), do: [sources: []]
  defp default_for(:repo_provider_adapters), do: %{}
  defp default_for(:workspace_automation_sources), do: []
  defp default_for(:issue_policies), do: []

  defp normalize_map(value) when is_map(value), do: value

  defp normalize_map(value) when is_list(value), do: Map.new(value)
  defp normalize_map(_value), do: %{}
end
