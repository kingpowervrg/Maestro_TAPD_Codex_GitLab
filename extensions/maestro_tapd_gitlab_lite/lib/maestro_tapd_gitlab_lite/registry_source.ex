defmodule MaestroTapdGitlabLite.RegistrySource do
  @moduledoc "Application-assembly source for the Lite workflow extension."

  @behaviour SymphonyElixir.Workflow.Extension.Registry.Source

  def extension_modules(_opts), do: [MaestroTapdGitlabLite.Workflow.Extension]
end
