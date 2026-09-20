defmodule SymphonyElixir.Tracker.IssuePolicy.Runtime do
  @moduledoc "Public dispatcher for configured issue-policy lifecycle callbacks."

  alias SymphonyElixir.Issue
  alias SymphonyElixir.Tracker.IssuePolicy.Registry

  @spec enrich_issue(Issue.t(), map(), map()) :: {:ok, Issue.t()} | {:error, term()}
  def enrich_issue(%Issue{} = issue, tracker, context \\ %{}) when is_map(tracker) and is_map(context) do
    Enum.reduce_while(Registry.matching(tracker), {:ok, issue}, fn policy, {:ok, current} ->
      case policy.enrich_issue(current, Map.merge(context, %{tracker: tracker})) do
        {:ok, %Issue{} = enriched} -> {:cont, {:ok, enriched}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @spec evaluate_dispatch(Issue.t(), map(), map()) :: :allow | {:deny, term()}
  def evaluate_dispatch(%Issue{} = issue, tracker, context \\ %{}) when is_map(tracker) and is_map(context) do
    Enum.reduce_while(Registry.matching(tracker), :allow, fn policy, :allow ->
      case policy.evaluate_dispatch(issue, Map.merge(context, %{tracker: tracker})) do
        :allow -> {:cont, :allow}
        {:deny, _reason} = denied -> {:halt, denied}
      end
    end)
  end

  @spec candidate_scope(String.t(), map()) :: map() | nil
  def candidate_scope(entity_type, tracker) when is_binary(entity_type) and is_map(tracker) do
    Enum.find_value(Registry.matching(tracker), fn policy ->
      if function_exported?(policy, :candidate_scope, 2), do: policy.candidate_scope(entity_type, tracker)
    end)
  end

  @spec complete(map(), map()) :: {:ok, term()} | {:error, term()}
  def complete(tracker, context) when is_map(tracker) and is_map(context),
    do: invoke_first(tracker, :complete, context)

  @spec handle_failure(map(), map()) :: :ok | {:error, term()}
  def handle_failure(tracker, context) when is_map(tracker) and is_map(context) do
    case Registry.matching(tracker) do
      [] -> :ok
      policies -> reduce_failures(policies, Map.put(context, :tracker, tracker))
    end
  end

  @spec handle_operator_stop(map(), map()) :: :ok | :unhandled | {:error, term()}
  def handle_operator_stop(tracker, context) when is_map(tracker) and is_map(context) do
    case Registry.matching(tracker) do
      [] -> :unhandled
      policies -> reduce_operator_stops(policies, Map.put(context, :tracker, tracker))
    end
  end

  @spec operator_stop_supported?(map()) :: boolean()
  def operator_stop_supported?(tracker) when is_map(tracker) do
    Registry.matching(tracker)
    |> Enum.any?(&function_exported?(&1, :handle_operator_stop, 1))
  end

  def operator_stop_supported?(_tracker), do: false

  defp invoke_first(tracker, callback, context) do
    case Registry.matching(tracker) do
      [policy | _rest] -> apply(policy, callback, [Map.put(context, :tracker, tracker)])
      [] -> {:error, :issue_policy_not_configured}
    end
  end

  defp reduce_failures(policies, context) do
    Enum.reduce_while(policies, :ok, fn policy, :ok ->
      case policy.handle_failure(context) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp reduce_operator_stops(policies, context) do
    Enum.reduce_while(policies, :unhandled, fn policy, :unhandled ->
      if function_exported?(policy, :handle_operator_stop, 1) do
        case policy.handle_operator_stop(context) do
          :ok -> {:halt, :ok}
          :unhandled -> {:cont, :unhandled}
          {:error, _reason} = error -> {:halt, error}
        end
      else
        {:cont, :unhandled}
      end
    end)
  end
end
