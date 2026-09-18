import Config

config :maestro_tapd_gitlab_lite,
  enabled: true,
  core_contract_version: 1

config :symphony_elixir, :workflow_runtime_extensions,
  sources: [
    SymphonyElixir.AssemblyCatalog.WorkflowExtensions,
    MaestroTapdGitlabLite.RegistrySource
  ]

config :symphony_elixir,
  :workflow_runtime_extension_apps,
  [:maestro_tapd_gitlab_lite]

config :symphony_elixir,
  :repo_provider_adapters,
  %{"git" => MaestroTapdGitlabLite.Repo.GitlabLiteBackend}

config :symphony_elixir,
  :workspace_automation_sources,
  [MaestroTapdGitlabLite.RepoBootstrap.AutomationSource]

config :symphony_elixir,
  :issue_policies,
  [MaestroTapdGitlabLite.Tracker.CompanyTapdIssuePolicy]
