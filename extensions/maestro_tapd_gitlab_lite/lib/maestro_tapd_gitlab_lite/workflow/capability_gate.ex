defmodule MaestroTapdGitlabLite.Workflow.CapabilityGate do
  @moduledoc "Fail-fast inventory gate for the Lite workflow."

  @required_capabilities [
    "repo.remote_search",
    "repo.sparse_add",
    "tracker.complete_ai_workflow"
  ]

  @spec validate(term()) :: :ok | {:error, term()}
  def validate(settings) when is_map(settings) do
    if lite_workflow?(settings), do: validate_inventory(), else: :ok
  end

  def validate(_settings), do: :ok

  @spec required_capabilities() :: [String.t()]
  def required_capabilities, do: @required_capabilities

  @spec required_capabilities(term()) :: [String.t()]
  def required_capabilities(settings) when is_map(settings) do
    if lite_workflow?(settings), do: @required_capabilities, else: []
  end

  def required_capabilities(_settings), do: []

  defp validate_inventory do
    context = SymphonyElixir.Agent.DynamicTool.capture_context()

    case SymphonyElixir.Agent.DynamicTool.Inventory.resolve_required(
           context,
           @required_capabilities
         ) do
      {:ok, _tools} ->
        :ok

      {:error, error} ->
        {:error,
         {:lite_required_tool_unavailable, Map.get(error, :capability), Map.get(error, :reason)}}
    end
  end

  defp lite_workflow?(settings) do
    field(settings, :tracker) |> field(:kind) == "tapd" and
      field(settings, :workflow) |> field(:profile) |> field(:kind) == "coding_pr_delivery" and
      field(settings, :repo) |> field(:provider) |> field(:kind) == "git" and
      field(settings, :repo) |> field(:provider) |> field(:options) |> field(:remote_code_search) ==
        "gitlab"
  end

  defp field(map, key) when is_map(map) and is_atom(key),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp field(_value, _key), do: nil
end
