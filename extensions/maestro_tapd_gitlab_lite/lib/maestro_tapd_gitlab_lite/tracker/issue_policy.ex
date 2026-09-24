defmodule MaestroTapdGitlabLite.Tracker.CompanyTapdIssuePolicy do
  @moduledoc "Company TAPD opt-in, routing, completion, and failure policy."

  @behaviour SymphonyElixir.Tracker.IssuePolicy

  alias MaestroTapdGitlabLite.Tracker.PolicyConfig

  @policy_id "maestro.tapd.company_ai"

  @impl true
  def id, do: @policy_id

  @impl true
  def supports?(tracker),
    do: tracker_kind(tracker) in [nil, "tapd"] and PolicyConfig.enabled?(tracker)

  @impl true
  def candidate_scope(entity_type, tracker) when entity_type in ["bug", "story"] do
    if supports?(tracker) do
      %{
        states: PolicyConfig.active_states(tracker, entity_type),
        filters: policy_filters(tracker, entity_type)
      }
    end
  end

  def candidate_scope(_entity_type, _tracker), do: nil

  @impl true
  def enrich_issue(issue, %{tracker: tracker} = context) when is_map(issue) do
    raw_issue = Map.get(context, :raw_issue, %{})
    entity_type = Map.get(issue, :entity_type, "bug")
    workflow_value = PolicyConfig.field_value(raw_issue, PolicyConfig.workflow_field(tracker, entity_type))
    model_level = PolicyConfig.model_level(raw_issue, tracker, entity_type)

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

    {:ok, issue |> Map.put(:custom_fields, custom_fields) |> Map.put(:agent_options, agent_options)}
  end

  @impl true
  def evaluate_dispatch(issue, %{tracker: tracker}) when is_map(issue) do
    policy_fields = issue |> Map.get(:custom_fields, %{}) |> Map.get(id(), %{})
    workflow_value = Map.get(policy_fields, "workflow")
    state = issue |> Map.get(:state) |> normalize_string() |> downcase()
    entity_type = Map.get(issue, :entity_type, "bug")
    active_states = Enum.map(PolicyConfig.active_states(tracker, entity_type), &downcase/1)

    allowed? = workflow_value == PolicyConfig.accepted_value(tracker) and state in active_states

    if allowed? do
      :allow
    else
      {:deny, :company_tapd_policy_not_accepted}
    end
  end

  @impl true
  def complete(context) when is_map(context),
    do: MaestroTapdGitlabLite.Tracker.PolicyLifecycle.complete(context)

  @impl true
  def handle_failure(context) when is_map(context),
    do: MaestroTapdGitlabLite.Tracker.PolicyLifecycle.handle_failure(context)

  @impl true
  def handle_operator_stop(context) when is_map(context),
    do: MaestroTapdGitlabLite.Tracker.PolicyLifecycle.handle_failure(context)

  defp tracker_kind(tracker), do: field(tracker, :kind)

  defp policy_filters(tracker, entity_type) do
    case PolicyConfig.workflow_field(tracker, entity_type) do
      field when is_binary(field) -> %{field => PolicyConfig.accepted_value(tracker)}
      _ -> %{}
    end
  end

  defp field(map, key) when is_map(map),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp normalize_string(value) when is_binary(value), do: String.trim(value)
  defp normalize_string(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_string(_value), do: ""
  defp downcase(value), do: value |> normalize_string() |> String.downcase()
end
