defmodule MaestroTapdGitlabLite.Repo.GitlabLiteBackend do
  @moduledoc "Replaceable Git-only backend with local-first code search."

  @behaviour SymphonyElixir.RepoProvider.Adapter

  alias MaestroTapdGitlabLite.Repo.GitlabCodeSearch
  alias MaestroTapdGitlabLite.Repo.LocalCodeSearch

  def kind, do: "git"

  def defaults, do: %{}

  def validate_config(_repo), do: :ok

  def capabilities, do: [:code_search]

  def code_search(repo, opts) do
    if GitlabCodeSearch.enabled?(repo),
      do: GitlabCodeSearch.search(repo, opts),
      else: LocalCodeSearch.search(repo, opts)
  end

  def dynamic_tool_enabled?(repo, "repo_remote_search"),
    do: GitlabCodeSearch.enabled?(repo) or LocalCodeSearch.enabled?(repo)

  def dynamic_tool_enabled?(_repo, _tool), do: true
end
