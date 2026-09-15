defmodule SymphonyElixir.Tracker.Tapd.BugAIWorkflow do
  @moduledoc false

  import SymphonyElixir.Tracker.ConfigAccess, only: [map_field: 2, provider_field: 2]

  alias SymphonyElixir.Tracker.Tapd.Client.Fields

  @default_active_states ["new", "reopened"]
  @default_accepted_value "接受/处理"
  @default_resolved_value "AI已解决"
  @default_exception_value "AI异常"

  @spec enabled?(map()) :: boolean()
  def enabled?(tracker) when is_map(tracker), do: is_binary(field(tracker))

  @spec field(map()) :: String.t() | nil
  def field(tracker) when is_map(tracker) do
    tracker
    |> config()
    |> map_field("field")
    |> Fields.normalize_string()
    |> case do
      value when is_binary(value) -> if valid_field?(value), do: value
      _value -> nil
    end
  end

  @spec valid_field?(term()) :: boolean()
  def valid_field?(value) when is_binary(value),
    do: Regex.match?(~r/^custom_field_[a-z0-9_]+$/, value)

  def valid_field?(_value), do: false

  @spec accepted_value(map()) :: String.t()
  def accepted_value(tracker) when is_map(tracker),
    do: config_string(tracker, "accepted_value") || @default_accepted_value

  @spec resolved_value(map()) :: String.t()
  def resolved_value(tracker) when is_map(tracker),
    do: config_string(tracker, "resolved_value") || @default_resolved_value

  @spec exception_value(map()) :: String.t()
  def exception_value(tracker) when is_map(tracker),
    do: config_string(tracker, "exception_value") || @default_exception_value

  @spec active_states(map()) :: [String.t()]
  def active_states(tracker) when is_map(tracker) do
    case map_field(config(tracker), "active_states") do
      values when is_list(values) ->
        values
        |> Enum.map(&Fields.normalize_string/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
        |> case do
          [] -> @default_active_states
          normalized -> normalized
        end

      _values ->
        @default_active_states
    end
  end

  @spec accepted?(map(), map()) :: boolean()
  def accepted?(bug, tracker) when is_map(bug) and is_map(tracker) do
    value(bug, tracker) == accepted_value(tracker)
  end

  @spec resolved?(map(), map()) :: boolean()
  def resolved?(bug, tracker) when is_map(bug) and is_map(tracker) do
    value(bug, tracker) == resolved_value(tracker)
  end

  @doc "Returns whether the Bug is marked as having encountered an AI exception."
  @spec exception?(map(), map()) :: boolean()
  def exception?(bug, tracker) when is_map(bug) and is_map(tracker),
    do: value(bug, tracker) == exception_value(tracker)

  @spec value(map(), map()) :: String.t() | nil
  def value(bug, tracker) when is_map(bug) and is_map(tracker) do
    case field(tracker) do
      field when is_binary(field) -> Fields.normalize_string(Fields.string_field(bug, field))
      _field -> nil
    end
  end

  defp config(tracker) do
    tracker
    |> provider_field("platform")
    |> map_field("bug_ai_workflow")
    |> case do
      value when is_map(value) -> value
      _value -> %{}
    end
  end

  defp config_string(tracker, key) do
    tracker
    |> config()
    |> map_field(key)
    |> Fields.normalize_string()
  end
end
