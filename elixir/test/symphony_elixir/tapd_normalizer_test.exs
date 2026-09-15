defmodule SymphonyElixir.TapdNormalizerTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.Tracker.Tapd.{BugAIWorkflow, Normalizer}

  test "recognizes AI exception workflow value and keeps the Bug out of dispatch" do
    tracker = %{
      "provider" => %{
        "platform" => %{
          "bug_ai_workflow" => %{"field" => "custom_field_6"}
        }
      }
    }

    bug = %{
      "id" => "bug-1",
      "title" => "Interrupted repair",
      "status" => "reopened",
      "current_owner" => "王权;",
      "custom_field_6" => "AI异常"
    }

    issue = Normalizer.normalize_bug(bug, tracker)

    assert BugAIWorkflow.exception?(bug, tracker)
    assert BugAIWorkflow.exception_value(tracker) == "AI异常"
    refute issue.assigned_to_worker
    assert issue.custom_fields["AI特殊工作流"] == "AI异常"
  end

  test "normalizes a TAPD story into the shared issue shape" do
    story = %{
      "id" => "123456",
      "name" => "Implement TAPD adapter",
      "description" => "<p>Add runtime integration</p><p><strong>代码分支：</strong> v24.9.0/battle_royale</p>",
      "priority" => "3",
      "status" => "developing",
      "owner" => "晓菊;",
      "workitem_type_id" => "1153070854001000001",
      "label" => "backend, integration ",
      "blocked_by" => [
        %{"id" => "111", "status" => "planning"},
        "222"
      ],
      "created" => "2026-04-01T10:00:00Z",
      "modified" => "2026-04-02T12:30:00Z"
    }

    issue =
      Normalizer.normalize_story(story,
        workspace_url: "https://www.tapd.cn/53000000/prong/stories/view",
        workflow: %{
          workitem_type_id: "1153070854001000001",
          raw_state_by_route_key: %{review: "review"}
        },
        state_phase_map: %{
          "planning" => "todo",
          "developing" => "in_progress",
          "resolved" => "done"
        }
      )

    assert issue.id == "123456"
    assert issue.identifier == "TAPD-123456"
    assert issue.title == "Implement TAPD adapter"

    assert issue.description ==
             "<p>Add runtime integration</p><p><strong>代码分支：</strong> v24.9.0/battle_royale</p>"

    assert issue.branch_name == "v24.9.0/battle_royale"
    assert issue.priority == 3
    assert issue.state == "developing"
    assert issue.lifecycle_phase == "in_progress"
    assert issue.workitem_type_id == "1153070854001000001"
    assert issue.url == "https://www.tapd.cn/53000000/prong/stories/view"
    assert issue.assignee_id == "晓菊"
    assert issue.labels == ["backend", "integration"]
    assert issue.workflow[:raw_state_by_route_key][:review] == "review"

    assert issue.blocked_by == [
             %{id: "111", identifier: "TAPD-111", state: "planning", lifecycle_phase: "todo"},
             %{id: "222", identifier: "TAPD-222", state: nil, lifecycle_phase: nil}
           ]

    assert issue.assigned_to_worker
    assert issue.created_at == ~U[2026-04-01 10:00:00Z]
    assert issue.updated_at == ~U[2026-04-02 12:30:00Z]
  end

  test "ignores invalid or absent TAPD code branch metadata" do
    invalid =
      Normalizer.normalize_story(%{
        "id" => "1",
        "name" => "Invalid branch",
        "description" => "代码分支： feature/../unsafe"
      })

    absent =
      Normalizer.normalize_story(%{
        "id" => "2",
        "name" => "No branch",
        "description" => "普通需求描述"
      })

    assert invalid.branch_name == nil
    assert absent.branch_name == nil
  end

  test "routes a TAPD story only to its configured assignee" do
    matching_filter = %{match_values: MapSet.new(["王权"])}

    matching_issue =
      Normalizer.normalize_story(
        %{"id" => "1", "name" => "Mine", "status" => "developing", "owner" => "晓菊; 王权;"},
        assignee_filter: matching_filter
      )

    other_issue =
      Normalizer.normalize_story(
        %{"id" => "2", "name" => "Other", "status" => "developing", "owner" => "晓菊;"},
        assignee_filter: matching_filter
      )

    unassigned_issue =
      Normalizer.normalize_story(
        %{"id" => "3", "name" => "Unassigned", "status" => "developing"},
        assignee_filter: matching_filter
      )

    assert matching_issue.assignee_id == "晓菊;王权"
    assert matching_issue.assigned_to_worker
    refute other_issue.assigned_to_worker
    refute unassigned_issue.assigned_to_worker
  end

  test "merges raw blockers with relation-derived blockers without duplicates" do
    story = %{
      "id" => "123456",
      "name" => "Implement TAPD adapter",
      "status" => "developing",
      "blocked_by" => [
        %{"id" => "111", "status" => "planning"}
      ]
    }

    issue =
      Normalizer.normalize_story(story,
        state_phase_map: %{
          "planning" => "todo",
          "resolved" => "done"
        },
        blocked_by: [
          %{id: "111", identifier: "TAPD-111", state: "planning", lifecycle_phase: "todo"},
          %{id: "222", identifier: "TAPD-222", state: "resolved", lifecycle_phase: "done"}
        ]
      )

    assert issue.blocked_by == [
             %{id: "111", identifier: "TAPD-111", state: "planning", lifecycle_phase: "todo"},
             %{id: "222", identifier: "TAPD-222", state: "resolved", lifecycle_phase: "done"}
           ]
  end
end
