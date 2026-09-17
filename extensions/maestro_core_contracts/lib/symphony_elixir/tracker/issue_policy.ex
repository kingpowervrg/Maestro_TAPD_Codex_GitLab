defmodule SymphonyElixir.Tracker.IssuePolicy do
  @moduledoc """
  Platform-neutral lifecycle policy contract for tracker issues.

  Policies enrich normalized issues, decide whether they may be dispatched,
  complete policy-owned state, and safely handle terminal failures. Trackers
  retain ownership of transport; policies retain ownership of business fields.
  """

  alias SymphonyElixir.Issue

  @type context :: map()
  @type decision :: :allow | {:deny, term()}

  @callback id() :: String.t()
  @callback supports?(map()) :: boolean()
  @callback enrich_issue(Issue.t(), context()) :: {:ok, Issue.t()} | {:error, term()}
  @callback evaluate_dispatch(Issue.t(), context()) :: decision()
  @callback complete(context()) :: {:ok, term()} | {:error, term()}
  @callback handle_failure(context()) :: :ok | {:error, term()}
  @callback candidate_scope(String.t(), map()) :: map() | nil

  @optional_callbacks candidate_scope: 2
end
