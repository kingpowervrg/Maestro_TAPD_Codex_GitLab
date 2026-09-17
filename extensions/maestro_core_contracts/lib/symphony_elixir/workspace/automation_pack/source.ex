defmodule SymphonyElixir.Workspace.AutomationPack.Source do
  @moduledoc "Provider-neutral source contract for workspace automation overlays."

  @callback source_dir(keyword()) :: Path.t()
end
