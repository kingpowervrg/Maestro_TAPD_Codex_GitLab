defmodule MaestroTapdGitlabLite.Tracker.WorkpadCompletionTest do
  use ExUnit.Case, async: true

  alias MaestroTapdGitlabLite.Tracker.WorkpadCompletion

  test "accepts a completed workpad with matching published commit" do
    assert :ok = WorkpadCompletion.validate(body())
    assert :ok = WorkpadCompletion.validate(body() <> "\n### Confusions\n- [x] Historical timeout resolved\n")
  end

  test "rejects unfinished checklists even when handoff is populated" do
    for text <- ["Implement", "Behavior verified", "Targeted checks passed"] do
      assert {:error, {:invalid_arguments, _}} =
               WorkpadCompletion.validate(String.replace(body(), "[x] " <> text, "[ ] " <> text))
    end

    assert {:error, {:invalid_arguments, _}} =
             WorkpadCompletion.validate(body() <> "\n### Confusions\n- [] Not resolved\n")
  end

  test "rejects missing sections, body, and placeholder handoff values" do
    assert {:error, {:invalid_arguments, _}} = WorkpadCompletion.validate(nil)
    assert {:error, {:invalid_arguments, _}} = WorkpadCompletion.validate("only a summary")

    for key <- ~w(repository branch_name commit_sha published_head_sha suggested_mr_title suggested_mr_description) do
      invalid = Regex.replace(~r/^- #{key}:.*$/m, body(), "- #{key}: `pending`")
      assert {:error, {:invalid_arguments, _}} = WorkpadCompletion.validate(invalid)
    end
  end

  test "requires full matching SHAs and rejects duplicate handoff fields" do
    invalid_bodies = [
      String.replace(body(), "- commit_sha: `#{String.duplicate("a", 40)}`", "- commit_sha: abc123"),
      String.replace(body(), "- published_head_sha: `#{String.duplicate("a", 40)}`", "- published_head_sha: #{String.duplicate("b", 40)}"),
      body() <> "\n- branch_name: maestro/other\n",
      body() <> "\n### Plan\n- [ ] Not complete\n"
    ]

    for invalid <- invalid_bodies do
      assert {:error, {:invalid_arguments, _}} = WorkpadCompletion.validate(invalid)
    end
  end

  defp body do
    """
    ## Workpad
    ### Plan
    - [x] Implement
    ### Acceptance Criteria
    - [x] Behavior verified
    ### Validation
    - [x] Targeted checks passed
    ### Git Handoff
    - repository: org/repo
    - branch_name: `maestro/tapd-test`
    - commit_sha: `#{String.duplicate("a", 40)}`
    - published_head_sha: `#{String.duplicate("a", 40)}`
    - suggested_mr_title: Fix duplicate entries
    - suggested_mr_description: Preserve unique entries and ignore duplicates.
    """
  end
end
