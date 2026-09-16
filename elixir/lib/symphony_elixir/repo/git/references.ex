defmodule SymphonyElixir.Repo.Git.References do
  @moduledoc false

  alias SymphonyElixir.Repo.Error

  @spec remote_default_branch(String.t(), Path.t(), String.t()) :: {:ok, String.t()} | {:error, Error.t()}
  def remote_default_branch(output, path, remote) do
    remote_head = String.trim(output)
    prefix = "refs/remotes/#{remote}/"

    with true <- String.starts_with?(remote_head, prefix),
         branch when is_binary(branch) and branch != "" <- String.replace_prefix(remote_head, prefix, "") do
      {:ok, branch}
    else
      _other -> {:error, Error.remote_not_found(:remote_default_branch, path, remote, %{output: output})}
    end
  end

  @spec ls_remote_default_branch(String.t(), String.t()) :: {:ok, String.t()} | {:error, Error.t()}
  def ls_remote_default_branch(output, remote_url) do
    case Regex.run(~r/^ref:\s+refs\/heads\/([^\s]+)\s+HEAD$/m, output, capture: :all_but_first) do
      [branch] ->
        {:ok, branch}

      _other ->
        {:error,
         Error.operation_failed(
           :remote_default_branch_from_url,
           :remote_default_branch_unavailable,
           nil,
           1,
           "Unable to determine default branch for #{remote_url}"
         )}
    end
  end

  @spec published_head_sha(String.t(), Path.t(), String.t()) :: {:ok, String.t()} | {:error, Error.t()}
  def published_head_sha(output, path, ref) do
    output
    |> String.split("\n", trim: true)
    |> Enum.find_value(fn line ->
      case String.split(line, ~r/\s+/, parts: 2) do
        [sha, remote_ref] ->
          if valid_object_id?(sha) and String.starts_with?(remote_ref, "refs/"), do: sha

        _other ->
          nil
      end
    end)
    |> case do
      sha when is_binary(sha) -> {:ok, sha}
      nil -> {:error, Error.branch_not_found(:published_head_sha, path, ref)}
    end
  end

  defp valid_object_id?(value) when is_binary(value),
    do: Regex.match?(~r/\A(?:[0-9a-fA-F]{40}|[0-9a-fA-F]{64})\z/, value)
end
