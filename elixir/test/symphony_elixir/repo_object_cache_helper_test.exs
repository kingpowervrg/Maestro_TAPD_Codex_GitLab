defmodule SymphonyElixir.RepoObjectCacheHelperTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Platform.CommandEnv

  @helper Path.expand("priv/workspace_automation/bin/repo-object-cache", File.cwd!())

  test "concurrent tasks reuse one cache and clones borrow its objects" do
    root = tmp_dir!("repo-object-cache")
    source = Path.join(root, "source")
    remote = Path.join(root, "remote.git")
    cache_root = Path.join(root, "cache")
    checkout = Path.join(root, "checkout")

    File.mkdir_p!(source)
    run!("git", ["-C", source, "init", "-b", "main"])
    run!("git", ["-C", source, "config", "user.name", "Maestro Test"])
    run!("git", ["-C", source, "config", "user.email", "maestro@example.invalid"])
    File.write!(Path.join(source, "README.md"), "cached objects\n")
    run!("git", ["-C", source, "add", "README.md"])
    run!("git", ["-C", source, "commit", "-m", "Initial cache fixture"])
    run!("git", ["clone", "--bare", source, remote])
    run!("git", ["-C", remote, "config", "uploadpack.allowFilter", "true"])

    remote_url = "file://#{remote}"

    cache_paths =
      1..2
      |> Task.async_stream(
        fn _index -> prepare_cache(remote_url, cache_root) end,
        max_concurrency: 2,
        ordered: false,
        timeout: 30_000
      )
      |> Enum.map(fn {:ok, cache_path} -> cache_path end)

    assert [cache_path] = Enum.uniq(cache_paths)
    assert File.dir?(cache_path)
    assert String.trim(run!("git", ["-C", cache_path, "rev-parse", "--is-bare-repository"])) == "true"

    run!("git", [
      "clone",
      "--depth",
      "1",
      "--filter=blob:none",
      "--reference-if-able",
      cache_path,
      "--branch",
      "main",
      remote_url,
      checkout
    ])

    alternates = checkout |> Path.join(".git/objects/info/alternates") |> File.read!() |> String.trim()
    assert alternates == Path.join(cache_path, "objects")

    File.write!(Path.join(source, "README.md"), "cached objects\nupdated\n")
    run!("git", ["-C", source, "commit", "-am", "Update cache fixture"])
    run!("git", ["-C", source, "push", remote_url, "main"])

    assert prepare_cache(remote_url, cache_root) == cache_path

    source_head = run!("git", ["-C", source, "rev-parse", "HEAD"]) |> String.trim()
    cache_head = run!("git", ["-C", cache_path, "rev-parse", "refs/heads/main"]) |> String.trim()
    assert cache_head == source_head
  end

  defp prepare_cache(remote_url, cache_root) do
    case CommandEnv.system_cmd(@helper, ["prepare", remote_url, cache_root], stderr_to_stdout: true) do
      {output, 0} -> output |> String.split("\n", trim: true) |> List.last()
      {output, status} -> flunk("cache prepare failed with #{status}: #{output}")
    end
  end

  defp run!(command, args) do
    case CommandEnv.system_cmd(command, args, stderr_to_stdout: true) do
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
