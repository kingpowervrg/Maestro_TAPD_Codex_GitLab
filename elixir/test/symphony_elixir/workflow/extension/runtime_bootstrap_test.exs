defmodule SymphonyElixir.Workflow.Extension.RuntimeBootstrapTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Workflow.Extension.RuntimeBootstrap

  @app :symphony_elixir
  @config_key :workflow_runtime_extension_apps

  setup do
    previous = Application.get_env(@app, @config_key)

    on_exit(fn ->
      if is_nil(previous), do: Application.delete_env(@app, @config_key), else: Application.put_env(@app, @config_key, previous)
    end)

    :ok
  end

  test "starts configured OTP applications" do
    Application.put_env(@app, @config_key, [:logger])

    assert :ok = RuntimeBootstrap.ensure_started()
  end

  test "rejects non-application configuration values" do
    Application.put_env(@app, @config_key, ["maestro_tapd_gitlab_lite"])

    assert {:error, {:invalid_workflow_runtime_extension_app, "maestro_tapd_gitlab_lite"}} =
             RuntimeBootstrap.ensure_started()
  end
end
