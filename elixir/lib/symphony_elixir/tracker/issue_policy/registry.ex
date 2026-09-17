defmodule SymphonyElixir.Tracker.IssuePolicy.Registry do
  @moduledoc "Configured registry for external tracker issue policies."

  alias SymphonyElixir.Tracker.IssuePolicy

  @spec policies() :: [module()]
  def policies do
    :symphony_elixir
    |> Application.get_env(:issue_policies, [])
    |> List.wrap()
    |> Enum.map(&validate!/1)
  end

  @spec matching(map()) :: [module()]
  def matching(tracker) when is_map(tracker) do
    Enum.filter(policies(), & &1.supports?(tracker))
  end

  def matching(_tracker), do: []

  defp validate!(module) when is_atom(module) do
    required = [id: 0, supports?: 1, enrich_issue: 2, evaluate_dispatch: 2, complete: 1, handle_failure: 1]

    if Code.ensure_loaded?(module) and
         Enum.all?(required, fn {name, arity} -> function_exported?(module, name, arity) end) and
         IssuePolicy in List.flatten(Keyword.get_values(module.module_info(:attributes), :behaviour)) do
      module
    else
      raise ArgumentError, "invalid tracker issue policy: #{inspect(module)}"
    end
  end

  defp validate!(value), do: raise(ArgumentError, "invalid tracker issue policy: #{inspect(value)}")
end
