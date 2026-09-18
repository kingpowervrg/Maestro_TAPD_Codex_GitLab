defmodule SymphonyElixir.Agent.Runner.RunContextTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Agent.Runner.RunContext
  alias SymphonyElixir.Issue

  test "preserves provider-neutral workspace hook context for an issue attempt" do
    issue = %Issue{
      id: "issue-1",
      identifier: "WORK-1",
      branch_name: "release/next",
      agent_options: %{reasoning_effort: "high"}
    }

    assert RunContext.run_issue_context(issue, "run-1") == %{
             id: "issue-1",
             identifier: "WORK-1",
             run_id: "run-1",
             branch_name: "release/next",
             agent_options: %{reasoning_effort: "high"}
           }
  end
end
