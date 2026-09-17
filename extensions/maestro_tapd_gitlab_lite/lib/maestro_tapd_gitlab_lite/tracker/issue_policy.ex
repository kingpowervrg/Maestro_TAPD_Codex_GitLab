defmodule MaestroTapdGitlabLite.Tracker.CompanyTapdIssuePolicy do
  @moduledoc "Company TAPD opt-in, routing, completion, and failure policy."

  @behaviour SymphonyElixir.Tracker.IssuePolicy

  alias MaestroTapdGitlabLite.Tracker.PolicyConfig

  @policy_id "maestro.tapd.company_ai"

  def id, do: @policy_id

  def supports?(tracker),
    do: tracker_kind(tracker) in [nil, "tapd"] and PolicyConfig.enabled?(tracker)

  def candidate_scope("bug", tracker) do
    if supports?(tracker) do
      %{
        states: PolicyConfig.active_states(tracker),
        filters: %{PolicyConfig.workflow_field(tracker) => PolicyConfig.accepted_value(tracker)}
      }
    end
  end

  def candidate_scope(_entity_type, _tracker), do: nil

  def enrich_issue(issue, %{tracker: tracker} = context) when is_map(issue) do
    raw_issue = Map.get(context, :raw_issue, %{})
    workflow_value = PolicyConfig.field_value(raw_issue, PolicyConfig.workflow_field(tracker))
    model_level = PolicyConfig.model_level(raw_issue, tracker)

    policy_fields = %{
      "workflow" => workflow_value,
      "model_level" => model_level,
      "policy_id" => id()
    }

    custom_fields =
      issue
      |> Map.get(:custom_fields, %{})
      |> Map.put(id(), policy_fields)
      |> Map.put("AI特殊工作流", workflow_value)
      |> Map.put("ai_special_workflow", workflow_value)
      |> Map.put("AI模型等级", model_level)
      |> Map.put("ai_model_level", model_level)

    agent_options =
      issue
      |> Map.get(:agent_options, %{})
      |> Map.put(:reasoning_effort, model_level)

    {:ok,
     issue |> Map.put(:custom_fields, custom_fields) |> Map.put(:agent_options, agent_options)}
  end

  def evaluate_dispatch(issue, %{tracker: tracker}) when is_map(issue) do
    policy_fields = issue |> Map.get(:custom_fields, %{}) |> Map.get(id(), %{})
    workflow_value = Map.get(policy_fields, "workflow")
    state = issue |> Map.get(:state) |> normalize_string() |> downcase()
    active_states = Enum.map(PolicyConfig.active_states(tracker), &downcase/1)

    if Map.get(issue, :entity_type) != "bug" or
         (workflow_value == PolicyConfig.accepted_value(tracker) and state in active_states) do
      :allow
    else
      {:deny, :company_tapd_policy_not_accepted}
    end
  end

  def complete(context) when is_map(context),
    do: MaestroTapdGitlabLite.Tracker.PolicyLifecycle.complete(context)

  def handle_failure(context) when is_map(context),
    do: MaestroTapdGitlabLite.Tracker.PolicyLifecycle.handle_failure(context)

  defp tracker_kind(tracker), do: field(tracker, :kind)

  defp field(map, key) when is_map(map),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp normalize_string(value) when is_binary(value), do: String.trim(value)
  defp normalize_string(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_string(_value), do: ""
  defp downcase(value), do: value |> normalize_string() |> String.downcase()
end
