defmodule MaestroTapdGitlabLite.Repo.LocalCodeSearchTest do
  use ExUnit.Case, async: true

  alias MaestroTapdGitlabLite.Repo.{GitlabCodeSearch, GitlabLiteBackend, LocalCodeSearch}

  test "searches and refreshes a requested branch without switching the reference worktree" do
    root = tmp_dir!()
    remote = Path.join(root, "remote.git")
    reference = Path.join(root, "reference")
    writer = Path.join(root, "writer")

    run!("git", ["init", "--bare", "--initial-branch", "master", remote])
    clone!(remote, reference)
    clone!(remote, writer)
    File.mkdir_p!(Path.join(reference, "Game/Assets/_Script"))

    File.write!(
      Path.join(reference, "Game/Assets/_Script/UnitGroup.cs"),
      "master GetUnitDicInfo();\n"
    )

    commit_and_push!(reference, "master")
    run!("git", ["-C", reference, "switch", "-c", "v25.4.0/firebase"])

    File.write!(
      Path.join(reference, "Game/Assets/_Script/UnitGroup.cs"),
      "old GetUnitDicInfo();\n"
    )

    commit_and_push!(reference, "old firebase")
    stale_sha = String.trim(run!("git", ["-C", reference, "rev-parse", "HEAD"]))
    run!("git", ["-C", reference, "switch", "master"])
    File.write!(Path.join(reference, "local-dirty.txt"), "preserve me\n")
    master_head = String.trim(run!("git", ["-C", reference, "rev-parse", "HEAD"]))

    run!("git", ["-C", writer, "fetch", "origin", "v25.4.0/firebase"])
    run!("git", ["-C", writer, "switch", "-c", "v25.4.0/firebase", "origin/v25.4.0/firebase"])

    File.write!(
      Path.join(writer, "Game/Assets/_Script/UnitGroup.cs"),
      "foo:12:bar GetUnitDicInfo();\n-GetUnitDicInfo();\n"
    )

    commit_and_push!(writer, "current firebase")
    current_sha = String.trim(run!("git", ["-C", writer, "rev-parse", "HEAD"]))

    repo = repo(reference, remote)
    request_fun = fn _request -> flunk("local search must not call GitLab") end

    assert {:ok, result} =
             LocalCodeSearch.search(repo,
               query: "GetUnitDicInfo",
               ref: "v25.4.0/firebase",
               path: "Game/Assets/_Script",
               max_results: 1,
               request_fun: request_fun
             )

    assert result["backend"] == "local_reference"
    assert result["searched_sha"] == current_sha
    assert result["searched_sha"] != stale_sha
    assert result["truncated"]
    assert result["count"] == 1
    assert get_in(result, ["matches", Access.at(0), "snippet"]) == "foo:12:bar GetUnitDicInfo();"
    assert String.trim(run!("git", ["-C", reference, "branch", "--show-current"])) == "master"
    assert String.trim(run!("git", ["-C", reference, "rev-parse", "HEAD"])) == master_head
    assert File.read!(Path.join(reference, "local-dirty.txt")) == "preserve me\n"

    local_repo = put_in(repo, [:provider, :options, :remote_blob_search_enabled], false)
    assert GitlabLiteBackend.dynamic_tool_enabled?(local_repo, "repo_remote_search")

    assert {:ok, %{"backend" => "local_reference", "searched_sha" => ^current_sha, "count" => 1}} =
             GitlabLiteBackend.code_search(local_repo,
               query: "-GetUnitDicInfo",
               ref: "v25.4.0/firebase",
               request_fun: request_fun
             )

    assert {:error, :gitlab_code_search_not_configured} =
             GitlabCodeSearch.search(local_repo, query: "needle", request_fun: request_fun)

    refute GitlabCodeSearch.enabled?(local_repo)
  end

  test "rejects a missing local reference and unsafe paths" do
    assert {:error, :local_search_reference_not_found} =
             LocalCodeSearch.search(repo("/missing/reference", "unused"),
               query: "needle",
               ref: "master"
             )

    root = tmp_dir!()
    File.mkdir_p!(Path.join(root, ".git"))

    assert {:error, {:invalid_arguments, _}} =
             LocalCodeSearch.search(repo(root, "unused"),
               query: "needle",
               ref: "master",
               path: "../secret"
             )
  end

  test "searches with read-only helpers as extracted from the escript archive" do
    root = tmp_dir!()
    remote = Path.join(root, "remote.git")
    reference = Path.join(root, "reference")
    run!("git", ["init", "--bare", "--initial-branch", "master", remote])
    clone!(remote, reference)
    File.write!(Path.join(reference, "UnitGroup.cs"), "GetUnitDicInfo();\n")
    commit_and_push!(reference, "search fixture")

    source_bin =
      :maestro_tapd_gitlab_lite
      |> :code.priv_dir()
      |> to_string()
      |> Path.join("workspace_automation/bin")

    extracted_bin = Path.join(root, "extracted/bin")
    File.mkdir_p!(extracted_bin)

    for filename <- ["repo-local-search", "repo-full-checkout"] do
      destination = Path.join(extracted_bin, filename)
      File.cp!(Path.join(source_bin, filename), destination)
      File.chmod!(destination, 0o644)
    end

    helper = Path.join(extracted_bin, "repo-local-search")
    {output, status} = System.cmd("python3", [helper, reference, remote, "master", "GetUnitDicInfo", "", "20"])
    assert status == 0, output
    assert %{"ok" => %{"backend" => "local_reference", "count" => 1}} = :json.decode(output)
    assert Bitwise.band(File.stat!(Path.join(extracted_bin, "repo-full-checkout")).mode, 0o111) == 0
  end

  defp repo(reference, remote) do
    %{
      base_branch: "master",
      remote: %{url: remote},
      provider: %{options: %{local_search_reference: reference}}
    }
  end

  defp clone!(remote, path) do
    run!("git", ["clone", remote, path])
    run!("git", ["-C", path, "config", "user.name", "Maestro Test"])
    run!("git", ["-C", path, "config", "user.email", "maestro@example.invalid"])
  end

  defp commit_and_push!(path, message) do
    run!("git", ["-C", path, "add", "."])
    run!("git", ["-C", path, "commit", "-m", message])
    run!("git", ["-C", path, "push", "origin", "HEAD"])
  end

  defp run!(command, args) do
    case System.cmd(command, args, stderr_to_stdout: true) do
      {output, 0} -> output
      {output, status} -> flunk("#{command} failed with #{status}: #{output}")
    end
  end

  defp tmp_dir! do
    path = Path.join(System.tmp_dir!(), "local-code-search-#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)
    path
  end
end
