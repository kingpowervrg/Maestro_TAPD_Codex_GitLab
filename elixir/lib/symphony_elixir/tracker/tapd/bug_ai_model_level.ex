defmodule SymphonyElixir.Tracker.Tapd.BugAIModelLevel do
  @moduledoc false

  import SymphonyElixir.Tracker.ConfigAccess, only: [map_field: 2, provider_field: 2]

  alias SymphonyElixir.Tracker.Tapd.Client.Fields

  @default_level "medium"
  @supported_levels ~w(low medium high xhigh)

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

  @spec level(map(), map()) :: String.t()
  def level(bug, tracker) when is_map(bug) and is_map(tracker) do
    raw_level =
      case field(tracker) do
        field when is_binary(field) -> Fields.string_field(bug, field)
        _field -> nil
      end

    normalize_level(raw_level)
  end

  @spec normalize_level(term()) :: String.t()
  def normalize_level(value) when is_binary(value) do
    normalized = value |> String.trim() |> String.downcase()
    if normalized in @supported_levels, do: normalized, else: @default_level
  end

  def normalize_level(_value), do: @default_level

  @spec default_level() :: String.t()
  def default_level, do: @default_level

  defp config(tracker) do
    tracker
    |> provider_field("platform")
    |> map_field("bug_ai_model_level")
    |> case do
      value when is_map(value) -> value
      _value -> %{}
    end
  end
end
