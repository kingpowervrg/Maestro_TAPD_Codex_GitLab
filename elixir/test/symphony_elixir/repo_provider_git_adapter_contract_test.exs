defmodule SymphonyElixir.RepoProviderGitAdapterContractTest do
  use ExUnit.Case, async: true

  use SymphonyElixir.RepoProviderAdapterContract,
    adapter: SymphonyElixir.RepoProvider.Git.Adapter,
    config: %{
      path: "repo",
      base_branch: "main",
      remote: %{name: "origin", url: "git@example.test:acme/widgets.git"},
      provider: %{kind: "git"}
    }

  test "Core Git adapter declares no provider HTTP capabilities" do
    repo = adapter_contract_config()

    assert [] == SymphonyElixir.RepoProvider.Git.Adapter.capabilities()
    assert [] == SymphonyElixir.RepoProvider.dynamic_tools(repo)
    assert :ok == SymphonyElixir.RepoProvider.validate_config(repo)
  end

  test "Lite assembly replaces Git with a read-only search backend" do
    repo = put_in(adapter_contract_config(), [:provider, :options], %{remote_code_search: "gitlab"})

    assert SymphonyElixir.RepoProvider.adapter(repo) ==
             MaestroTapdGitlabLite.Repo.GitlabLiteBackend

    assert [:code_search] == SymphonyElixir.RepoProvider.capabilities(repo)
    assert ["repo_remote_search"] == Enum.map(SymphonyElixir.RepoProvider.dynamic_tools(repo), & &1["name"])
  end
end
