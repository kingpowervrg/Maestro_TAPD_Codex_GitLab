defmodule SymphonyElixir.Tracker.Tapd.Client.Reader do
  @moduledoc false

  alias SymphonyElixir.Issue
  alias SymphonyElixir.Tracker.Config, as: TrackerConfig
  alias SymphonyElixir.Tracker.IssuePolicy.Runtime, as: IssuePolicyRuntime
  alias SymphonyElixir.Tracker.Tapd.Client.{BugPayload, Errors, Fields, Paths, Request, StoryPayload, StoryRelations, WorkitemTypeScope}
  alias SymphonyElixir.Tracker.Tapd.{ProviderOptions, WorkflowConfig}

  @page_limit 100
  @request_timeout_ms 30_000
  @id_fetch_max_concurrency 4

  @spec fetch_candidate_issues(map(), keyword()) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_candidate_issues(tracker, opts \\ []) when is_map(tracker) and is_list(opts) do
    request_fun = Keyword.get(opts, :request_fun, &Request.default_request/1)
    reader_opts = opts |> Keyword.put(:tracker, tracker) |> Keyword.put(:request_fun, request_fun)

    result =
      case candidate_issue_ids(tracker) do
        issue_ids when is_list(issue_ids) and issue_ids != [] ->
          fetch_issues_by_ids(issue_ids, reader_opts)

        _issue_ids ->
          with state_names when is_list(state_names) <- TrackerConfig.active_states(tracker),
               {:ok, stories} <- fetch_stories_by_status(state_names, reader_opts),
               {:ok, bugs} <- maybe_fetch_candidate_bugs(tracker, reader_opts) do
            {:ok, stories ++ bugs}
          else
            nil -> {:error, :missing_tapd_active_states}
            error -> error
          end
      end

    Errors.map_result(result, :fetch_candidate_issues)
  end

  @spec fetch_issues_by_states([String.t()], map(), keyword()) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issues_by_states(state_names, tracker, opts \\ [])
      when is_list(state_names) and is_map(tracker) and is_list(opts) do
    reader_opts = Keyword.put(opts, :tracker, tracker)

    with {:ok, stories} <- fetch_stories_by_status(state_names, reader_opts),
         {:ok, bugs} <- maybe_fetch_bugs_by_requested_states(state_names, tracker, reader_opts) do
      {:ok, stories ++ bugs}
    end
    |> Errors.map_result(:fetch_issues_by_states)
  end

  @spec fetch_issue_states_by_ids([String.t()], map(), keyword()) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issue_states_by_ids(issue_ids, tracker, opts \\ [])
      when is_list(issue_ids) and is_map(tracker) and is_list(opts) do
    issue_ids
    |> fetch_issues_by_ids(Keyword.put(opts, :tracker, tracker))
    |> Errors.map_result(:fetch_issue_states_by_ids)
  end

  @spec fetch_issues_by_ids([String.t()], keyword()) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issues_by_ids(issue_ids, opts \\ []) when is_list(issue_ids) and is_list(opts) do
    tracker = Keyword.fetch!(opts, :tracker)
    normalized_ids = normalize_issue_ids(issue_ids)

    with {:ok, stories} <- do_fetch_stories_by_ids(normalized_ids, tracker, Keyword.get(opts, :request_fun, &Request.default_request/1)),
         missing_ids <- missing_issue_ids(normalized_ids, stories),
         {:ok, bugs} <- maybe_fetch_bugs_by_ids(missing_ids, tracker, opts) do
      {:ok, order_issues_by_ids(stories ++ bugs, normalized_ids)}
    end
  end

  @spec fetch_stories_by_status([String.t()], keyword()) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_stories_by_status(state_names, opts \\ [])
      when is_list(state_names) and is_list(opts) do
    tracker = Keyword.fetch!(opts, :tracker)
    operation = Keyword.get(opts, :operation, :fetch_issues_by_states)
    request_fun = Keyword.get(opts, :request_fun, &Request.default_request/1)

    statuses =
      state_names
      |> Enum.map(&Fields.normalize_string/1)
      |> Enum.reject(&is_nil/1)

    result =
      case statuses do
        [] ->
          {:ok, []}

        _ ->
          with {:ok, issues} <-
                 do_fetch_stories_by_status(
                   tracker,
                   Enum.join(statuses, "|"),
                   1,
                   [],
                   [],
                   request_fun
                 ) do
            maybe_enrich_issues(issues, tracker, request_fun, opts)
          end
      end

    Errors.map_result(result, operation)
  end

  @spec fetch_stories_by_ids([String.t()], keyword()) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_stories_by_ids(issue_ids, opts \\ []) when is_list(issue_ids) and is_list(opts) do
    tracker = Keyword.fetch!(opts, :tracker)
    operation = Keyword.get(opts, :operation, :fetch_issue_states_by_ids)
    request_fun = Keyword.get(opts, :request_fun, &Request.default_request/1)

    result =
      issue_ids
      |> Enum.map(&normalize_issue_id/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> do_fetch_stories_by_ids(tracker, request_fun)
      |> case do
        {:ok, issues} -> maybe_enrich_issues(issues, tracker, request_fun, opts)
        error -> error
      end

    Errors.map_result(result, operation)
  end

  @spec fetch_bugs_by_status([String.t()], keyword()) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_bugs_by_status(state_names, opts \\ []) when is_list(state_names) and is_list(opts) do
    tracker = Keyword.fetch!(opts, :tracker)
    request_fun = Keyword.get(opts, :request_fun, &Request.default_request/1)

    statuses = state_names |> Enum.map(&Fields.normalize_string/1) |> Enum.reject(&is_nil/1)

    case statuses do
      [] ->
        {:ok, []}

      _statuses ->
        filters = Keyword.get(opts, :policy_filters, %{})
        do_fetch_bugs_by_status(tracker, Enum.join(statuses, "|"), filters, 1, [], request_fun)
    end
  end

  @spec fetch_bugs_by_ids([String.t()], keyword()) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_bugs_by_ids(issue_ids, opts \\ []) when is_list(issue_ids) and is_list(opts) do
    tracker = Keyword.fetch!(opts, :tracker)
    request_fun = Keyword.get(opts, :request_fun, &Request.default_request/1)

    issue_ids
    |> normalize_issue_ids()
    |> Task.async_stream(
      &fetch_bug_by_id(&1, tracker, request_fun),
      max_concurrency: @id_fetch_max_concurrency,
      ordered: true,
      timeout: @request_timeout_ms + 1_000
    )
    |> reduce_issue_fetch_results()
  end

  @spec fetch_story_by_id(String.t(), map(), function()) :: {:ok, [Issue.t()]} | {:error, term()}
  defp fetch_story_by_id(issue_id, tracker, request_fun) do
    case Request.request("GET", Paths.stories(), %{"id" => issue_id},
           tracker: tracker,
           request_fun: request_fun
         ) do
      {:ok, body} ->
        case StoryPayload.decode(Paths.stories(), body, tracker, request_fun, validate_workitem_types?: false) do
          {:ok, issues, _raw_count, _observed_workitem_type_ids} -> {:ok, issues}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_bug_by_id(issue_id, tracker, request_fun) do
    case Request.request("GET", Paths.bugs(), %{"id" => issue_id}, tracker: tracker, request_fun: request_fun) do
      {:ok, body} ->
        case BugPayload.decode(Paths.bugs(), body, tracker) do
          {:ok, issues, _raw_count} -> {:ok, issues}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_fetch_stories_by_status(
         tracker,
         status_filter,
         page,
         acc,
         observed_workitem_type_ids,
         request_fun
       ) do
    params =
      %{
        "status" => status_filter,
        "page" => page,
        "limit" => @page_limit
      }
      |> maybe_put_workitem_type_id(WorkflowConfig.request_workitem_type_id(tracker))
      |> maybe_put_assignee(ProviderOptions.assignee(tracker))

    with {:ok, body} <-
           Request.request("GET", Paths.stories(), params, tracker: tracker, request_fun: request_fun),
         {:ok, issues, raw_count, page_workitem_type_ids} <-
           StoryPayload.decode(Paths.stories(), body, tracker, request_fun, validate_workitem_types?: false) do
      updated_acc = acc ++ issues

      updated_workitem_type_ids =
        WorkitemTypeScope.merge_ids(observed_workitem_type_ids, page_workitem_type_ids)

      if raw_count < @page_limit do
        with :ok <-
               WorkitemTypeScope.maybe_validate(
                 updated_workitem_type_ids,
                 tracker,
                 request_fun,
                 true
               ) do
          {:ok, updated_acc}
        end
      else
        do_fetch_stories_by_status(
          tracker,
          status_filter,
          page + 1,
          updated_acc,
          updated_workitem_type_ids,
          request_fun
        )
      end
    end
  end

  defp do_fetch_stories_by_ids(issue_ids, tracker, request_fun) do
    issue_ids
    |> Task.async_stream(
      fn issue_id ->
        fetch_story_by_id(issue_id, tracker, request_fun)
      end,
      max_concurrency: @id_fetch_max_concurrency,
      ordered: true,
      timeout: @request_timeout_ms + 1_000
    )
    |> reduce_issue_fetch_results()
  end

  defp reduce_issue_fetch_results(results) do
    Enum.reduce_while(results, {:ok, []}, fn
      {:ok, {:ok, issues}}, {:ok, acc} ->
        {:cont, {:ok, acc ++ issues}}

      {:ok, {:error, reason}}, _acc ->
        {:halt, {:error, reason}}

      {:exit, reason}, _acc ->
        {:halt, {:error, {:tapd_request, reason}}}
    end)
  end

  defp do_fetch_bugs_by_status(tracker, status_filter, filters, page, acc, request_fun) do
    params =
      %{"status" => status_filter, "page" => page, "limit" => @page_limit}
      |> maybe_put_bug_assignee(ProviderOptions.assignee(tracker))
      |> Map.merge(filters)

    with {:ok, body} <- Request.request("GET", Paths.bugs(), params, tracker: tracker, request_fun: request_fun),
         {:ok, issues, raw_count} <- BugPayload.decode(Paths.bugs(), body, tracker) do
      updated_acc = acc ++ issues

      if raw_count < @page_limit do
        {:ok, updated_acc}
      else
        do_fetch_bugs_by_status(tracker, status_filter, filters, page + 1, updated_acc, request_fun)
      end
    end
  end

  defp maybe_fetch_candidate_bugs(tracker, opts) do
    case IssuePolicyRuntime.candidate_scope("bug", tracker) do
      %{states: states, filters: filters} when is_list(states) and is_map(filters) ->
        fetch_bugs_by_status(states, Keyword.put(opts, :policy_filters, filters))

      _scope ->
        {:ok, []}
    end
  end

  defp maybe_fetch_bugs_by_requested_states(state_names, tracker, opts) do
    case IssuePolicyRuntime.candidate_scope("bug", tracker) do
      %{states: states, filters: filters} when is_list(states) and is_map(filters) ->
        requested_states = Enum.filter(state_names, &(&1 in states))

        if requested_states == [],
          do: {:ok, []},
          else: fetch_bugs_by_status(requested_states, Keyword.put(opts, :policy_filters, filters))

      _scope ->
        {:ok, []}
    end
  end

  defp maybe_fetch_bugs_by_ids([], _tracker, _opts), do: {:ok, []}

  defp maybe_fetch_bugs_by_ids(issue_ids, tracker, opts) do
    case IssuePolicyRuntime.candidate_scope("bug", tracker) do
      %{} -> fetch_bugs_by_ids(issue_ids, opts)
      nil -> {:ok, []}
    end
  end

  defp maybe_put_bug_assignee(params, nil), do: params
  defp maybe_put_bug_assignee(params, assignee), do: Map.put(params, "current_owner", assignee)

  defp normalize_issue_ids(issue_ids) do
    issue_ids
    |> Enum.map(&normalize_issue_id/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp missing_issue_ids(issue_ids, issues) do
    found_ids = MapSet.new(issues, & &1.id)
    Enum.reject(issue_ids, &MapSet.member?(found_ids, &1))
  end

  defp order_issues_by_ids(issues, issue_ids) do
    issues_by_id = Map.new(issues, &{&1.id, &1})
    Enum.flat_map(issue_ids, fn issue_id -> List.wrap(Map.get(issues_by_id, issue_id)) end)
  end

  defp maybe_put_workitem_type_id(params, workitem_type_id) do
    case Fields.normalize_string(workitem_type_id) do
      nil -> params
      value -> Map.put(params, "workitem_type_id", value)
    end
  end

  defp maybe_put_assignee(params, nil), do: params
  defp maybe_put_assignee(params, assignee), do: Map.put(params, "owner", assignee)

  defp maybe_enrich_issues(issues, tracker, request_fun, opts) do
    if Keyword.get(opts, :include_relations?, true) do
      StoryRelations.enrich_issues(issues, tracker, request_fun, &fetch_story_by_id/3)
    else
      {:ok, issues}
    end
  end

  defp normalize_issue_id("TAPD-" <> id), do: normalize_issue_id(id)
  defp normalize_issue_id(issue_id), do: Fields.normalize_string(issue_id)

  defp candidate_issue_ids(tracker) do
    tracker
    |> TrackerConfig.provider()
    |> nested_value("candidate_issue_ids")
    |> normalize_string_list()
  end

  defp normalize_string_list(values) when is_list(values) do
    values
    |> Enum.map(&Fields.normalize_string/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp normalize_string_list(_values), do: []

  defp nested_value(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) || map_get_existing_atom(map, key)
  end

  defp nested_value(_map, _key), do: nil

  defp map_get_existing_atom(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> nil
  end
end
