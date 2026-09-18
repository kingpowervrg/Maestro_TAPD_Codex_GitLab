defmodule SymphonyElixir.Workspace.Context do
  @moduledoc false

  alias SymphonyElixir.Tracker

  @type worker_host :: String.t() | nil
  @type issue_context :: %{
          issue_id: term(),
          issue_identifier: String.t(),
          run_id: String.t() | nil,
          branch_name: String.t() | nil,
          reasoning_effort: String.t() | nil
        }

  @spec issue_context(map() | String.t() | nil) :: issue_context()
  def issue_context(%{id: issue_id, identifier: identifier} = issue) do
    %{
      issue_id: issue_id,
      issue_identifier: identifier || "issue",
      run_id: Map.get(issue, :run_id),
      branch_name: Map.get(issue, :branch_name),
      reasoning_effort: reasoning_effort(issue)
    }
  end

  def issue_context(identifier) when is_binary(identifier) do
    %{
      issue_id: nil,
      issue_identifier: identifier,
      run_id: nil,
      branch_name: nil,
      reasoning_effort: nil
    }
  end

  def issue_context(_identifier) do
    %{
      issue_id: nil,
      issue_identifier: "issue",
      run_id: nil,
      branch_name: nil,
      reasoning_effort: nil
    }
  end

  @spec workspace_context(Path.t()) :: issue_context()
  def workspace_context(workspace) when is_binary(workspace) do
    issue_context(Path.basename(workspace))
  end

  @spec event_fields(issue_context(), Path.t() | nil, worker_host(), map()) :: map()
  def event_fields(issue_context, workspace, worker_host, extra \\ %{})
      when is_map(issue_context) and is_map(extra) do
    %{
      component: "workspace",
      tracker_kind: tracker_kind(),
      run_id: issue_context[:run_id],
      correlation_id: issue_context[:run_id],
      issue_id: issue_context[:issue_id],
      issue_identifier: issue_context[:issue_identifier],
      workspace_path: workspace,
      worker_host: worker_host
    }
    |> Map.merge(extra)
  end

  defp tracker_kind, do: Tracker.current_kind()

  defp reasoning_effort(issue) when is_map(issue) do
    issue
    |> Map.get(:agent_options, %{})
    |> case do
      options when is_map(options) -> Map.get(options, :reasoning_effort) || Map.get(options, "reasoning_effort")
      _options -> nil
    end
    |> normalize_optional_string()
  end

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_string(_value), do: nil
end
