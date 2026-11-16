defmodule MaestroTapdGitlabLite.Repo.LocalCodeSearch do
  @moduledoc "Search synchronized branch objects without switching the reference worktree."

  @spec enabled?(map()) :: boolean()
  def enabled?(repo), do: is_binary(normalize_string(reference(repo)))

  @spec search(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def search(repo, opts) when is_map(repo) and is_list(opts) do
    with {:ok, query} <- required_string(Keyword.get(opts, :query), "query"),
         {:ok, ref} <-
           required_string(Keyword.get(opts, :ref) || field(repo, :base_branch), "ref"),
         {:ok, limit} <- result_limit(opts),
         {:ok, path} <- path_prefix(opts),
         {:ok, reference} <- reference_path(repo),
         {:ok, remote} <- required_string(repo |> field(:remote) |> field(:url), "remote URL") do
      run_search([reference, remote, ref, query, path || "", Integer.to_string(limit)])
    end
  end

  def search(_repo, _opts), do: {:error, :invalid_local_code_search_invocation}

  defp run_search(args) do
    helper =
      :maestro_tapd_gitlab_lite
      |> :code.priv_dir()
      |> to_string()
      |> Path.join("workspace_automation/bin/repo-local-search")

    {output, _status} = System.cmd("python3", [helper | args])

    case :json.decode(output) do
      %{"ok" => result} when is_map(result) -> {:ok, result}
      %{"error" => reason} -> {:error, {:local_code_search_failed, reason}}
      _other -> {:error, :local_code_search_invalid_response}
    end
  rescue
    _error -> {:error, :local_code_search_unavailable}
  end

  defp reference_path(repo) do
    case normalize_string(reference(repo)) do
      reference when is_binary(reference) ->
        if Path.type(reference) == :absolute and File.dir?(reference),
          do: {:ok, reference},
          else: {:error, :local_search_reference_not_found}

      nil ->
        {:error, :local_search_reference_not_configured}
    end
  end

  defp result_limit(opts) do
    case Keyword.get(opts, :max_results, 20) do
      value when is_integer(value) and value in 1..100 -> {:ok, value}
      _value -> {:error, {:invalid_arguments, "max_results must be an integer from 1 to 100."}}
    end
  end

  defp path_prefix(opts) do
    case normalize_string(Keyword.get(opts, :path)) do
      nil ->
        {:ok, nil}

      path ->
        path = String.trim_trailing(path, "/")

        if Path.type(path) == :relative and not String.contains?(path, ["\\", "\0", "\n", "\r"]) and
             Enum.all?(String.split(path, "/"), &(&1 not in ["", ".", ".."])) do
          {:ok, path}
        else
          {:error, {:invalid_arguments, "path must be a safe repository-relative prefix."}}
        end
    end
  end

  defp required_string(value, label) do
    case normalize_string(value) do
      nil ->
        {:error, {:invalid_arguments, "local code search requires #{label}."}}

      value ->
        if String.contains?(value, ["\0", "\n", "\r"]),
          do: {:error, {:invalid_arguments, "#{label} must be a single line."}},
          else: {:ok, value}
    end
  end

  defp reference(repo),
    do: repo |> field(:provider) |> field(:options) |> field(:local_search_reference)

  defp field(map, key) when is_map(map) and is_atom(key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(key))
    end
  end

  defp field(_value, _key), do: nil

  defp normalize_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      "$" <> _unresolved -> nil
      value -> value
    end
  end

  defp normalize_string(_value), do: nil
end
