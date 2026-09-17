defmodule SymphonyElixir.Workspace.AutomationPack do
  @moduledoc false

  alias SymphonyElixir.Workspace.Paths

  @bundle_dirname "workspace_automation"
  @cache_rootname "symphony-elixir-workspace-automation-pack"
  @runtime_env_var "SYMPHONY_WORKSPACE_AUTOMATION_DIR"
  @cli_env_var "SYMPHONY_CLI"

  @type source_kind :: :bundled | :override

  @spec runtime_env_var() :: String.t()
  def runtime_env_var, do: @runtime_env_var

  @spec cli_env_var() :: String.t()
  def cli_env_var, do: @cli_env_var

  @spec destination_dir(Path.t(), String.t()) :: Path.t()
  def destination_dir(workspace, destination_dirname)
      when is_binary(workspace) and is_binary(destination_dirname) do
    Path.join(workspace, destination_dirname)
  end

  @spec runtime_env(Path.t(), String.t()) :: [{String.t(), String.t()}]
  def runtime_env(workspace, destination_dirname)
      when is_binary(workspace) and is_binary(destination_dirname) do
    workspace_env = [{@runtime_env_var, destination_dir(workspace, destination_dirname)}]

    case current_cli_path() do
      {:ok, cli_path} -> [{@cli_env_var, cli_path} | workspace_env]
      :error -> workspace_env
    end
  end

  @spec remote_shell_assign(Path.t(), String.t()) :: String.t()
  def remote_shell_assign(workspace, destination_dirname)
      when is_binary(workspace) and is_binary(destination_dirname) do
    [
      Paths.remote_shell_assign(@runtime_env_var, destination_dir(workspace, destination_dirname)),
      "export #{@runtime_env_var}"
    ]
    |> Enum.join("\n")
  end

  @spec source_dir(nil | String.t()) :: {:ok, source_kind(), Path.t()} | {:error, term()}
  def source_dir(override_dir \\ nil)

  def source_dir(override_dir) when is_binary(override_dir) and override_dir != "" do
    {:ok, :override, override_dir}
  end

  def source_dir(_override_dir) do
    with {:ok, bundled_dir} <- bundled_source_dir() do
      {:ok, :bundled, bundled_dir}
    end
  end

  @spec bundled_source_dir() :: {:ok, Path.t()} | {:error, term()}
  def bundled_source_dir do
    case application_priv_source_dir() do
      {:ok, bundled_dir} ->
        compose_sources(bundled_dir)

      {:error, _reason} ->
        extract_bundled_source_dir()
    end
  end

  defp compose_sources(bundled_dir) do
    case configured_source_dirs() do
      [] -> {:ok, bundled_dir}
      overlay_dirs -> build_composite_source([bundled_dir | overlay_dirs])
    end
  end

  defp configured_source_dirs do
    :symphony_elixir
    |> Application.get_env(:workspace_automation_sources, [])
    |> List.wrap()
    |> Enum.map(&source_dir!/1)
  end

  defp source_dir!(module) when is_atom(module) do
    unless Code.ensure_loaded?(module) and function_exported?(module, :source_dir, 1) do
      raise ArgumentError, "invalid workspace automation source: #{inspect(module)}"
    end

    case module.source_dir([]) do
      path when is_binary(path) and path != "" -> path
      value -> raise ArgumentError, "workspace automation source must return a path, got: #{inspect(value)}"
    end
  end

  defp source_dir!(value),
    do: raise(ArgumentError, "invalid workspace automation source: #{inspect(value)}")

  defp build_composite_source(source_dirs) do
    with :ok <- validate_composite_sources(source_dirs) do
      cache_key = source_dirs |> Enum.map(&source_fingerprint/1) |> :erlang.phash2() |> Integer.to_string(36)
      cache_parent = Path.join([System.tmp_dir!(), @cache_rootname, "composite-#{cache_key}"])
      composite_dir = Path.join(cache_parent, @bundle_dirname)

      if File.dir?(composite_dir) do
        {:ok, composite_dir}
      else
        assemble_composite_source(source_dirs, cache_parent, composite_dir)
      end
    end
  end

  defp validate_composite_sources(source_dirs) do
    case Enum.find(source_dirs, &(not File.dir?(&1))) do
      nil -> :ok
      path -> {:error, {:bundled_automation_pack_missing, path}}
    end
  end

  defp source_fingerprint(path) do
    case File.stat(path, time: :posix) do
      {:ok, stat} -> {Path.expand(path), stat.mtime, stat.size}
      {:error, reason} -> {Path.expand(path), reason}
    end
  end

  defp assemble_composite_source(source_dirs, cache_parent, composite_dir) do
    staging_parent = cache_parent <> ".#{System.unique_integer([:positive, :monotonic])}"
    staging_dir = Path.join(staging_parent, @bundle_dirname)

    try do
      File.mkdir_p!(staging_dir)
      Enum.each(source_dirs, &copy_overlay!(&1, staging_dir))
      File.mkdir_p!(Path.dirname(cache_parent))

      case File.rename(staging_parent, cache_parent) do
        :ok -> :ok
        {:error, :eexist} -> :ok
        {:error, reason} -> raise File.Error, reason: reason, action: "rename", path: cache_parent
      end

      {:ok, composite_dir}
    after
      File.rm_rf(staging_parent)
    end
  rescue
    error -> {:error, {:workspace_automation_source_composition_failed, Exception.message(error)}}
  end

  defp copy_overlay!(source_dir, destination_dir) do
    source_dir
    |> File.ls!()
    |> Enum.each(fn entry -> copy_overlay_entry!(Path.join(source_dir, entry), Path.join(destination_dir, entry)) end)
  end

  defp copy_overlay_entry!(source, destination) do
    if File.dir?(source) do
      File.mkdir_p!(destination)
      copy_overlay!(source, destination)
    else
      File.mkdir_p!(Path.dirname(destination))
      File.cp!(source, destination)
    end
  end

  defp application_priv_source_dir do
    case Application.app_dir(:symphony_elixir, Path.join("priv", @bundle_dirname)) do
      path when is_binary(path) ->
        cond do
          File.dir?(path) ->
            {:ok, path}

          File.exists?(path) ->
            {:error, {:bundled_automation_pack_not_directory, path}}

          true ->
            {:error, {:bundled_automation_pack_missing, path}}
        end
    end
  rescue
    ArgumentError ->
      {:error, :bundled_automation_pack_missing}
  end

  defp extract_bundled_source_dir do
    with {:ok, script_path} <- escript_path(),
         {:ok, cache_root} <- extraction_cache_root(script_path),
         {:ok, bundled_dir} <- ensure_extracted_bundle(script_path, cache_root) do
      {:ok, bundled_dir}
    else
      {:error, reason} ->
        {:error, {:workspace_bootstrap_automation_unavailable, reason}}
    end
  end

  defp escript_path do
    case :escript.script_name() do
      script_name when is_list(script_name) ->
        script_path = script_name |> List.to_string() |> Path.expand()

        cond do
          script_path in ["", Path.expand("-e")] ->
            {:error, :escript_script_name_unavailable}

          File.regular?(script_path) ->
            {:ok, script_path}

          true ->
            {:error, {:escript_script_not_found, script_path}}
        end
    end
  end

  defp extraction_cache_root(script_path) do
    case File.stat(script_path) do
      {:ok, %File.Stat{size: size, mtime: mtime}} ->
        cache_key = :erlang.phash2({script_path, size, mtime}) |> Integer.to_string(36)
        {:ok, Path.join([System.tmp_dir!(), @cache_rootname, cache_key])}

      {:error, reason} ->
        {:error, {:escript_stat_failed, script_path, reason}}
    end
  end

  defp ensure_extracted_bundle(script_path, cache_root) do
    case find_extracted_bundle(cache_root) do
      {:ok, bundled_dir} ->
        {:ok, bundled_dir}

      {:error, _reason} ->
        File.rm_rf!(cache_root)
        File.mkdir_p!(cache_root)

        with {:ok, archive_bin} <- escript_archive(script_path),
             :ok <- unzip_archive(archive_bin, cache_root),
             {:ok, bundled_dir} <- find_extracted_bundle(cache_root) do
          {:ok, bundled_dir}
        end
    end
  end

  defp find_extracted_bundle(cache_root) do
    [cache_root, "**", "priv", @bundle_dirname]
    |> Path.join()
    |> Path.wildcard()
    |> Enum.find(&File.dir?/1)
    |> case do
      nil -> {:error, {:bundled_automation_pack_missing_after_extract, cache_root}}
      bundled_dir -> {:ok, bundled_dir}
    end
  end

  defp escript_archive(script_path) do
    case :escript.extract(String.to_charlist(script_path), []) do
      {:ok, sections} ->
        case Keyword.fetch(sections, :archive) do
          {:ok, archive_bin} when is_binary(archive_bin) ->
            {:ok, archive_bin}

          {:ok, _section} ->
            {:error, :escript_archive_invalid}

          :error ->
            {:error, :escript_archive_missing}
        end

      {:error, reason} ->
        {:error, {:escript_extract_failed, reason}}
    end
  end

  defp unzip_archive(archive_bin, cache_root) when is_binary(archive_bin) and is_binary(cache_root) do
    case :zip.extract(archive_bin, [{:cwd, String.to_charlist(cache_root)}]) do
      {:ok, _paths} ->
        :ok

      {:error, reason} ->
        {:error, {:archive_extract_failed, reason}}
    end
  end

  defp current_cli_path do
    [
      System.get_env(@cli_env_var),
      escript_script_path(),
      System.find_executable("symphony")
    ]
    |> Enum.find_value(fn
      path when is_binary(path) and path != "" ->
        expanded = Path.expand(path)

        if File.regular?(expanded) do
          {:ok, expanded}
        else
          false
        end

      _path ->
        false
    end)
    |> case do
      {:ok, path} -> {:ok, path}
      nil -> :error
    end
  end

  defp escript_script_path do
    case :escript.script_name() do
      script_name when is_list(script_name) ->
        script_name
        |> List.to_string()
        |> case do
          script_path when script_path in ["", "-e"] -> nil
          script_path -> script_path
        end
    end
  rescue
    _error -> nil
  end
end
