defmodule SymphonyElixir.RepoProvider.GitLabCodeSearchTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.RepoProvider
  alias SymphonyElixir.RepoProvider.GitLab.CodeSearch

  @token "gitlab-test-token-never-log"

  test "search infers self-managed GitLab endpoint and project from an SSH remote" do
    request_fun = fn request ->
      assert request.method == "GET"

      assert request.url ==
               "https://gitlab-ee.example.test/api/v4/projects/acme%2Fwidgets/search"

      assert request.params == %{
               "page" => 1,
               "per_page" => 100,
               "ref" => "release/24.9",
               "scope" => "blobs",
               "search" => "BattleTileType"
             }

      assert {"private-token", @token} in request.headers
      assert request.timeout_ms == 60_000

      {:ok,
       %{
         status: 200,
         body: [
           %{
             "filename" => "tile_type.lua",
             "path" => "game/battle/tile_type.lua",
             "startline" => 41,
             "data" => "local BattleTileType = {}",
             "ref" => "release/24.9"
           },
           %{
             "filename" => "docs.md",
             "path" => "docs/tile_types.md",
             "startline" => 7,
             "data" => "BattleTileType"
           }
         ],
         headers: %{}
       }}
    end

    assert {:ok,
            %{
              "count" => 1,
              "project" => "acme/widgets",
              "matches" => [
                %{
                  "path" => "game/battle/tile_type.lua",
                  "startline" => 41,
                  "snippet" => "local BattleTileType = {}"
                }
              ]
            }} =
             CodeSearch.search(gitlab_repo(),
               query: "BattleTileType",
               ref: "release/24.9",
               path: "game/battle",
               max_results: 5,
               token: @token,
               request_fun: request_fun
             )
  end

  test "typed remote search keeps the API token out of tool schemas and results" do
    repo = gitlab_repo()
    specs = RepoProvider.dynamic_tools(repo)

    assert Enum.map(specs, & &1["name"]) == ["repo_remote_search"]
    refute inspect(specs) =~ @token
    refute inspect(specs) =~ "GITLAB_API_TOKEN="

    request_fun = fn _request ->
      {:ok,
       %{
         status: 200,
         body: [
           %{
             "filename" => "world.lua",
             "path" => "game/world.lua",
             "startline" => 3,
             "data" => "WorldMap = {}"
           }
         ]
       }}
    end

    assert {:success, payload} =
             RepoProvider.execute_dynamic_tool(
               repo,
               "repo_remote_search",
               %{"query" => "WorldMap", "ref" => "master"},
               token: @token,
               request_fun: request_fun
             )

    assert get_in(payload, ["data", "matches", Access.at(0), "path"]) == "game/world.lua"
    refute inspect(payload) =~ @token
  end

  test "remote search is not advertised unless explicitly enabled" do
    repo = put_in(gitlab_repo(), [:provider, :options], %{})
    assert RepoProvider.dynamic_tools(repo) == []
  end

  test "authentication failures are structured without exposing the token" do
    request_fun = fn _request -> {:ok, %{status: 401, body: %{"message" => "401 Unauthorized"}}} end

    assert {:failure, payload} =
             RepoProvider.execute_dynamic_tool(
               gitlab_repo(),
               "repo_remote_search",
               %{"query" => "WorldMap"},
               token: @token,
               request_fun: request_fun
             )

    assert get_in(payload, ["error", "code"]) == "gitlab_code_search_auth_failed"
    refute inspect(payload) =~ @token
  end

  test "transport diagnostics never serialize request headers" do
    request_fun = fn _request ->
      {:error, %{headers: [{"private-token", @token}], reason: "connection closed"}}
    end

    assert {:failure, payload} =
             RepoProvider.execute_dynamic_tool(
               gitlab_repo(),
               "repo_remote_search",
               %{"query" => "WorldMap"},
               token: @token,
               request_fun: request_fun
             )

    assert get_in(payload, ["error", "code"]) == "gitlab_code_search_request_failed"
    refute inspect(payload) =~ @token
  end

  defp gitlab_repo do
    %{
      path: System.tmp_dir!(),
      base_branch: "master",
      remote: %{
        name: "origin",
        url: "git@gitlab-ee.example.test:acme/widgets.git"
      },
      provider: %{
        kind: "git",
        repository: "acme/widgets",
        options: %{remote_code_search: "gitlab"}
      }
    }
  end
end
