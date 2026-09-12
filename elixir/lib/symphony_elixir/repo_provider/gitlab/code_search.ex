defmodule SymphonyElixir.RepoProvider.GitLab.CodeSearch do
  @moduledoc false

  alias SymphonyElixir.RepoProvider.Config, as: RepoConfig

  @token_env "GITLAB_API_TOKEN"
  @default_limit 20
  @max_limit 100
  @snippet_limit 2_000
  @default_timeout_seconds 60

  @spec enabled?(RepoConfig.t() | map()) :: boolean()
  def enabled?(repo) do
    repo
    |> RepoConfig.option("remote_code_search")
    |> normalize_string()
    |> case do
      "gitlab" -> true
      _other -> false
    end
  end

  @spec search(RepoConfig.t() | map(), keyword()) :: {:ok, map()} | {:error, term()}
  def search(repo, opts) when is_map(repo) and is_list(opts) do
    with :ok <- validate_enabled(repo),
         {:ok, query} <- required_option(opts, :query),
         {:ok, token} <- access_token(opts),
         {:ok, api_base_url} <- api_base_url(repo),
         {:ok, project} <- project(repo),
         {:ok, limit} <- result_limit(opts),
         {:ok, path} <- path_prefix(opts),
         {:ok, response} <- request(repo, api_base_url, project, query, token, limit, opts),
         {:ok, matches} <- decode_response(response) do
      ref = opts |> Keyword.get(:ref) |> normalize_string()

      filtered_matches =
        matches
        |> Enum.map(&normalize_match(&1, ref))
        |> Enum.reject(&is_nil/1)
        |> filter_path(path)
        |> Enum.take(limit)

      {:ok,
       %{
         "project" => project,
         "query" => query,
         "ref" => ref,
         "path" => path,
         "count" => length(filtered_matches),
         "matches" => filtered_matches
       }}
    end
  end

  def search(_repo, _opts), do: {:error, :invalid_gitlab_code_search_invocation}

  @spec token_env() :: String.t()
  def token_env, do: @token_env

  defp validate_enabled(repo) do
    if enabled?(repo), do: :ok, else: {:error, :gitlab_code_search_not_configured}
  end

  defp access_token(opts) do
    case opts |> Keyword.get(:token, System.get_env(@token_env)) |> normalize_string() do
      token when is_binary(token) -> {:ok, token}
      nil -> {:error, :missing_gitlab_api_token}
    end
  end

  defp api_base_url(repo) do
    configured =
      RepoConfig.option(repo, "gitlab_api_base_url") ||
        System.get_env("GITLAB_API_BASE_URL")

    case normalize_string(configured) || infer_api_base_url(RepoConfig.remote_url(repo)) do
      value when is_binary(value) -> {:ok, String.trim_trailing(value, "/")}
      nil -> {:error, :missing_gitlab_api_base_url}
    end
  end

  defp project(repo) do
    configured =
      RepoConfig.option(repo, "gitlab_project_id") ||
        System.get_env("GITLAB_PROJECT_ID") ||
        RepoConfig.repository(repo)

    case normalize_string(configured) do
      value when is_binary(value) -> {:ok, value}
      nil -> {:error, :missing_gitlab_project_id}
    end
  end

  defp required_option(opts, key) do
    case opts |> Keyword.get(key) |> normalize_string() do
      value when is_binary(value) -> {:ok, value}
      nil -> {:error, {:invalid_arguments, "GitLab code search requires #{key}."}}
    end
  end

  defp result_limit(opts) do
    case Keyword.get(opts, :max_results, @default_limit) do
      value when is_integer(value) and value in 1..@max_limit -> {:ok, value}
      _value -> {:error, {:invalid_arguments, "max_results must be an integer from 1 to #{@max_limit}."}}
    end
  end

  defp request(repo, api_base_url, project, query, token, limit, opts) do
    url =
      api_base_url <>
        "/projects/" <>
        URI.encode(project, &URI.char_unreserved?/1) <>
        "/search"

    params =
      %{
        "scope" => "blobs",
        "search" => query,
        "ref" => opts |> Keyword.get(:ref) |> normalize_string(),
        "per_page" => request_page_size(opts, limit),
        "page" => 1
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    request = %{
      method: "GET",
      url: url,
      params: params,
      headers: [{"private-token", token}, {"accept", "application/json"}],
      timeout_ms: timeout_ms(repo)
    }

    request_fun = Keyword.get(opts, :request_fun, &default_request/1)

    case request_fun.(request) do
      {:ok, response} when is_map(response) -> {:ok, response}
      {:error, reason} -> {:error, {:gitlab_code_search_request_failed, safe_diagnostic(reason)}}
      other -> {:error, {:gitlab_code_search_invalid_response, safe_diagnostic(other)}}
    end
  end

  defp default_request(request) do
    Req.get(request.url,
      params: request.params,
      headers: request.headers,
      retry: false,
      receive_timeout: request.timeout_ms,
      connect_options: [timeout: request.timeout_ms]
    )
    |> case do
      {:ok, %Req.Response{status: status, body: body, headers: headers}} ->
        {:ok, %{status: status, body: body, headers: headers}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp decode_response(%{status: 200, body: body}) when is_list(body), do: {:ok, body}

  defp decode_response(%{status: status}) when status in [401, 403],
    do: {:error, :gitlab_code_search_auth_failed}

  defp decode_response(%{status: 404}), do: {:error, :gitlab_code_search_project_not_found}

  defp decode_response(%{status: status}) when is_integer(status),
    do: {:error, {:gitlab_code_search_status, status}}

  defp decode_response(response),
    do: {:error, {:gitlab_code_search_invalid_response, safe_diagnostic(response)}}

  defp normalize_match(match, requested_ref) when is_map(match) do
    path = map_value(match, "path") |> normalize_string()

    if is_binary(path) do
      %{
        "path" => path,
        "filename" => map_value(match, "filename") |> normalize_string(),
        "startline" => normalize_integer(map_value(match, "startline")),
        "snippet" => match |> map_value("data") |> normalize_snippet(),
        "ref" => map_value(match, "ref") |> normalize_string() || requested_ref
      }
    end
  end

  defp normalize_match(_match, _requested_ref), do: nil

  defp filter_path(matches, nil), do: matches

  defp filter_path(matches, path) do
    prefix = String.trim_trailing(path, "/") <> "/"
    Enum.filter(matches, &(&1["path"] == path or String.starts_with?(&1["path"], prefix)))
  end

  defp normalize_path_prefix(value) do
    case normalize_string(value) do
      nil -> nil
      path -> path |> String.trim_trailing("/") |> blank_to_nil()
    end
  end

  defp path_prefix(opts) do
    case opts |> Keyword.get(:path) |> normalize_path_prefix() do
      nil ->
        {:ok, nil}

      path ->
        segments = String.split(path, "/", trim: false)

        if Path.type(path) == :relative and
             not String.contains?(path, ["\\", "\0", "\n", "\r"]) and
             Enum.all?(segments, &(&1 not in ["", ".", ".."])) do
          {:ok, path}
        else
          {:error, {:invalid_arguments, "path must be a safe repository-relative prefix."}}
        end
    end
  end

  defp request_page_size(opts, limit) do
    if opts |> Keyword.get(:path) |> normalize_path_prefix(), do: @max_limit, else: limit
  end

  defp infer_api_base_url(remote_url) when is_binary(remote_url) do
    uri = URI.parse(String.trim(remote_url))

    cond do
      uri.scheme in ["http", "https"] and is_binary(uri.host) ->
        authority = if uri.port && uri.port not in [80, 443], do: "#{uri.host}:#{uri.port}", else: uri.host
        "#{uri.scheme}://#{authority}/api/v4"

      uri.scheme in ["ssh", "git"] and is_binary(uri.host) ->
        "https://#{uri.host}/api/v4"

      true ->
        infer_scp_api_base_url(remote_url)
    end
  rescue
    _error -> nil
  end

  defp infer_api_base_url(_remote_url), do: nil

  defp infer_scp_api_base_url(remote_url) do
    case Regex.run(~r/^[^@\s]+@(?<host>[^:\s]+):.+$/u, remote_url, capture: :all_names) do
      [host] -> "https://#{host}/api/v4"
      _other -> nil
    end
  end

  defp timeout_ms(repo) do
    repo
    |> RepoConfig.runtime_http_timeout_seconds()
    |> parse_positive_integer(@default_timeout_seconds)
    |> Kernel.*(1_000)
  end

  defp parse_positive_integer(value, default) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {integer, ""} when integer > 0 -> integer
      _other -> default
    end
  end

  defp parse_positive_integer(_value, default), do: default

  defp normalize_integer(value) when is_integer(value), do: value

  defp normalize_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _other -> nil
    end
  end

  defp normalize_integer(_value), do: nil

  defp normalize_snippet(value) when is_binary(value), do: String.slice(value, 0, @snippet_limit)
  defp normalize_snippet(_value), do: nil

  defp normalize_string(value) when is_binary(value) do
    value |> String.trim() |> blank_to_nil()
  end

  defp normalize_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_string(_value), do: nil

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp map_value(map, key) when is_map(map) do
    Map.get(map, key) || map_get_existing_atom(map, key)
  end

  defp map_get_existing_atom(map, key) do
    Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> nil
  end

  defp safe_diagnostic(%{__struct__: module}) when is_atom(module), do: inspect(module)
  defp safe_diagnostic(value) when is_atom(value), do: Atom.to_string(value)
  defp safe_diagnostic(value) when is_binary(value), do: "string(#{byte_size(value)} bytes)"
  defp safe_diagnostic(value) when is_map(value), do: "map(#{map_size(value)} keys)"
  defp safe_diagnostic(value) when is_list(value), do: "list(#{length(value)} items)"
  defp safe_diagnostic(_value), do: "unknown"
end
