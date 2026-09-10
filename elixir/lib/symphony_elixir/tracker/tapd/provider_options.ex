defmodule SymphonyElixir.Tracker.Tapd.ProviderOptions do
  @moduledoc false

  import SymphonyElixir.Tracker.ConfigAccess, only: [map_field: 2]

  alias SymphonyElixir.Tracker.Config, as: TrackerConfig
  alias SymphonyElixir.Tracker.Tapd.Normalizer

  @type assignee_filter ::
          %{optional(:configured_assignee) => String.t(), required(:match_values) => MapSet.t(String.t())} | nil

  @spec assignee(map()) :: String.t() | nil
  def assignee(tracker) when is_map(tracker) do
    tracker
    |> TrackerConfig.provider()
    |> map_field("assignee")
    |> normalize_configured_assignee()
  end

  @spec routing_assignee_filter(map()) :: assignee_filter()
  def routing_assignee_filter(tracker) when is_map(tracker) do
    case assignee(tracker) do
      nil ->
        nil

      configured_assignee ->
        %{
          configured_assignee: configured_assignee,
          match_values: MapSet.new([Normalizer.normalize_assignee_match_value(configured_assignee)])
        }
    end
  end

  defp normalize_configured_assignee(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_configured_assignee(_value), do: nil
end
