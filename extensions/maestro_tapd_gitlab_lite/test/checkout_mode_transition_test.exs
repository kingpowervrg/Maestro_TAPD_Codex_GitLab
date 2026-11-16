defmodule MaestroTapdGitlabLite.CheckoutModeTransitionTest do
  use ExUnit.Case, async: true

  @template Path.expand("../priv/workflow_templates/tapd/git/codex.md", __DIR__)
  @helper Path.expand("../priv/workspace_automation/bin/repo-full-checkout", __DIR__)
  @branch "v25.4.0/firebase"

  setup do
    root = Path.join(System.tmp_dir!(), "checkout transition #{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    remote = Path.join(root, "remote.git")
    reference = Path.join(root, "reference")
    workspace = Path.join(root, "workspace")
    repo = Path.join(workspace, "repo")
    automation = Path.join(workspace, ".codex")

    run!("git", ["init", "--bare", "--initial-branch", @branch, remote])
    run!("git", ["clone", remote, reference])
    run!("git", ["-C", reference, "config", "user.name", "Maestro Test"])
    run!("git", ["-C", reference, "config", "user.email", "maestro@example.invalid"])
    File.mkdir_p!(Path.join(reference, "Game/.agents/skills/review"))
    File.mkdir_p!(Path.join(reference, "Other"))
    File.write!(Path.join(reference, "Game/Unit.cs"), "class Unit {}\n")
    File.write!(Path.join(reference, "Game/AGENTS.md"), "# Target guidance\n")
    File.write!(Path.join(reference, "Game/.agents/skills/review/SKILL.md"), "# Review\n")
    File.write!(Path.join(reference, "Other/asset.txt"), "outside selected paths\n")
    File.write!(Path.join(reference, ".gitignore"), "local.cache\n")
    run!("git", ["-C", reference, "add", "."])
    run!("git", ["-C", reference, "commit", "-m", "Initial reference"])
    run!("git", ["-C", reference, "push", "origin", "HEAD"])

    File.mkdir_p!(Path.join(automation, "bin"))
    File.mkdir_p!(Path.join(automation, "skills"))
    File.ln_s!(@helper, Path.join(automation, "bin/repo-full-checkout"))
    run!("git", ["clone", "--depth", "1", "--filter=blob:none", "--sparse", "--branch", @branch, "file://" <> remote, repo])
    File.write!(Path.join(automation, "repo-materialization-mode"), "sparse\n")
    File.write!(Path.join(workspace, ".symphony-tapd-workpad.md"), "- published_head_sha: pending\n- suggested_mr_title: pending\n")

    {:ok, root: root, remote: remote, reference: reference, workspace: workspace, repo: repo, automation: automation}
  end

  for {mode, paths} <- [{"full", ""}, {"partial", "Game"}] do
    test "switches an existing sparse workspace to #{mode} checkout", context do
      File.write!(Path.join(context.repo, "local.cache"), "preserve ignored data\n")
      assert {output, 0} = hook(context, [{"SOURCE_REPO_PULL_PATHS", unquote(paths)}])
      assert output =~ "rematerializing the clean sparse workspace"
      assert marker(context) == unquote(mode)
      assert File.read!(Path.join(context.repo, "Game/Unit.cs")) == "class Unit {}\n"
      assert File.exists?(Path.join(context.repo, "Other/asset.txt")) == (unquote(mode) == "full")
      assert String.trim(run!("git", ["-C", context.repo, "branch", "--show-current"])) == @branch
      assert String.trim(run!("git", ["-C", context.repo, "rev-parse", "--is-shallow-repository"])) == "false"
      assert {_output, 1} = System.cmd("git", ["-C", context.repo, "config", "--get", "remote.origin.promisor"])
      assert File.read!(Path.join(context.automation, "repo-sparse-before-xhigh/local.cache")) == "preserve ignored data\n"
      assert File.read!(Path.join(context.automation, "skills/target-agents-review/SKILL.md")) == "# Review\n"
      assert File.read!(Path.join(context.workspace, "AGENTS.md")) =~ "repo/Game/AGENTS.md"
      assert {_output, 0} = hook(context, [{"SOURCE_REPO_PULL_PATHS", unquote(paths)}])
    end
  end

  test "protects untracked edits before changing modes", context do
    File.write!(Path.join(context.repo, "work.txt"), "unfinished work\n")
    assert {output, 74} = hook(context)
    assert output =~ "dirty sparse workspace"
    assert File.read!(Path.join(context.repo, "work.txt")) == "unfinished work\n"
    assert marker(context) == "sparse"
  end

  test "protects local commits even when the worktree is clean", context do
    run!("git", ["-C", context.repo, "config", "user.name", "Maestro Test"])
    run!("git", ["-C", context.repo, "config", "user.email", "maestro@example.invalid"])
    run!("git", ["-C", context.repo, "commit", "--allow-empty", "-m", "Unpublished work"])
    assert {output, 74} = hook(context)
    assert output =~ "local commits"
    assert marker(context) == "sparse"
  end

  test "preserves a published completion recovery without requiring a reference", context do
    sha = String.trim(run!("git", ["-C", context.repo, "rev-parse", "HEAD"]))
    File.write!(Path.join(context.workspace, ".symphony-tapd-workpad.md"), "- published_head_sha: #{sha}\n- suggested_mr_title: Fix duplicate units\n")
    assert {output, 0} = hook(context, [{"SOURCE_REPO_LOCAL_REFERENCE", ""}])
    assert output =~ "completion recovery"
    assert marker(context) == "sparse"
  end

  test "refreshes a stale reference before migration", context do
    reference_head = String.trim(run!("git", ["-C", context.reference, "rev-parse", "HEAD"]))
    run!("git", ["clone", context.remote, Path.join(context.root, "updater")])
    updater = Path.join(context.root, "updater")
    run!("git", ["-C", updater, "config", "user.name", "Maestro Test"])
    run!("git", ["-C", updater, "config", "user.email", "maestro@example.invalid"])
    run!("git", ["-C", updater, "commit", "--allow-empty", "-m", "New baseline"])
    run!("git", ["-C", updater, "push", "origin", "HEAD"])
    assert {output, 0} = hook(context)
    assert output =~ "rematerializing the clean sparse workspace"
    assert marker(context) == "full"

    assert String.trim(run!("git", ["-C", context.repo, "rev-parse", "HEAD"])) ==
             String.trim(run!("git", ["-C", updater, "rev-parse", "HEAD"]))

    assert String.trim(run!("git", ["-C", context.reference, "rev-parse", "HEAD"])) == reference_head
    assert File.exists?(Path.join(context.automation, "repo-sparse-before-xhigh"))
    assert String.trim(run!("git", ["-C", context.reference, "branch", "--show-current"])) == @branch
  end

  test "a missing remote branch blocks before replacing the sparse repository", context do
    assert {output, 1} = hook(context, [{"SYMPHONY_ISSUE_BRANCH_NAME", "missing/branch"}])
    assert output =~ "Unable to resolve origin/missing/branch"
    assert marker(context) == "sparse"
    refute File.exists?(Path.join(context.automation, "repo-sparse-before-xhigh"))
  end

  test "a rejected fetch blocks before replacing the sparse repository", context do
    run!("git", ["-C", context.reference, "update-ref", "-d", "refs/remotes/origin/#{@branch}"])
    run!("git", ["-C", context.reference, "branch", "-m", "master"])
    rejection_hook = Path.join(context.reference, ".git/hooks/reference-transaction")
    File.write!(rejection_hook, "#!/bin/sh\nexit 1\n")
    File.chmod!(rejection_hook, 0o755)

    assert {output, 74} = hook(context)
    assert output =~ "Unable to update the complete checkout reference"
    assert marker(context) == "sparse"
    refute File.exists?(Path.join(context.automation, "repo-sparse-before-xhigh"))
    assert String.trim(run!("git", ["-C", context.reference, "branch", "--show-current"])) == "master"
  end

  defp hook(context, overrides \\ []) do
    [_, script] = Regex.run(~r/^  before_run: \|\n(.*?)^  before_remove:/ms, File.read!(@template))
    script = Regex.replace(~r/^    /m, script, "")

    env = [
      {"SYMPHONY_AGENT_REASONING_EFFORT", "xhigh"},
      {"SYMPHONY_ISSUE_BRANCH_NAME", @branch},
      {"SYMPHONY_WORKSPACE_AUTOMATION_DIR", context.automation},
      {"SOURCE_REPO_URL", context.remote},
      {"SOURCE_REPO_LOCAL_REFERENCE", context.reference},
      {"SOURCE_REPO_PROJECT_SUBDIR", "Game"},
      {"SOURCE_REPO_PULL_PATHS", ""}
    ]

    System.cmd("bash", ["-euc", script], cd: context.workspace, env: Map.to_list(Map.merge(Map.new(env), Map.new(overrides))), stderr_to_stdout: true)
  end

  defp marker(context), do: context.automation |> Path.join("repo-materialization-mode") |> File.read!() |> String.trim()

  defp run!(command, args) do
    case System.cmd(command, args, stderr_to_stdout: true) do
      {output, 0} -> output
      {output, status} -> flunk("#{command} failed with #{status}: #{output}")
    end
  end
end
