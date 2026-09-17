# Testing

Run independent package tests with the repository-pinned toolchain:

```bash
cd elixir
mise exec -- bash -lc 'cd ../extensions/maestro_tapd_gitlab_lite && mix test'
```

Run integration and disabled-extension coverage from `elixir/`:

```bash
mise exec -- mix test test/symphony_elixir/extension_isolation_test.exs
mise exec -- mix test test/symphony_elixir/extension/tapd_gitlab_lite_integration_test.exs
mise exec -- mix test test/symphony_elixir/tapd_adapter_test.exs
mise exec -- mix test test/symphony_elixir/workflow_templates_test.exs
```

Mode A uses the company policy with `GitlabLiteBackend`. Mode B runs the same
policy test against fake Lite and fake upstream-compatible backends. Mode C
removes all extension registrations and asserts that the Core Git adapter,
template inventory, policies, and automation pack have no Lite behavior.
