defmodule SymphonyElixir.RepoProvider.Git.Adapter do
  @moduledoc """
  Git-remote repo-provider adapter.

  This adapter exists so workflows backed by a plain Git remote can pass
  repo-provider configuration validation without pretending that the remote
  supports change proposals, reviews, checks, or merges. It optionally exposes
  read-only GitLab code search when a workflow opts into that narrow API.
  Repository checkout, diff, commit, and push operations remain owned by
  `SymphonyElixir.Repo`.
  """

  @behaviour SymphonyElixir.RepoProvider.Adapter

  alias SymphonyElixir.RepoProvider.ConfigValidator
  alias SymphonyElixir.RepoProvider.GitLab.CodeSearch
  alias SymphonyElixir.RepoProvider.Kinds

  @provider_kind Kinds.git()

  @impl true
  def kind, do: @provider_kind

  @impl true
  def defaults, do: %{}

  @impl true
  def validate_config(repo), do: ConfigValidator.validate(repo, __MODULE__)

  @impl true
  def capabilities, do: [:code_search]

  @impl true
  def code_search(repo, opts), do: CodeSearch.search(repo, opts)
end
