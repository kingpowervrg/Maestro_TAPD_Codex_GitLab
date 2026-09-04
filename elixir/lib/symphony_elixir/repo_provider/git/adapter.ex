defmodule SymphonyElixir.RepoProvider.Git.Adapter do
  @moduledoc """
  Git-only repo-provider adapter.

  This adapter exists so workflows backed by a plain Git remote can pass
  repo-provider configuration validation without pretending that the remote
  supports change proposals, reviews, checks, merges, or a hosting API.
  Repository checkout, diff, commit, and push operations remain owned by
  `SymphonyElixir.Repo`.
  """

  @behaviour SymphonyElixir.RepoProvider.Adapter

  alias SymphonyElixir.RepoProvider.ConfigValidator
  alias SymphonyElixir.RepoProvider.Kinds

  @provider_kind Kinds.git()

  @impl true
  def kind, do: @provider_kind

  @impl true
  def defaults, do: %{}

  @impl true
  def validate_config(repo), do: ConfigValidator.validate(repo, __MODULE__)

  @impl true
  def capabilities, do: []
end
