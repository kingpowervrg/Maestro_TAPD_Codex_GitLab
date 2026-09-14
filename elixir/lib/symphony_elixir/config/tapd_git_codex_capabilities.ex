defmodule SymphonyElixir.Config.TapdGitCodexCapabilities do
  @moduledoc false

  alias SymphonyElixir.Agent.DynamicTool
  alias SymphonyElixir.Agent.DynamicTool.Inventory
  alias SymphonyElixir.Agent.DynamicTool.Inventory.ResolutionError
  alias SymphonyElixir.Repo.Capabilities, as: RepoCapabilities
  alias SymphonyElixir.RepoProvider.Capabilities, as: RepoProviderCapabilities
  alias SymphonyElixir.Tracker.Capabilities, as: TrackerCapabilities

  @required_capabilities [
    RepoProviderCapabilities.remote_search(),
    RepoCapabilities.sparse_add(),
    TrackerCapabilities.complete_ai_workflow()
  ]

  @spec validate_required(map()) :: :ok | {:error, term()}
  def validate_required(settings) when is_map(settings) do
    if tapd_git_codex_workflow?(settings) do
      validate_inventory(@required_capabilities)
    else
      :ok
    end
  end

  def validate_required(_settings), do: :ok

  defp validate_inventory(required_capabilities) do
    tool_context = DynamicTool.capture_context()

    case Inventory.resolve_required(tool_context, required_capabilities) do
      {:ok, _tools} ->
        :ok

      {:error, %ResolutionError{reason: reason, capability: capability}} ->
        {:error, {:tapd_git_codex_required_tool_unavailable, capability, reason}}
    end
  end

  defp tapd_git_codex_workflow?(settings) do
    map_field(settings, :tracker) |> map_field(:kind) == "tapd" and
      map_field(settings, :workflow) |> map_field(:profile) |> map_field(:kind) == "coding_pr_delivery" and
      map_field(settings, :repo) |> map_field(:provider) |> map_field(:kind) == "git" and
      map_field(settings, :repo) |> map_field(:provider) |> map_field(:options) |> map_field(:remote_code_search) == "gitlab"
  end

  defp map_field(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp map_field(_map, _key), do: nil
end
