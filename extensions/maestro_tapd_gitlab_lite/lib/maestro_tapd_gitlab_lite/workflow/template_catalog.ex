defmodule MaestroTapdGitlabLite.Workflow.TemplateCatalog do
  @moduledoc "External template contribution for the stable `tapd/git/codex` alias."

  @template_alias "tapd/git/codex"

  @spec entries() :: [term()]
  def entries do
    [
      SymphonyElixir.Workflow.Template.entry!(
        template_alias: @template_alias,
        asset_root: template_root(),
        profile_kind: "coding_pr_delivery",
        profile_version: 1,
        tracker_kind: "tapd",
        repo_provider_kind: "git",
        agent_provider_kind: "codex"
      )
    ]
  end

  @spec template_root() :: Path.t()
  def template_root do
    :maestro_tapd_gitlab_lite
    |> :code.priv_dir()
    |> to_string()
    |> Path.join("workflow_templates")
  end
end
