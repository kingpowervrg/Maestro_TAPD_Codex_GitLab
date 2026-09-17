defmodule MaestroTapdGitlabLite.Tracker.PolicyLifecycle do
  @moduledoc "Policy lifecycle effects executed through injected host operations."

  alias MaestroTapdGitlabLite.Tracker.{CompanyTapdIssuePolicy, PolicyConfig}

  @spec complete(map()) :: {:ok, term()} | {:error, term()}
  def complete(context) do
    with {:ok, issue} <- required_issue(context),
         tracker when is_map(tracker) <- Map.get(context, :tracker),
         :ok <- validate_active_bug(issue, tracker),
         :ok <- validate_current_value(issue, tracker, :complete),
         :ok <- maybe_update(issue, tracker, context, PolicyConfig.resolved_value(tracker)),
         {:ok, updated_issue} <- fetch_issue(context),
         :ok <- verify_value(updated_issue, tracker, PolicyConfig.resolved_value(tracker)) do
      {:ok,
       %{
         issue: updated_issue,
         custom_fields: %{
           "AI特殊工作流" => PolicyConfig.resolved_value(tracker),
           "aiSpecialWorkflow" => PolicyConfig.resolved_value(tracker)
         }
       }}
    else
      nil -> {:error, :issue_policy_tracker_missing}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec handle_failure(map()) :: :ok | {:error, term()}
  def handle_failure(context) do
    with {:ok, issue} <- required_issue(context),
         tracker when is_map(tracker) <- Map.get(context, :tracker),
         :ok <- validate_active_bug(issue, tracker),
         :ok <- validate_current_value(issue, tracker, :failure),
         :ok <- maybe_update(issue, tracker, context, PolicyConfig.exception_value(tracker)),
         {:ok, updated_issue} <- fetch_issue(context),
         :ok <- verify_value(updated_issue, tracker, PolicyConfig.exception_value(tracker)) do
      :ok
    else
      nil -> {:error, :issue_policy_tracker_missing}
      {:error, reason} -> {:error, reason}
    end
  end

  defp required_issue(%{issue: issue}) when is_map(issue), do: {:ok, issue}
  defp required_issue(_context), do: {:error, :issue_policy_issue_missing}

  defp validate_active_bug(issue, tracker) do
    state = issue |> Map.get(:state) |> normalize() |> String.downcase()

    active_states =
      Enum.map(PolicyConfig.active_states(tracker), &(normalize(&1) |> String.downcase()))

    cond do
      Map.get(issue, :entity_type) != "bug" ->
        {:error, {:invalid_arguments, "AI workflow lifecycle is supported only for TAPD Bugs."}}

      state not in active_states ->
        {:error, {:state_conflict, "TAPD Bug is no longer in an AI-active state."}}

      true ->
        :ok
    end
  end

  defp validate_current_value(issue, tracker, outcome) do
    current = workflow_value(issue)
    accepted = PolicyConfig.accepted_value(tracker)
    target = target_value(tracker, outcome)

    if current in [accepted, target] do
      :ok
    else
      {:error,
       {:state_conflict,
        %{
          "message" =>
            "TAPD Bug is no longer accepted for AI processing; refusing to overwrite its AI workflow.",
          "expected" => accepted,
          "actual" => current
        }}}
    end
  end

  defp maybe_update(issue, tracker, context, target) do
    if workflow_value(issue) == target do
      :ok
    else
      case Map.get(context, :update_fields) do
        fun when is_function(fun, 1) -> fun.(%{PolicyConfig.workflow_field(tracker) => target})
        _fun -> {:error, :issue_policy_update_operation_missing}
      end
    end
  end

  defp fetch_issue(context) do
    case Map.get(context, :fetch_issue) do
      fun when is_function(fun, 0) -> fun.()
      _fun -> {:error, :issue_policy_fetch_operation_missing}
    end
  end

  defp verify_value(issue, tracker, expected) do
    if workflow_value(issue) == expected do
      :ok
    else
      {:error,
       {:state_conflict,
        %{
          "message" => "TAPD Bug AI workflow read-back did not confirm the expected value.",
          "expected" => expected,
          "actual" => workflow_value(issue),
          "field" => PolicyConfig.workflow_field(tracker)
        }}}
    end
  end

  defp workflow_value(issue) do
    issue
    |> Map.get(:custom_fields, %{})
    |> Map.get(CompanyTapdIssuePolicy.id(), %{})
    |> Map.get("workflow")
  end

  defp target_value(tracker, :complete), do: PolicyConfig.resolved_value(tracker)
  defp target_value(tracker, :failure), do: PolicyConfig.exception_value(tracker)

  defp normalize(value) when is_binary(value), do: String.trim(value)
  defp normalize(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize(_value), do: ""
end
