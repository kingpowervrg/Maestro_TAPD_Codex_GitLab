defmodule MaestroTapdGitlabLite.ManifestTest do
  use ExUnit.Case, async: true

  alias MaestroTapdGitlabLite.Manifest

  test "publishes stable package identity and Core contract requirement" do
    assert Manifest.metadata() == %{
             id: "maestro.extension.tapd_gitlab_lite",
             version: "0.1.0",
             required_core_contract_version: 1
           }
  end

  test "owns the company TAPD model-level environment binding" do
    template = File.read!("priv/workflow_templates/tapd/git/codex.md")

    assert template =~ "bug_ai_model_level:"
    assert template =~ "field: $TAPD_BUG_AI_MODEL_LEVEL_FIELD"
  end
end
