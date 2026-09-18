defmodule MaestroTapdGitlabLite.RepoBootstrap.FullCheckoutTest do
  use ExUnit.Case, async: true

  @helper Path.expand("../priv/workspace_automation/bin/repo-full-checkout", __DIR__)

  test "accepts a complete local checkout whose origin matches the target repository" do
    root = tmp_dir!("full-checkout-reference")
    remote = Path.join(root, "remote.git")
    reference = Path.join(root, "reference")

    run!("git", ["init", "--bare", remote])
    run!("git", ["clone", remote, reference])
    run!("git", ["-C", reference, "config", "user.name", "Maestro Test"])
    run!("git", ["-C", reference, "config", "user.email", "maestro@example.invalid"])
    File.write!(Path.join(reference, "README.md"), "complete reference\n")
    run!("git", ["-C", reference, "add", "README.md"])
    run!("git", ["-C", reference, "commit", "-m", "Initial reference"])
    run!("git", ["-C", reference, "push", "origin", "HEAD:master"])

    output = run!(@helper, ["validate-reference", reference, remote])

    assert String.trim(output) == Path.expand(reference)
  end

  test "rejects partial local references" do
    root = tmp_dir!("partial-checkout-reference")
    reference = Path.join(root, "reference")

    run!("git", ["init", "-b", "master", reference])
    run!("git", ["-C", reference, "remote", "add", "origin", "ssh://git.example.invalid/acme/repo.git"])
    run!("git", ["-C", reference, "config", "remote.origin.promisor", "true"])

    assert {output, 74} =
             System.cmd(
               @helper,
               ["validate-reference", reference, "ssh://git.example.invalid/acme/repo.git"],
               stderr_to_stdout: true
             )

    assert output =~ "must not be a promisor clone"
  end

  test "materializes locally first, fetches the remote delta, and checks out the requested branch" do
    root = tmp_dir!("full-checkout-development-branch")
    remote = Path.join(root, "remote.git")
    seed = Path.join(root, "seed")
    reference = Path.join(root, "master-reference")
    task_checkout = Path.join(root, "task-checkout")

    run!("git", ["init", "--bare", remote])
    run!("git", ["clone", remote, seed])
    run!("git", ["-C", seed, "config", "user.name", "Maestro Test"])
    run!("git", ["-C", seed, "config", "user.email", "maestro@example.invalid"])
    File.write!(Path.join(seed, "shared.txt"), "master content\n")
    run!("git", ["-C", seed, "add", "shared.txt"])
    run!("git", ["-C", seed, "commit", "-m", "Master content"])
    run!("git", ["-C", seed, "push", "origin", "HEAD:master"])
    run!("git", ["clone", "--branch", "master", remote, reference])

    run!("git", ["-C", seed, "switch", "-c", "v22.0/god"])
    File.write!(Path.join(seed, "branch.txt"), "development content\n")
    run!("git", ["-C", seed, "add", "branch.txt"])
    run!("git", ["-C", seed, "commit", "-m", "Development branch content"])
    run!("git", ["-C", seed, "push", "origin", "v22.0/god"])

    run!(@helper, ["materialize", reference, remote, "task-checkout", "v22.0/god"], cd: root)

    assert String.trim(run!("git", ["-C", task_checkout, "branch", "--show-current"])) == "v22.0/god"
    assert File.read!(Path.join(task_checkout, "shared.txt")) == "master content\n"
    assert File.read!(Path.join(task_checkout, "branch.txt")) == "development content\n"

    alternates =
      task_checkout
      |> Path.join(".git/objects/info/alternates")
      |> File.read!()
      |> String.trim()

    assert alternates == Path.join([reference, ".git", "objects"])
    assert String.trim(run!("git", ["-C", task_checkout, "remote", "get-url", "origin"])) == remote
    assert String.trim(run!("git", ["-C", task_checkout, "rev-parse", "--is-shallow-repository"])) == "false"
    refute File.exists?(Path.join(task_checkout, ".git/shallow"))
  end

  test "rejects unsafe task checkout targets and invalid branches" do
    root = tmp_dir!("full-checkout-invalid-target")
    reference = Path.join(root, "reference")

    run!("git", ["init", "-b", "master", reference])

    assert {_output, 64} =
             System.cmd(@helper, ["materialize", reference, "unused", "../repo", "master"],
               stderr_to_stdout: true
             )

    assert {_output, 64} =
             System.cmd(@helper, ["materialize", reference, "unused", "repo", "bad..branch"],
               stderr_to_stdout: true
             )
  end

  test "installs target guidance and repository-owned skills before Codex starts" do
    root = tmp_dir!("full-checkout-agent-context")
    workspace = Path.join(root, "workspace")
    project = Path.join([workspace, "repo", "Game"])

    File.mkdir_p!(Path.join([workspace, ".codex", "skills"]))
    File.mkdir_p!(Path.join([project, ".codex", "skills", "ui-review"]))
    File.mkdir_p!(Path.join([project, ".agents", "skills", "unity-standards"]))
    File.write!(Path.join(project, "AGENTS.md"), "# Game rules\n")
    File.write!(Path.join([project, ".codex", "skills", "ui-review", "SKILL.md"]), "# UI review\n")
    File.write!(Path.join([project, ".agents", "skills", "unity-standards", "SKILL.md"]), "# Unity standards\n")

    run!(@helper, ["install-agent-context", project, workspace])

    guidance = File.read!(Path.join(workspace, "AGENTS.md"))
    assert guidance =~ "repo/Game/AGENTS.md"
    assert guidance =~ "repo/Game/.codex/rules/AGENTS.md"

    assert File.read!(Path.join([workspace, ".codex", "skills", "target-codex-ui-review", "SKILL.md"])) ==
             "# UI review\n"

    assert File.read!(Path.join([workspace, ".codex", "skills", "target-agents-unity-standards", "SKILL.md"])) == "# Unity standards\n"
  end

  defp run!(command, args, opts \\ []) do
    case System.cmd(command, args, Keyword.put(opts, :stderr_to_stdout, true)) do
      {output, 0} -> output
      {output, status} -> flunk("#{command} failed with #{status}: #{output}")
    end
  end

  defp tmp_dir!(name) do
    path = Path.join(System.tmp_dir!(), "#{name}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)
    path
  end
end
