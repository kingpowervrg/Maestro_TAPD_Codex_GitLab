defmodule SymphonyElixir.Orchestrator.Retry.IssueHandler do
  @moduledoc false

  alias SymphonyElixir.Issue
  alias SymphonyElixir.Orchestrator.Dispatch
  alias SymphonyElixir.Orchestrator.Retry.{Events, Scheduler}

  @spec handle(map(), String.t(), integer(), map(), keyword()) :: {:noreply, map()}
  def handle(state, issue_id, attempt, metadata, opts)
      when is_map(state) and is_binary(issue_id) and is_integer(attempt) and is_map(metadata) do
    dispatch_context = Keyword.fetch!(opts, :dispatch_context)
    dispatch_runtime = Keyword.fetch!(opts, :dispatch_runtime)
    dispatch_issue = Keyword.fetch!(opts, :dispatch_issue)
    release_issue_claim = Keyword.fetch!(opts, :release_issue_claim)
    cleanup_issue_workspace = Keyword.fetch!(opts, :cleanup_issue_workspace)
    emit_event = Keyword.get(opts, :emit_event)
    fetch_candidate_issues = Keyword.get(opts, :fetch_candidate_issues, fn -> {:ok, []} end)

    case fetch_candidate_issues.() do
      {:ok, issues} ->
        issues
        |> find_issue_by_id(issue_id)
        |> resolve_missing_issue(issue_id, opts)
        |> handle_retry_issue_lookup(
          state,
          issue_id,
          attempt,
          metadata,
          dispatch_context,
          dispatch_runtime,
          dispatch_issue,
          release_issue_claim,
          cleanup_issue_workspace,
          emit_event,
          opts
        )

      {:error, reason} ->
        Events.emit(
          emit_event,
          :warning,
          :issue_retry_poll_failed,
          nil,
          state,
          %{
            issue_id: issue_id,
            issue_identifier: metadata[:identifier] || issue_id,
            attempt: attempt,
            run_id: metadata[:run_id],
            error: inspect(reason),
            worker_host: metadata[:worker_host],
            workspace_path: metadata[:workspace_path]
          }
        )

        {:noreply,
         Scheduler.schedule(
           state,
           issue_id,
           attempt + 1,
           Map.merge(metadata, %{error: "retry poll failed: #{inspect(reason)}"}),
           emit_event: emit_event
         )}
    end
  end

  def handle(state, _issue_id, _attempt, _metadata, _opts), do: {:noreply, state}

  defp handle_retry_issue_lookup(
         %Issue{} = issue,
         state,
         issue_id,
         attempt,
         metadata,
         dispatch_context,
         dispatch_runtime,
         dispatch_issue,
         release_issue_claim,
         cleanup_issue_workspace,
         emit_event,
         opts
       ) do
    cond do
      Dispatch.terminal_issue_state?(issue, issue.state, dispatch_context) ->
        Events.released(emit_event, issue, state, attempt, metadata, "terminal")
        cleanup_workspace(cleanup_issue_workspace, issue.identifier, metadata)
        {:noreply, release_issue_claim.(state, issue_id)}

      Dispatch.retry_candidate_issue?(issue, dispatch_context) and Scheduler.exhausted?(attempt) ->
        handle_retry_exhausted(issue, state, issue_id, attempt, metadata, emit_event, opts)

      Dispatch.retry_candidate_issue?(issue, dispatch_context) ->
        handle_active_retry(
          state,
          issue,
          attempt,
          metadata,
          dispatch_context,
          dispatch_runtime,
          dispatch_issue,
          emit_event
        )

      true ->
        skip_reason = retry_release_reason(issue)
        Events.released(emit_event, issue, state, attempt, metadata, skip_reason)
        maybe_cleanup_unrouted_workspace(cleanup_issue_workspace, issue, metadata)
        {:noreply, release_issue_claim.(state, issue_id)}
    end
  end

  defp handle_retry_issue_lookup(
         nil,
         state,
         issue_id,
         _attempt,
         _metadata,
         _dispatch_context,
         _dispatch_runtime,
         _dispatch_issue,
         release_issue_claim,
         _cleanup_issue_workspace,
         emit_event,
         _opts
       ) do
    Events.emit(
      emit_event,
      :info,
      :issue_retry_released,
      nil,
      state,
      %{
        issue_id: issue_id,
        run_id: nil,
        skip_reason: "missing"
      }
    )

    {:noreply, release_issue_claim.(state, issue_id)}
  end

  defp handle_active_retry(
         state,
         issue,
         attempt,
         metadata,
         dispatch_context,
         dispatch_runtime,
         dispatch_issue,
         emit_event
       ) do
    if Dispatch.retry_candidate_issue?(issue, dispatch_context) and
         Dispatch.dispatch_slots_available?(issue, dispatch_runtime, dispatch_context) and
         runtime_worker_slots_available?(dispatch_runtime) do
      {:noreply, dispatch_issue.(state, issue, attempt, metadata[:worker_host])}
    else
      Events.emit(
        emit_event,
        :info,
        :issue_retry_dispatch_deferred,
        issue,
        state,
        %{
          attempt: attempt,
          run_id: metadata[:run_id],
          skip_reason: "no_available_slots",
          worker_host: metadata[:worker_host],
          workspace_path: metadata[:workspace_path]
        }
      )

      {:noreply,
       Scheduler.schedule(
         state,
         issue.id,
         attempt,
         Map.merge(metadata, %{
           identifier: issue.identifier,
           error: "no available orchestrator slots"
         }),
         emit_event: emit_event
       )}
    end
  end

  defp handle_retry_exhausted(issue, state, issue_id, attempt, metadata, emit_event, opts) do
    max_retry_attempts = SymphonyElixir.Config.settings!().agent.execution.max_retry_attempts

    Events.emit(
      emit_event,
      :error,
      :issue_retry_exhausted,
      issue,
      state,
      %{
        issue_id: issue_id,
        issue_identifier: issue.identifier,
        attempt: attempt,
        max_retry_attempts: max_retry_attempts,
        run_id: metadata[:run_id],
        worker_host: metadata[:worker_host],
        workspace_path: metadata[:workspace_path],
        failure_class: metadata[:failure_class],
        error: metadata[:error],
        result_summary: "retry_exhausted"
      }
    )

    record_retry_exhaustion_confusion(
      issue,
      issue_id,
      attempt,
      max_retry_attempts,
      emit_event,
      state,
      metadata,
      opts
    )

    mark_retry_exhaustion_exception(issue, issue_id, emit_event, state, metadata, opts)

    finalize_retry_exhaustion =
      Keyword.get(opts, :finalize_retry_exhaustion, fn retry_state, retry_issue_id ->
        release_issue_claim = Keyword.fetch!(opts, :release_issue_claim)
        release_issue_claim.(retry_state, retry_issue_id)
      end)

    {:noreply, finalize_retry_exhaustion.(state, issue_id)}
  end

  defp record_retry_exhaustion_confusion(
         %Issue{entity_type: "bug"} = issue,
         issue_id,
         attempt,
         max_retry_attempts,
         emit_event,
         state,
         metadata,
         opts
       ) do
    create_comment = Keyword.get(opts, :create_comment)

    case create_comment do
      create_comment when is_function(create_comment, 3) ->
        body = retry_exhaustion_confusion_body(attempt, max_retry_attempts, metadata)
        result = create_comment.(issue_id, body, entity_type: "bug")
        emit_retry_exhaustion_comment_result(result, issue, issue_id, emit_event, state, metadata)

      _create_comment ->
        :ok
    end
  end

  defp record_retry_exhaustion_confusion(
         _issue,
         _issue_id,
         _attempt,
         _max_retry_attempts,
         _emit_event,
         _state,
         _metadata,
         _opts
       ),
       do: :ok

  defp retry_exhaustion_confusion_body(attempt, max_retry_attempts, metadata) do
    error =
      metadata
      |> Map.get(:error, "Unknown retry failure")
      |> to_string()
      |> String.replace("```", "'''")

    """
    ### Confusions

    - [ ] Symphony cannot continue because the retry limit was exhausted.
    - Failure class: `#{metadata_value(metadata[:failure_class])}`
    - Attempt: `#{attempt}` (configured retry limit: `#{max_retry_attempts}`)
    - Run ID: `#{metadata_value(metadata[:run_id])}`
    - Session ID: `#{metadata_value(metadata[:session_id])}`
    - Recorded at: `#{DateTime.utc_now(:second) |> DateTime.to_iso8601()}`

    #### Failure

    ```text
    #{error}
    ```
    """
    |> String.trim()
  end

  defp metadata_value(value) when is_binary(value) do
    case String.trim(value) do
      "" -> "n/a"
      normalized -> String.replace(normalized, "`", "'")
    end
  end

  defp metadata_value(nil), do: "n/a"
  defp metadata_value(value), do: value |> to_string() |> String.replace("`", "'")

  defp emit_retry_exhaustion_comment_result(:ok, issue, issue_id, emit_event, state, metadata) do
    Events.emit(emit_event, :warning, :tracker_issue_confusion_recorded, issue, state, %{
      issue_id: issue_id,
      issue_identifier: issue.identifier,
      run_id: metadata[:run_id],
      reason: "retry_exhausted"
    })
  end

  defp emit_retry_exhaustion_comment_result({:error, reason}, issue, issue_id, emit_event, state, metadata) do
    Events.emit(emit_event, :error, :tracker_issue_confusion_record_failed, issue, state, %{
      issue_id: issue_id,
      issue_identifier: issue.identifier,
      run_id: metadata[:run_id],
      reason: "retry_exhausted",
      error: inspect(reason)
    })
  end

  defp emit_retry_exhaustion_comment_result(_result, _issue, _issue_id, _emit_event, _state, _metadata), do: :ok

  defp mark_retry_exhaustion_exception(%Issue{entity_type: "bug"} = issue, issue_id, emit_event, state, metadata, opts) do
    mark_exception = Keyword.get(opts, :mark_ai_workflow_exception)

    case mark_exception do
      mark_exception when is_function(mark_exception, 1) ->
        emit_retry_exhaustion_exception_result(mark_exception.(issue_id), issue, issue_id, emit_event, state, metadata)

      _mark_exception ->
        :ok
    end
  end

  defp mark_retry_exhaustion_exception(_issue, _issue_id, _emit_event, _state, _metadata, _opts), do: :ok

  defp emit_retry_exhaustion_exception_result(:ok, issue, issue_id, emit_event, state, metadata) do
    Events.emit(emit_event, :warning, :tracker_issue_workflow_exception, issue, state, %{
      issue_id: issue_id,
      issue_identifier: issue.identifier,
      run_id: metadata[:run_id],
      reason: "retry_exhausted"
    })
  end

  defp emit_retry_exhaustion_exception_result({:error, reason}, issue, issue_id, emit_event, state, metadata) do
    Events.emit(emit_event, :error, :tracker_issue_workflow_exception_update_failed, issue, state, %{
      issue_id: issue_id,
      issue_identifier: issue.identifier,
      run_id: metadata[:run_id],
      reason: "retry_exhausted",
      error: inspect(reason)
    })
  end

  defp emit_retry_exhaustion_exception_result(_result, _issue, _issue_id, _emit_event, _state, _metadata), do: :ok

  defp find_issue_by_id(issues, issue_id) when is_list(issues) and is_binary(issue_id) do
    Enum.find(issues, fn
      %Issue{id: ^issue_id} ->
        true

      _other ->
        false
    end)
  end

  defp find_issue_by_id(_issues, _issue_id), do: nil

  defp resolve_missing_issue(%Issue{} = issue, _issue_id, _opts), do: issue

  defp resolve_missing_issue(nil, issue_id, opts) when is_binary(issue_id) and is_list(opts) do
    case Keyword.get(opts, :fetch_issue_states_by_ids) do
      fetch_issue_states_by_ids when is_function(fetch_issue_states_by_ids, 1) ->
        case fetch_issue_states_by_ids.([issue_id]) do
          {:ok, issues} when is_list(issues) -> find_issue_by_id(issues, issue_id)
          _other -> nil
        end

      _other ->
        nil
    end
  rescue
    _error -> nil
  catch
    _kind, _reason -> nil
  end

  defp resolve_missing_issue(_issue, _issue_id, _opts), do: nil

  defp cleanup_workspace(cleanup_issue_workspace, identifier, metadata)
       when is_function(cleanup_issue_workspace, 3) and is_binary(identifier) do
    cleanup_issue_workspace.(identifier, metadata[:worker_host], metadata[:workspace_path])
  end

  defp cleanup_workspace(_cleanup_issue_workspace, _identifier, _metadata), do: :ok

  defp retry_release_reason(%Issue{} = issue) do
    if Dispatch.issue_routable_to_worker?(issue), do: "not_active", else: "not_routed"
  end

  defp maybe_cleanup_unrouted_workspace(cleanup_issue_workspace, %Issue{} = issue, metadata) do
    if Dispatch.issue_routable_to_worker?(issue) do
      :ok
    else
      cleanup_workspace(cleanup_issue_workspace, issue.identifier, metadata)
    end
  end

  defp runtime_worker_slots_available?(%{worker_slots_available?: available?})
       when is_boolean(available?),
       do: available?

  defp runtime_worker_slots_available?(_runtime), do: false
end
