defmodule SymphonyElixir.Config.Schema.AgentExecution do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  alias SymphonyElixir.Config.InputNormalizer
  alias SymphonyElixir.Config.Schema.StateLimits

  @default_max_retry_attempts 3

  @primary_key false
  embedded_schema do
    field(:max_concurrent_agents, :integer, default: 10)
    field(:max_turns, :integer, default: 20)
    field(:max_retry_attempts, :integer, default: @default_max_retry_attempts)
    field(:max_retry_backoff_ms, :integer, default: 300_000)
    field(:max_concurrent_agents_by_state, :map, default: %{})
  end

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(schema, attrs) do
    attrs =
      Map.update(
        attrs,
        "max_retry_attempts",
        @default_max_retry_attempts,
        &InputNormalizer.resolve_integer_setting(&1, @default_max_retry_attempts)
      )

    schema
    |> cast(
      attrs,
      [
        :max_concurrent_agents,
        :max_turns,
        :max_retry_attempts,
        :max_retry_backoff_ms,
        :max_concurrent_agents_by_state
      ],
      empty_values: []
    )
    |> validate_number(:max_concurrent_agents, greater_than: 0)
    |> validate_number(:max_turns, greater_than: 0)
    |> validate_number(:max_retry_attempts, greater_than: 0)
    |> validate_number(:max_retry_backoff_ms, greater_than: 0)
    |> update_change(:max_concurrent_agents_by_state, &StateLimits.normalize/1)
    |> StateLimits.validate(:max_concurrent_agents_by_state)
  end
end
