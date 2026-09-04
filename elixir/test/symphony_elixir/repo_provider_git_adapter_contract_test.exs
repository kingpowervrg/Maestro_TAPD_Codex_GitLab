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

  test "Git-only adapter declares no provider API capabilities or typed tools" do
    repo = adapter_contract_config()

    assert [] == SymphonyElixir.RepoProvider.Git.Adapter.capabilities()
    assert [] == SymphonyElixir.RepoProvider.dynamic_tools(repo)
    assert :ok == SymphonyElixir.RepoProvider.validate_config(repo)
  end
end
