defmodule MaestroTapdGitlabLite.Tracker.IssueReader do
  @moduledoc "Preserves the entity category of known TAPD identities."
  alias SymphonyElixir.Agent.DynamicTool.Context
  alias SymphonyElixir.Tracker.Tapd.Client

  @spec fetch_issues_by_ids([String.t()], map(), keyword()) :: term()
  def fetch_issues_by_ids(issue_ids, tracker, opts) do
    read_opts = Keyword.put(opts, :tracker, tracker)
    case entity_type(issue_ids, opts) do
      "bug" -> Client.fetch_bugs_by_ids(issue_ids, read_opts)
      "story" -> Client.fetch_stories_by_ids(issue_ids, read_opts)
      _unknown -> :unhandled
    end
  end

  defp entity_type(issue_ids, opts) do
    case Keyword.get(opts, :entity_type) do
      value when value in ["bug", "story"] -> value
      _other -> contextual_entity_type(issue_ids, opts)
    end
  end

  defp contextual_entity_type(issue_ids, opts) do
    issue = Keyword.get(opts, :issue) || %{}
    context = Keyword.get(opts, :tool_context)
    id = Map.get(issue, :id) || Context.runtime_metadata_value(context, :issue_id)
    type = Map.get(issue, :entity_type) || Context.runtime_metadata_value(context, :entity_type)

    if is_binary(id) and type in ["bug", "story"] and
         Enum.all?(issue_ids, &(&1 == String.replace_prefix(id, "TAPD-", ""))) do
      type
    end
  end
end
