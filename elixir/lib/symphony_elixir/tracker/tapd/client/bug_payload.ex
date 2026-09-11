defmodule SymphonyElixir.Tracker.Tapd.Client.BugPayload do
  @moduledoc false

  alias SymphonyElixir.Tracker
  alias SymphonyElixir.Tracker.Tapd.Client.{Fields, Response}
  alias SymphonyElixir.Tracker.Tapd.{Normalizer, ProviderOptions, WorkflowConfig}

  @spec decode(String.t(), term(), map()) :: {:ok, [SymphonyElixir.Issue.t()], non_neg_integer()} | {:error, term()}
  def decode(path, body, tracker) when is_binary(path) and is_map(tracker) do
    with {:ok, data} <- Response.decode_success_envelope(path, body),
         true <- is_list(data) || {:error, {:unexpected_tapd_payload, path, body}},
         {:ok, raw_bugs} <- unwrap_bug_list(path, data, body) do
      workflow = WorkflowConfig.workflow_for_bug(tracker)
      workspace_id = Tracker.project_id(tracker)
      assignee_filter = ProviderOptions.routing_assignee_filter(tracker)

      issues =
        Enum.map(raw_bugs, fn bug ->
          Normalizer.normalize_bug(bug, tracker,
            assignee_filter: assignee_filter,
            issue_url: bug_url(workspace_id, Fields.string_field(bug, "id")),
            state_phase_map: workflow.state_phase_map,
            workflow: workflow
          )
        end)

      {:ok, issues, length(raw_bugs)}
    end
  end

  defp unwrap_bug_list(path, data, body) do
    data
    |> Enum.reduce_while({:ok, []}, fn entry, {:ok, acc} ->
      case unwrap_bug_node(entry) do
        {:ok, bug} -> {:cont, {:ok, acc ++ [bug]}}
        :error -> {:halt, {:error, {:unexpected_tapd_payload, path, body}}}
      end
    end)
  end

  defp unwrap_bug_node(%{"Bug" => %{} = bug}), do: {:ok, bug}
  defp unwrap_bug_node(%{Bug: %{} = bug}), do: {:ok, bug}

  defp unwrap_bug_node(%{} = bug) do
    if is_binary(Fields.string_field(bug, "id")) do
      {:ok, Fields.normalize_keys_to_strings(bug)}
    else
      :error
    end
  end

  defp unwrap_bug_node(_entry), do: :error

  defp bug_url(workspace_id, bug_id) when is_binary(workspace_id) and is_binary(bug_id) do
    "https://www.tapd.cn/tapd_fe/#{workspace_id}/bug/detail/#{bug_id}"
  end

  defp bug_url(_workspace_id, _bug_id), do: nil
end
