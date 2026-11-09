defmodule MaestroTapdGitlabLite.Tracker.PolicyLifecycleTest do
  use ExUnit.Case, async: true

  alias MaestroTapdGitlabLite.Tracker.{CompanyTapdIssuePolicy, PolicyLifecycle}

  @policy_id CompanyTapdIssuePolicy.id()

  test "story completion writes the story workflow field" do
    assert_writes(:complete, "story", "custom_field_38", "status_4", "AI已解决")
  end

  test "bug completion still writes the bug workflow field" do
    assert_writes(:complete, "bug", "custom_field_6", "new", "AI已解决")
  end

  test "story failure writes the story workflow field" do
    assert_writes(:failure, "story", "custom_field_38", "status_4", "AI异常")
  end

  test "story completion does not fall back to the bug workflow field" do
    tracker = tracker("bug", "custom_field_6", "new")
    issue = issue("story", "status_4", "接受/处理")

    assert {:error, :issue_policy_workflow_field_missing} =
             PolicyLifecycle.complete(%{
               tracker: tracker,
               issue: issue,
               update_fields: fn _fields ->
                 flunk("must not update a story through the bug field")
               end,
               fetch_issue: fn -> flunk("must not read back before selecting a story field") end
             })
  end

  defp assert_writes(action, entity_type, field, state, target) do
    parent = self()
    issue = issue(entity_type, state, "接受/处理")

    context = %{
      tracker: tracker(entity_type, field, state),
      issue: issue,
      update_fields: fn fields ->
        send(parent, {:updated_fields, fields})
        :ok
      end,
      fetch_issue: fn ->
        {:ok, put_in(issue, [:custom_fields, @policy_id, "workflow"], target)}
      end
    }

    result =
      case action do
        :complete -> PolicyLifecycle.complete(context)
        :failure -> PolicyLifecycle.handle_failure(context)
      end

    case result do
      {:ok, %{custom_fields: %{"AI特殊工作流" => ^target}}} -> :ok
      :ok -> assert action == :failure
    end

    assert_receive {:updated_fields, %{^field => ^target}}
  end

  defp issue(entity_type, state, workflow) do
    %{
      entity_type: entity_type,
      state: state,
      custom_fields: %{@policy_id => %{"workflow" => workflow}}
    }
  end

  defp tracker(entity_type, field, state) do
    config_key = if entity_type == "story", do: :task_ai_workflow, else: :bug_ai_workflow

    %{
      provider: %{
        platform: %{
          config_key => %{
            field: field,
            active_states: [state],
            accepted_value: "接受/处理",
            resolved_value: "AI已解决",
            exception_value: "AI异常"
          }
        }
      }
    }
  end
end
