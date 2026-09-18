defmodule SymphonyElixir.ExtensionIsolationTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.RepoProvider
  alias SymphonyElixir.Tracker.IssuePolicy.{Registry, Runtime}
  alias SymphonyElixir.Workflow.Template

  defmodule NeutralPolicy do
    @behaviour SymphonyElixir.Tracker.IssuePolicy

    @impl true
    def id, do: "symphony.test.neutral_policy"

    @impl true
    def supports?(%{kind: "memory"}), do: true
    def supports?(_tracker), do: false

    @impl true
    def enrich_issue(issue, _context), do: {:ok, Map.put(issue, :priority, 7)}

    @impl true
    def evaluate_dispatch(%{title: "blocked"}, _context), do: {:deny, :test_blocked}
    def evaluate_dispatch(_issue, _context), do: :allow

    @impl true
    def complete(context), do: {:ok, Map.fetch!(context, :result)}

    @impl true
    def handle_failure(_context), do: :ok
  end

  setup do
    keys = [
      :workflow_runtime_extensions,
      :repo_provider_adapters,
      :issue_policies,
      :workspace_automation_sources
    ]

    previous = Map.new(keys, &{&1, Application.get_env(:symphony_elixir, &1)})

    on_exit(fn ->
      Enum.each(previous, fn
        {key, nil} -> Application.delete_env(:symphony_elixir, key)
        {key, value} -> Application.put_env(:symphony_elixir, key, value)
      end)
    end)

    :ok
  end

  test "a neutral fake policy exercises all four lifecycle callbacks" do
    Application.put_env(:symphony_elixir, :issue_policies, [NeutralPolicy])
    tracker = %{kind: "memory"}
    issue = %SymphonyElixir.Issue{id: "1", identifier: "M-1", title: "ready", state: "todo"}

    assert Registry.matching(tracker) == [NeutralPolicy]
    assert {:ok, %{priority: 7} = enriched} = Runtime.enrich_issue(issue, tracker)
    assert Runtime.evaluate_dispatch(enriched, tracker) == :allow
    assert Runtime.complete(tracker, %{result: :done}) == {:ok, :done}
    assert Runtime.handle_failure(tracker, %{}) == :ok
  end

  test "Mode C disables the package and keeps Core Git/TAPD independent" do
    Application.put_env(:symphony_elixir, :workflow_runtime_extensions, sources: [SymphonyElixir.AssemblyCatalog.WorkflowExtensions])

    Application.put_env(:symphony_elixir, :repo_provider_adapters, %{})
    Application.put_env(:symphony_elixir, :issue_policies, [])
    Application.put_env(:symphony_elixir, :workspace_automation_sources, [])

    repo = %{provider: %{kind: "git", options: %{remote_code_search: "gitlab"}}}

    assert RepoProvider.adapter(repo) == SymphonyElixir.RepoProvider.Git.Adapter
    assert RepoProvider.dynamic_tools(repo) == []
    assert Registry.policies() == []
    assert Template.fetch("tapd/git/codex") == :error
  end

  test "enabled package contributes template, backend, policy, and automation overlay" do
    assert {:ok, entry} = Template.fetch("tapd/git/codex")
    assert String.contains?(entry.asset_path, "maestro_tapd_gitlab_lite")

    assert RepoProvider.adapter(%{provider: %{kind: "git"}}) ==
             MaestroTapdGitlabLite.Repo.GitlabLiteBackend

    assert MaestroTapdGitlabLite.Tracker.CompanyTapdIssuePolicy in Registry.policies()

    assert {:ok, automation_dir} = SymphonyElixir.Workspace.AutomationPack.bundled_source_dir()
    assert File.regular?(Path.join([automation_dir, "bin", "repo-object-cache"]))
    assert File.regular?(Path.join([automation_dir, "bin", "repo-full-checkout"]))
  end

  test "project agent guidance routes Lite work to the extension boundary" do
    project_guidance = File.read!(Path.expand("../AGENTS.md", File.cwd!()))

    extension_guidance =
      File.read!(
        Path.expand(
          "../extensions/maestro_tapd_gitlab_lite/AGENTS.md",
          File.cwd!()
        )
      )

    assert project_guidance =~ "extensions/maestro_tapd_gitlab_lite/AGENTS.md"
    assert project_guidance =~ "Do not add Lite-specific"
    assert extension_guidance =~ "belong here"
    assert extension_guidance =~ "Mode A"
    assert extension_guidance =~ "Mode B"
    assert extension_guidance =~ "Mode C"
  end
end
