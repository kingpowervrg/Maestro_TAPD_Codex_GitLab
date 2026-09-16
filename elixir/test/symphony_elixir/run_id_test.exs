defmodule SymphonyElixir.RunIdTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.RunId

  test "generates distinct run ids with the issue id suffix" do
    first = RunId.generate("issue-123")
    second = RunId.generate("issue-123")

    assert first != second
    assert String.starts_with?(first, "run-")
    assert String.ends_with?(first, "-issue-123")
  end

  test "generates a run id without an issue id" do
    assert RunId.generate() =~ ~r/^run-\d+-[A-Za-z0-9_-]{12}$/
  end
end
