defmodule SymphonyElixir.Workflow.Extension.RuntimeBootstrap do
  @moduledoc false

  @app :symphony_elixir
  @config_key :workflow_runtime_extension_apps

  @spec ensure_started() :: :ok | {:error, term()}
  def ensure_started do
    @app
    |> Application.get_env(@config_key, [])
    |> List.wrap()
    |> Enum.reduce_while(:ok, fn
      otp_app, :ok when is_atom(otp_app) ->
        case Application.ensure_all_started(otp_app) do
          {:ok, _started_apps} -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, {otp_app, reason}}}
        end

      value, :ok ->
        {:halt, {:error, {:invalid_workflow_runtime_extension_app, value}}}
    end)
  end
end
