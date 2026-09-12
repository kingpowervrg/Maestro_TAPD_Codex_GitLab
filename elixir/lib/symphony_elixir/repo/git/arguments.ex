defmodule SymphonyElixir.Repo.Git.Arguments do
  @moduledoc false

  @spec append_depth([String.t()], pos_integer() | String.t() | term()) :: [String.t()]
  def append_depth(args, depth) when is_integer(depth) and depth > 0, do: args ++ ["--depth", Integer.to_string(depth)]
  def append_depth(args, depth) when is_binary(depth) and depth != "", do: args ++ ["--depth", depth]
  def append_depth(args, _depth), do: args

  @spec append_filter([String.t()], String.t() | term()) :: [String.t()]
  def append_filter(args, filter) when is_binary(filter) and filter != "", do: args ++ ["--filter", filter]
  def append_filter(args, _filter), do: args

  @spec append_sparse([String.t()], boolean()) :: [String.t()]
  def append_sparse(args, true), do: args ++ ["--sparse"]
  def append_sparse(args, _sparse), do: args

  @spec append_reference_if_able([String.t()], String.t() | term()) :: [String.t()]
  def append_reference_if_able(args, path) when is_binary(path) and path != "",
    do: args ++ ["--reference-if-able", path]

  def append_reference_if_able(args, _path), do: args

  @spec append_branch([String.t()], String.t() | term()) :: [String.t()]
  def append_branch(args, branch) when is_binary(branch) and branch != "", do: args ++ ["--branch", branch]
  def append_branch(args, _branch), do: args

  @spec append_force_with_lease([String.t()], boolean()) :: [String.t()]
  def append_force_with_lease(args, true), do: args ++ ["--force-with-lease"]
  def append_force_with_lease(args, _force_with_lease), do: args

  @spec append_set_upstream([String.t()], boolean()) :: [String.t()]
  def append_set_upstream(args, true), do: args ++ ["-u"]
  def append_set_upstream(args, _set_upstream), do: args
end
