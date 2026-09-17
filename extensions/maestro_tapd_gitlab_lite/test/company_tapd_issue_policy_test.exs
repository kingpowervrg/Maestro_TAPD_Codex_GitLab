defmodule MaestroTapdGitlabLite.Tracker.CompanyTapdIssuePolicyTest do
  use ExUnit.Case, async: true

  alias MaestroTapdGitlabLite.Tracker.CompanyTapdIssuePolicy, as: Policy

  @workflow_field "custom_field_ai_workflow"
  @model_field "custom_field_ai_model"

  test "accepted Bugs are enriched and dispatchable independently of repository backend" do
    for backend <- [FakeLiteBackend, FakeUpstreamGitlabBackend] do
      tracker = tracker()
      issue = issue()
      raw = %{@workflow_field => "接受/处理", @model_field => "HIGH"}

      assert {:ok, enriched} =
               Policy.enrich_issue(issue, %{
                 tracker: tracker,
                 raw_issue: raw,
                 repo_backend: backend
               })

      assert Policy.evaluate_dispatch(enriched, %{tracker: tracker, repo_backend: backend}) ==
               :allow

      assert enriched.agent_options.reasoning_effort == "high"
    end
  end

  test "missing or non-accepted company fields never dispatch" do
    tracker = tracker()

    for raw <- [%{}, %{@workflow_field => "AI已解决"}] do
      assert {:ok, enriched} = Policy.enrich_issue(issue(), %{tracker: tracker, raw_issue: raw})

      assert {:deny, :company_tapd_policy_not_accepted} =
               Policy.evaluate_dispatch(enriched, %{tracker: tracker})
    end
  end

  defp issue do
    %{
      entity_type: "bug",
      state: "new",
      custom_fields: %{},
      agent_options: %{},
      assigned_to_worker: true
    }
  end

  defp tracker do
    %{
      kind: "tapd",
      provider: %{
        platform: %{
          bug_ai_workflow: %{
            field: @workflow_field,
            accepted_value: "接受/处理",
            resolved_value: "AI已解决",
            exception_value: "AI异常",
            active_states: ["new", "reopened"]
          },
          bug_ai_model_level: %{field: @model_field}
        }
      }
    }
  end
end
