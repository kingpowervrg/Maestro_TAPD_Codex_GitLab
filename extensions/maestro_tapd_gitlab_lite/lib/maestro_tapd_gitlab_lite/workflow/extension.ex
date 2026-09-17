defmodule MaestroTapdGitlabLite.Workflow.Extension do
  @moduledoc "Workflow registration and static contributions owned by the Lite package."

  @behaviour SymphonyElixir.Workflow.Extension
  @behaviour SymphonyElixir.Workflow.Extension.ContributionCallbacks

  alias MaestroTapdGitlabLite.Manifest
  alias MaestroTapdGitlabLite.Tracker.PolicyConfig
  alias MaestroTapdGitlabLite.Workflow.{CapabilityGate, TemplateCatalog}

  def id, do: Manifest.id()

  @spec version() :: String.t()
  def version, do: Manifest.version()

  def validate_settings(settings, _profile_context) do
    with :ok <- PolicyConfig.validate(settings),
         :ok <- CapabilityGate.validate(settings) do
      :ok
    end
  end

  def template_entries, do: TemplateCatalog.entries()

  def required_dynamic_tool_capabilities(settings),
    do: CapabilityGate.required_capabilities(settings)

  def run_poll_cycle(_context, _opts) do
    SymphonyElixir.Workflow.Extension.Runtime.Result.replace_extension_state(%{})
  end
end
