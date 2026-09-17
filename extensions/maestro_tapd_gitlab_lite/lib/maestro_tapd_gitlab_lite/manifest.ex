defmodule MaestroTapdGitlabLite.Manifest do
  @moduledoc "Static identity and Core compatibility metadata for the Lite extension."

  @id "maestro.extension.tapd_gitlab_lite"
  @version "0.1.0"
  @required_core_contract_version 1

  @spec id() :: String.t()
  def id, do: @id

  @spec version() :: String.t()
  def version, do: @version

  @spec required_core_contract_version() :: pos_integer()
  def required_core_contract_version, do: @required_core_contract_version

  @spec metadata() :: map()
  def metadata do
    %{
      id: id(),
      version: version(),
      required_core_contract_version: required_core_contract_version()
    }
  end
end
