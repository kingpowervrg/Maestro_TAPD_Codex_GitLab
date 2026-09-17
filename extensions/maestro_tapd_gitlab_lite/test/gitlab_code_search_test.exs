defmodule MaestroTapdGitlabLite.Repo.GitlabCodeSearchTest do
  use ExUnit.Case, async: true

  alias MaestroTapdGitlabLite.Repo.GitlabCodeSearch

  @token "secret-token-never-serialize"

  test "normalizes and path-filters blob search without returning the token" do
    request_fun = fn request ->
      assert request.url == "https://gitlab.example.test/api/v4/projects/acme%2Fwidgets/search"
      assert {"private-token", @token} in request.headers

      {:ok,
       %{
         status: 200,
         body: [
           %{"path" => "lib/ok.ex", "filename" => "ok.ex", "data" => "needle", "startline" => 3},
           %{"path" => "docs/no.md", "filename" => "no.md", "data" => "needle"}
         ]
       }}
    end

    assert {:ok, result} =
             GitlabCodeSearch.search(repo(),
               query: "needle",
               path: "lib",
               token: @token,
               request_fun: request_fun
             )

    assert result["count"] == 1
    assert get_in(result, ["matches", Access.at(0), "path"]) == "lib/ok.ex"
    refute inspect(result) =~ @token
  end

  test "rejects unsafe repository paths before making a request" do
    assert {:error, {:invalid_arguments, _message}} =
             GitlabCodeSearch.search(repo(), query: "needle", path: "../secret", token: @token)
  end

  defp repo do
    %{
      remote: %{url: "git@gitlab.example.test:acme/widgets.git"},
      provider: %{
        kind: "git",
        repository: "acme/widgets",
        options: %{remote_code_search: "gitlab"}
      }
    }
  end
end
