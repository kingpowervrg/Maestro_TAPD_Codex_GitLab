defmodule SymphonyElixir.Tracker.Tapd.Normalizer do
  @moduledoc """
  Normalizes TAPD Story payloads into `SymphonyElixir.Issue`.
  """

  alias SymphonyElixir.Issue
  alias SymphonyElixir.Tracker.Tapd.{BugAIWorkflow, StoryBranch}
  alias SymphonyElixir.Workflow.Lifecycle, as: WorkflowLifecycle

  @type assignee_filter ::
          %{optional(:configured_assignee) => String.t(), required(:match_values) => MapSet.t(String.t())} | nil

  @spec normalize_story(map(), keyword()) :: Issue.t() | nil
  def normalize_story(story, opts \\ [])

  def normalize_story(story, opts) when is_map(story) and is_list(opts) do
    story_id = string_field(story, "id")
    state_phase_map = Keyword.get(opts, :state_phase_map, %{})
    state = string_field(story, "status")
    workflow = Keyword.get(opts, :workflow, %{})
    workitem_type_id = string_field(story, "workitem_type_id")
    assignee_filter = Keyword.get(opts, :assignee_filter)
    assignees = assignee_values(story)

    blocked_by =
      merge_blockers(
        extract_blockers(story, state_phase_map),
        Keyword.get(opts, :blocked_by, [])
      )

    %Issue{
      id: story_id,
      identifier: story_identifier(story_id),
      title: string_field(story, "name") || string_field(story, "title"),
      description: string_field(story, "description"),
      priority: parse_priority(string_field(story, "priority")),
      state: state,
      lifecycle_phase: WorkflowLifecycle.phase_for_state(state, state_phase_map),
      workitem_type_id: normalize_string(workitem_type_id),
      entity_type: "story",
      branch_name: StoryBranch.from_description(string_field(story, "description")),
      url: Keyword.get(opts, :workspace_url),
      assignee_id: assignee_id(assignees),
      blocked_by: blocked_by,
      labels: extract_labels(story),
      workflow: workflow,
      assigned_to_worker: assigned_to_worker?(assignees, assignee_filter),
      created_at: parse_datetime(string_field(story, "created")),
      updated_at: parse_datetime(string_field(story, "modified") || string_field(story, "updated"))
    }
  end

  def normalize_story(_story, _opts), do: nil

  @spec normalize_bug(map(), map(), keyword()) :: Issue.t() | nil
  def normalize_bug(bug, tracker, opts \\ [])

  def normalize_bug(bug, tracker, opts) when is_map(bug) and is_map(tracker) and is_list(opts) do
    bug_id = string_field(bug, "id")
    state = string_field(bug, "status")
    state_phase_map = Keyword.get(opts, :state_phase_map, %{})
    workflow = Keyword.get(opts, :workflow, %{})
    assignee_filter = Keyword.get(opts, :assignee_filter)
    assignees = bug_assignee_values(bug)
    ai_workflow_value = BugAIWorkflow.value(bug, tracker)

    %Issue{
      id: bug_id,
      identifier: story_identifier(bug_id),
      title: string_field(bug, "title") || string_field(bug, "name"),
      description: string_field(bug, "description"),
      priority: parse_priority(string_field(bug, "priority")),
      state: state,
      lifecycle_phase: WorkflowLifecycle.phase_for_state(state, state_phase_map),
      workitem_type_id: "bug",
      entity_type: "bug",
      branch_name: StoryBranch.from_description(string_field(bug, "description")),
      url: Keyword.get(opts, :issue_url),
      assignee_id: assignee_id(assignees),
      blocked_by: [],
      labels: extract_labels(bug),
      custom_fields: %{
        "AI特殊工作流" => ai_workflow_value,
        "ai_special_workflow" => ai_workflow_value
      },
      workflow: workflow,
      assigned_to_worker:
        assigned_to_worker?(assignees, assignee_filter) and
          BugAIWorkflow.accepted?(bug, tracker) and
          not BugAIWorkflow.exception?(bug, tracker),
      created_at: parse_datetime(string_field(bug, "created")),
      updated_at: parse_datetime(string_field(bug, "modified") || string_field(bug, "updated"))
    }
  end

  def normalize_bug(_bug, _tracker, _opts), do: nil

  @doc false
  @spec normalize_assignee_match_value(term()) :: String.t() | nil
  def normalize_assignee_match_value(value) when is_binary(value) do
    case value |> String.trim() |> String.downcase() do
      "" -> nil
      normalized -> normalized
    end
  end

  def normalize_assignee_match_value(_value), do: nil

  defp story_identifier(nil), do: nil
  defp story_identifier(story_id), do: "TAPD-" <> story_id

  defp assignee_values(story) do
    story
    |> Map.get("owner", Map.get(story, :owner))
    |> normalize_assignee_values()
  end

  defp bug_assignee_values(bug) do
    bug
    |> Map.get("current_owner", Map.get(bug, :current_owner))
    |> normalize_assignee_values()
  end

  defp normalize_assignee_values(values) when is_list(values) do
    values
    |> Enum.flat_map(&normalize_assignee_values/1)
    |> Enum.uniq()
  end

  defp normalize_assignee_values(value) when is_binary(value) do
    value
    |> String.split(";", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp normalize_assignee_values(_value), do: []

  defp assignee_id([]), do: nil
  defp assignee_id(assignees), do: Enum.join(assignees, ";")

  defp assigned_to_worker?(_assignees, nil), do: true

  defp assigned_to_worker?(assignees, %{match_values: match_values})
       when is_struct(match_values, MapSet) do
    Enum.any?(assignees, fn assignee ->
      assignee
      |> normalize_assignee_match_value()
      |> then(&MapSet.member?(match_values, &1))
    end)
  end

  defp assigned_to_worker?(_assignees, _assignee_filter), do: false

  defp extract_labels(story) do
    case Map.get(story, "labels") || Map.get(story, "label") do
      values when is_list(values) ->
        values
        |> Enum.map(&normalize_string/1)
        |> Enum.reject(&is_nil/1)

      values when is_binary(values) ->
        values
        |> String.split(",", trim: true)
        |> Enum.map(&normalize_string/1)
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end

  defp extract_blockers(story, state_phase_map) do
    story
    |> Map.take(["blocked_by", "blockers", "dependencies"])
    |> Map.values()
    |> Enum.flat_map(&normalize_blocker_value(&1, state_phase_map))
  end

  defp normalize_blocker_value(values, state_phase_map) when is_list(values) do
    values
    |> Enum.flat_map(&normalize_blocker_value(&1, state_phase_map))
  end

  defp normalize_blocker_value(%{} = blocker, state_phase_map) do
    blocker_id = string_field(blocker, "id")
    blocker_state = string_field(blocker, "status")

    if is_nil(blocker_id) do
      []
    else
      [
        %{
          id: blocker_id,
          identifier: story_identifier(blocker_id),
          state: blocker_state,
          lifecycle_phase: WorkflowLifecycle.phase_for_state(blocker_state, state_phase_map)
        }
      ]
    end
  end

  defp normalize_blocker_value(value, _state_phase_map) when is_binary(value) do
    case normalize_string(value) do
      nil ->
        []

      blocker_id ->
        [
          %{
            id: blocker_id,
            identifier: story_identifier(blocker_id),
            state: nil,
            lifecycle_phase: nil
          }
        ]
    end
  end

  defp normalize_blocker_value(_value, _state_phase_map), do: []

  defp merge_blockers(existing_blockers, additional_blockers) do
    (existing_blockers ++ List.wrap(additional_blockers))
    |> Enum.reduce([], fn
      %{id: blocker_id} = blocker, acc when is_binary(blocker_id) ->
        merge_blocker(acc, blocker_id, blocker)

      _blocker, acc ->
        acc
    end)
  end

  defp merge_blocker(acc, blocker_id, blocker) do
    case Enum.find_index(acc, &(&1.id == blocker_id)) do
      nil ->
        acc ++ [blocker]

      index ->
        List.update_at(acc, index, fn existing ->
          existing
          |> Map.put_new(:identifier, blocker[:identifier])
          |> maybe_put_value(:state, blocker[:state])
          |> maybe_put_value(:lifecycle_phase, blocker[:lifecycle_phase])
        end)
    end
  end

  defp maybe_put_value(map, _key, nil), do: map

  defp maybe_put_value(map, key, value) do
    case Map.get(map, key) do
      nil -> Map.put(map, key, value)
      _existing -> map
    end
  end

  defp string_field(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) || Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> Map.get(map, key)
  end

  defp normalize_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_string(value), do: if(value in [nil, ""], do: nil, else: to_string(value))

  defp parse_priority(nil), do: nil
  defp parse_priority(value) when is_integer(value), do: value

  defp parse_priority(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {priority, ""} -> priority
      _ -> nil
    end
  end

  defp parse_priority(_value), do: nil

  defp parse_datetime(nil), do: nil

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} ->
        datetime

      _ ->
        nil
    end
  end

  defp parse_datetime(_value), do: nil
end
