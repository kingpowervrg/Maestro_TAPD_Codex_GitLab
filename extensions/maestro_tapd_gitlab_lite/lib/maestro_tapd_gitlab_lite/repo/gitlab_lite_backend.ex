defmodule MaestroTapdGitlabLite.Repo.GitlabLiteBackend do
  @moduledoc "Replaceable Git-only backend with one read-only GitLab blob-search capability."

  @behaviour SymphonyElixir.RepoProvider.Adapter

  alias MaestroTapdGitlabLite.Repo.GitlabCodeSearch

  def kind, do: "git"

  def defaults, do: %{}

  def validate_config(_repo), do: :ok

  def capabilities, do: [:code_search]

  def code_search(repo, opts), do: GitlabCodeSearch.search(repo, opts)

  def dynamic_tool_enabled?(repo, "repo_remote_search"), do: GitlabCodeSearch.enabled?(repo)
  def dynamic_tool_enabled?(_repo, _tool), do: true
end
