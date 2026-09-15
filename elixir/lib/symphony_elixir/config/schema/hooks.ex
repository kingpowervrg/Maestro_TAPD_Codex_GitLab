defmodule SymphonyElixir.Config.Schema.Hooks do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  alias SymphonyElixir.Config.InputNormalizer

  @default_timeout_ms 60_000

  @primary_key false
  embedded_schema do
    field(:after_create, :string)
    field(:before_run, :string)
    field(:after_run, :string)
    field(:before_remove, :string)
    field(:timeout_ms, :integer, default: @default_timeout_ms)
  end

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(schema, attrs) do
    attrs =
      Map.update(
        attrs,
        "timeout_ms",
        @default_timeout_ms,
        &InputNormalizer.resolve_integer_setting(&1, @default_timeout_ms)
      )

    schema
    |> cast(attrs, [:after_create, :before_run, :after_run, :before_remove, :timeout_ms], empty_values: [])
    |> validate_number(:timeout_ms, greater_than: 0)
  end
end
