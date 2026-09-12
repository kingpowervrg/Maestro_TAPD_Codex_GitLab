defmodule SymphonyElixir.Repo.Git.SparseCheckout do
  @moduledoc false

  alias SymphonyElixir.Repo.Error
  alias SymphonyElixir.Repo.Git.{Command, Validation}

  @operation :sparse_add

  @spec add(Path.t(), [String.t()], String.t(), keyword()) ::
          {:ok, [String.t()]} | {:error, Error.t()}
  def add(path, paths, ref \\ "HEAD", opts \\ [])

  def add(path, paths, ref, opts)
      when is_binary(path) and is_list(paths) and is_binary(ref) and is_list(opts) do
    with :ok <- Validation.directory(path, @operation),
         {:ok, normalized_paths} <- validate_paths(path, paths),
         :ok <- ensure_sparse_checkout(path, opts),
         :ok <- ensure_directories_exist(path, normalized_paths, ref, opts),
         {:ok, _output} <- run(path, ["sparse-checkout", "add"] ++ normalized_paths, opts),
         {:ok, _output} <- run(path, ["sparse-checkout", "reapply", "--sparse-index"], opts) do
      {:ok, normalized_paths}
    end
  end

  def add(path, _paths, _ref, _opts),
    do: {:error, Error.invalid_invocation(@operation, "Sparse checkout paths must be a list.", path)}

  defp validate_paths(path, paths) do
    normalized = paths |> Enum.map(&normalize_path/1) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    cond do
      normalized == [] ->
        {:error, Error.invalid_invocation(@operation, "At least one target directory is required.", path)}

      length(normalized) > 20 ->
        {:error, Error.invalid_invocation(@operation, "At most 20 target directories may be added at once.", path)}

      invalid = Enum.find(normalized, &(not safe_relative_directory?(&1))) ->
        {:error,
         Error.invalid_invocation(
           @operation,
           "Sparse checkout path must be a safe repository-relative directory: #{inspect(invalid)}.",
           path
         )}

      true ->
        {:ok, normalized}
    end
  end

  defp normalize_path(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> String.trim_trailing(trimmed, "/")
    end
  end

  defp normalize_path(_value), do: nil

  defp safe_relative_directory?(path) do
    segments = String.split(path, "/", trim: false)

    Path.type(path) == :relative and
      path not in ["", "."] and
      not String.starts_with?(path, "-") and
      not String.contains?(path, ["\\", "\0", "\n", "\r"]) and
      Enum.all?(segments, &(&1 not in ["", ".", ".."]))
  end

  defp ensure_sparse_checkout(path, opts) do
    case Command.run(path, ["config", "--bool", "core.sparseCheckout"], opts) do
      {:ok, output} ->
        if String.trim(output) == "true" do
          :ok
        else
          {:error, Error.invalid_invocation(@operation, "Repository is not using sparse checkout.", path)}
        end

      {:error, {:enoent, _output}} ->
        {:error, Error.missing_tooling(@operation, path)}

      {:error, {_status, _output}} ->
        {:error, Error.invalid_invocation(@operation, "Repository is not using sparse checkout.", path)}
    end
  end

  defp ensure_directories_exist(path, paths, ref, opts) do
    Enum.reduce_while(paths, :ok, fn target, :ok ->
      case Command.run(path, ["ls-tree", "-d", "--name-only", ref, "--", target], opts) do
        {:ok, output} ->
          if output |> String.split("\n", trim: true) |> Enum.member?(target) do
            {:cont, :ok}
          else
            {:halt,
             {:error,
              Error.invalid_invocation(
                @operation,
                "Target directory #{inspect(target)} does not exist at ref #{inspect(ref)}.",
                path,
                %{ref: ref, target: target}
              )}}
          end

        {:error, {:enoent, _output}} ->
          {:halt, {:error, Error.missing_tooling(@operation, path)}}

        {:error, {status, output}} ->
          {:halt, {:error, Error.operation_failed(@operation, :sparse_tree_lookup_failed, path, status, output)}}
      end
    end)
  end

  defp run(path, args, opts) do
    case Command.run(path, args, opts) do
      {:ok, output} -> {:ok, output}
      {:error, {:enoent, _output}} -> {:error, Error.missing_tooling(@operation, path)}
      {:error, {status, output}} -> {:error, Error.operation_failed(@operation, :sparse_checkout_failed, path, status, output)}
    end
  end
end
