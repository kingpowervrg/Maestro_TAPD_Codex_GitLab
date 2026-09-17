# TAPD + GitLab Lite 独立扩展与上游同步计划

- 状态：Proposed
- 创建日期：2026-09-16
- 对比基线：本地原始项目 `Maestro` 的 `33c970b`
- 当前实现：`Maestro_TAPD_Codex_GitLab` 的 `337d5b1`
- 关联计划：[`gitlab_repo_provider_lite.zh-CN.md`](./gitlab_repo_provider_lite.zh-CN.md)
- 适用范围：Maestro Elixir Runtime

## 1. Problem Statement

当前项目从本地原始项目 `/home/admin2/workspace_other/Maestro` 派生，在原有 TAPD + GitHub 完整流程之外增加了 TAPD + GitLab Lite。Lite 使用 Git SSH 完成代码写入，只通过 GitLab HTTP API 执行受控的只读 blob 搜索，MR、评审、Pipeline、审批和合并仍由人工处理。

现有实现不是一个独立的小型 Adapter：它同时修改了 Repo、Repo Provider、TAPD、Agent、Orchestrator、Workspace、工作流模板和部署脚本。若继续以这种形态开发，每次同步上游都需要在大量通用文件中辨认和重放本地逻辑，升级成本和回归风险会持续增长。

本计划将 TAPD + GitLab Lite 重构为独立 OTP 扩展应用，并把 Maestro 核心中的剩余修改收敛为少量、稳定、与具体业务无关的扩展接口，使原始 TAPD + GitHub 与新增 TAPD + GitLab Lite 能够独立演进。

## 2. Current-State Comparison

本节只描述 2026-09-16 本地两个目录的状态，不代表远端仓库的最新状态。

### 2.1 Git 关系

| 项目 | 原始项目 | 当前项目 |
| --- | --- | --- |
| 路径 | `/home/admin2/workspace_other/Maestro` | `/home/admin2/workspace_other/Maestro_TAPD_Codex_GitLab` |
| 分支 | `main` | `main` |
| HEAD | `33c970b` | `337d5b1` |
| Remote | `joosure/Maestro.git` | `kingpowervrg/Maestro_TAPD_Codex_GitLab.git` |
| 提交关系 | 对比基线 | 基线之后直接增加 18 个提交 |

当前项目完整包含原始项目的 `33c970b`，不存在无共同祖先或重新导入代码的问题。因此后续应采用标准 upstream/fork 工作流，不应继续通过复制目录同步。

原始项目工作区另有一个未提交修改：

```text
elixir/test/symphony_elixir/repo_provider/github_test.exs
```

该修改把测试参数 `find_executable` 改为 `executable_finder`，内容与当前项目已经提交的版本相同。开始升级或重构前，必须先在原始目录中提交、暂存或明确丢弃该修改，禁止直接覆盖。

### 2.2 差异规模

从 `33c970b` 到 `337d5b1`：

| 区域 | 文件数 | 新增 | 删除 |
| --- | ---: | ---: | ---: |
| Runtime | 73 | 2660 | 171 |
| Tests | 28 | 2214 | 57 |
| 模板与 workspace automation | 10 | 469 | 5 |
| 文档 | 12 | 1101 | 10 |
| 启停脚本 | 3 | 387 | 0 |
| 根配置及其他文件 | 7 | 98 | 10 |
| **合计** | **133** | **6929** | **253** |

文件状态为 25 个新增、108 个修改。当前功能已跨越多个通用边界，不能仅通过移动新增文件实现隔离。

### 2.3 当前功能组成

1. **Git/GitLab Lite**
   - Git-only Repo Adapter。
   - GitLab 只读 blob 搜索。
   - Sparse checkout、共享 object cache 和大仓库准备。
   - checkout、diff、commit、push 和远端 SHA 校验。
2. **TAPD Bug 定制**
   - Bug 候选筛选。
   - `AI特殊工作流` 成功/异常闭环。
   - `AI模型等级` 到 Codex reasoning effort 的映射。
   - Confusions 检查、返工轮次和最终 workpad。
3. **工作流模板**
   - `tapd/git/codex` 模板。
   - Git-only 权限、工具、workpad 和执行生命周期 partial。
4. **通用 Runtime 改动**
   - Worker 异常收尾和重试抑制。
   - Run ID、workspace 清理和发布 SHA 健壮性。
   - Codex model/effort 透传。
5. **部署与运维**
   - start/restart/stop 脚本。
   - 环境变量、部署文档、secret scan 和验证记录。

### 2.4 设计驱动因素与资产寿命

本次分离不是为了长期维护一套与上游竞争的 GitLab Provider，而是由以下三个现实需求驱动：

1. **上游当前尚未实现 GitLab 支持**：现阶段必须自研 GitLab Lite，才能让 TAPD 工作项在私有 GitLab 大仓库中完成代码交付。
2. **公司 TAPD 工作流具有长期差异**：不同公司的 Bug/Story 字段、状态和值域不同，需要通过附加字段实现 AI opt-in、完成和异常闭环，同时不得破坏历史工作项及原有工作流。
3. **未来优先采用上游 GitLab 实现**：上游提供正式 GitLab Provider 后，应以它为主，只保留公司 TAPD Policy 和上游未覆盖的少量差异。

因此必须把当前功能拆成不同寿命的三类资产：

| 资产 | 定位 | 上游支持 GitLab 后 |
| --- | --- | --- |
| 公司 TAPD AI Policy | 长期业务扩展 | 继续保留，与 Repo Provider 解耦 |
| GitLab Lite Backend/Search | 临时兼容实现 | 优先替换或删除，采用上游 Provider |
| Object cache/大仓库策略 | 公司运维优化 | 复用上游 hook；如上游等价覆盖则删除 |

核心原则：**长期维护公司 TAPD AI Policy，短期维护 GitLab Lite Backend；未来替换 Backend 时，Policy 不动。**

## 3. Goals

1. **隔离业务实现**：至少 90% 的 TAPD + GitLab Lite 专属代码、模板、测试、脚本和文档位于一个独立扩展目录。
2. **保护原始功能**：禁用扩展后，原有 TAPD + GitHub 的配置、工具集合、生命周期和测试行为与上游一致。
3. **缩小升级冲突面**：Maestro 核心只保留通用扩展接口和一个装配入口，业务字段名、GitLab API 细节及 Lite 生命周期不得散落在核心模块中。
4. **保持行为兼容**：迁移前后 `tapd/git/codex` 的候选筛选、远程搜索、稀疏展开、commit、verified push、workpad、`AI已解决` 和 `AI异常` 语义不变。
5. **建立可重复升级流程**：后续上游升级通过 Git remote、merge 分支和三模式测试完成，不再依赖目录复制或人工逐文件比对。
6. **约束后续 Agent 开发**：新增项目级 Agent Rule，向后续 Agent 明确 Core/Extension 边界，并要求 TAPD + GitLab Lite 的新增实现默认进入独立扩展目录。
7. **支持未来替换 Backend**：上游正式 GitLab Provider 到来时，主要通过注册和配置切换完成迁移，公司 TAPD Policy 不重写。

## 4. Non-Goals

1. **不实现完整 GitLab Provider**：本计划不增加自动 MR、评论、Pipeline、审批或合并。
2. **不改变 Lite 产品边界**：仍采用 Git SSH 写入和唯一只读 GitLab blob 搜索 API。
3. **不在迁移时重写业务规则**：TAPD Bug 字段、Confusions、返工和 workpad 行为先等价迁移；产品规则优化另立计划。
4. **不把整个 Maestro 改成 umbrella**：优先采用独立 path dependency/OTP application，避免为了目录隔离进行大规模构建系统重构。
5. **不承诺零核心改动**：当前核心尚缺少 Tracker、Dynamic Tool、模板和终止生命周期扩展点；需要一次性增加少量通用接口。
6. **不把外部扩展继续放入核心 namespace**：不新增 `SymphonyElixir.Workflow.Extensions.TapdGitlabLite`，也不把插件资源继续放入核心 `priv/workflow_extensions/`。

## 5. Target Architecture

### 5.1 推荐目录

```text
extensions/
└── maestro_tapd_gitlab_lite/
    ├── AGENTS.md
    ├── mix.exs
    ├── README.md
    ├── config/
    │   └── config.exs
    ├── lib/
    │   └── maestro_tapd_gitlab_lite/
    │       ├── application.ex
    │       ├── manifest.ex
    │       ├── registry_source.ex
    │       ├── host_adapters/
    │       ├── repo/
    │       │   ├── backend.ex
    │       │   ├── gitlab_lite_backend.ex
    │       │   ├── gitlab_code_search.ex
    │       │   └── remote_search_tool.ex
    │       ├── repo_bootstrap/
    │       │   ├── policy.ex
    │       │   ├── object_cache.ex
    │       │   └── clone_plan.ex
    │       ├── tracker/
    │       │   ├── issue_policy.ex
    │       │   ├── bug_ai_workflow.ex
    │       │   ├── bug_ai_model_level.ex
    │       │   ├── candidate_policy.ex
    │       │   ├── completion_policy.ex
    │       │   └── failure_policy.ex
    │       └── workflow/
    │           ├── capability_gate.ex
    │           ├── terminal_outcome.ex
    │           └── template_catalog.ex
    ├── priv/
    │   ├── workflow_templates/
    │   │   └── tapd/git/codex.md
    │   ├── workflow_partials/
    │   └── workspace_automation/
    │       └── repo-object-cache
    ├── bin/
    │   ├── start
    │   ├── restart
    │   └── stop
    ├── docs/
    └── test/
```

扩展使用独立的 `MaestroTapdGitlabLite.*` namespace，并作为独立 OTP application 编译。Maestro Runtime 通过 registry/source 接口发现扩展，而不是直接调用其具体模块。

### 5.2 依赖方向

```text
Maestro Core contracts/facades
             ↑
             │ depends on stable public contracts
             │
MaestroTapdGitlabLite extension
             │
             ├── Company TAPD IssuePolicy     # 长期保留
             ├── GitLab Lite Backend/Search   # 临时实现
             ├── Repository Bootstrap Policy  # 按需保留
             └── workflow/deployment assets
```

约束：

- Core 不得编译依赖 `MaestroTapdGitlabLite.*` 具体业务模块。
- 扩展只能通过稳定 facade、behaviour、registry source 或显式 Host Adapter 调用 Core。
- 业务规则模块优先接收依赖注入，不直接读取 Orchestrator 内部 state。
- 模板和 workspace automation 从扩展自己的 OTP `priv` 目录加载。
- TAPD Policy 只能依赖 Repo facade/capability，不能引用 GitLab Lite 具体模块。
- GitLab Lite 和未来上游 GitLab Provider 必须能在不修改 TAPD Policy 的情况下互换。

### 5.3 Core 保留内容

以下能力若确认具有通用价值，可保留在 Maestro Core：

- 通用 Git sparse checkout 原语和安全路径校验。
- 通用合法 Git object id/remote ref 解析。
- 通用 Run ID 唯一性修复。
- 通用 Codex model/effort 传递能力。
- 通用最大重试次数和终止结果协议。
- Extension registry、template source、dynamic tool source 和 lifecycle callback 合约。
- 一个统一的平台中性 `IssuePolicy` contract，用于 enrichment、派发决策、完成和失败处理。
- 必要时提供平台中性的 repository bootstrap contract；具体 object-cache 策略不进入 Core。

这些能力必须使用平台中性命名，不能引用 `GitLab`、`AI特殊工作流`、`tapd_git_codex` 或目标仓库信息。

### 5.4 必须迁入扩展的内容

- GitLab API URL、project id、token 和 blob search 响应解析。
- Git-only Repo Adapter 的 Lite 配置。
- TAPD `AI特殊工作流`、`AI模型等级` 和字段值映射。
- Bug 候选筛选、Confusions、返工和完成/异常策略。
- `tapd/git/codex` 模板及专属 partial。
- GitLab Lite capability gate。
- object cache 的产品配置和启动脚本。
- GitLab Lite 专属测试、运维文档和灰度记录。

### 5.5 三项工程决策

#### 5.5.1 TAPD：使用统一 IssuePolicy，不包装完整 Adapter

Core 增加一个平台中性的 `IssuePolicy` 扩展接口，公司 TAPD AI 工作流作为独立 Policy 实现。Policy 至少覆盖以下四个生命周期：

```text
enrich_issue      读取并规范化扩展字段
evaluate_dispatch 判断工作项是否允许派发
complete          成功后的字段回写与回读确认
handle_failure    阻塞或异常后的安全收尾
```

Core 负责固定调用时机、统一结果和错误处理；扩展负责 `AI特殊工作流`、`AI模型等级`、Confusions、返工和公司字段值语义。没有注册 Policy 时，原 TAPD Adapter 行为必须保持不变。

不包装完整 TAPD Adapter，避免复制全部 Adapter 接口、依赖内部实现，以及在上游 TAPD Adapter 增加方法时持续维护机械转发代码。

公司字段必须配置化，不能把 TAPD `custom_field_*` 编号写死在代码中：

```yaml
company_tapd_ai:
  enabled: true
  bug:
    active_states: [new, reopened]
    ai_workflow:
      field: $TAPD_BUG_AI_WORKFLOW_FIELD
      accepted_value: 接受/处理
      resolved_value: AI已解决
      exception_value: AI异常
    model_level:
      field: $TAPD_BUG_AI_MODEL_LEVEL_FIELD
  story:
    # Story 使用独立配置，不默认继承 Bug 字段和值域。
```

缺少扩展字段、字段不是接受值或未启用公司 Policy 的历史工作项必须保持原行为，不得被新 AI 流程派发或改写。

#### 5.5.2 交付：第一阶段使用同仓 path dependency

第一阶段采用同仓独立 Mix project：

```elixir
{:maestro_tapd_gitlab_lite,
 path: "../extensions/maestro_tapd_gitlab_lite"}
```

这只是代码来源和交付方式，不影响运行时 contract。扩展从第一天起必须具备独立 OTP application、namespace、`mix.exs`、`priv`、测试和版本；不得因为使用 path dependency 而直接调用 Core 私有模块。Contract 稳定后可以切换为 Git dependency，业务代码不应随之修改。

#### 5.5.3 Object cache：实现与策略先留在扩展

Object cache 当前由约 146 GB 的特定仓库需求驱动，尚无证据表明 GitHub/CNB 也需要完全相同的实现。因此第一阶段把 object-cache helper、配置、锁、cache key、clone 参数和清理策略留在扩展。

Core 只在迁移确有需要时提供平台中性的 repository bootstrap contract 或安全 Git 原语，并且不得读取 `SYMPHONY_GIT_OBJECT_CACHE_ROOT`。出现第二个 Provider 使用者，或者上游提供等价机制后，再决定复用、上移或删除；不提前把具体 helper 并入 Core。

### 5.6 上游 GitLab 替换策略

GitLab Lite 必须实现为可替换 Backend，而不是公司 TAPD Policy 的组成部分：

```text
Company TAPD IssuePolicy
           │
           ▼
Repo facade/capabilities
           │
           ├── 当前：GitLab Lite Backend
           └── 未来：Upstream GitLab Provider
```

上游 GitLab Provider 到来后的迁移顺序：

1. 建立 clone/fetch、checkout、search、commit/push、MR、review、pipeline 和 merge 能力矩阵。
2. 先接入上游 Provider，保持公司 TAPD Policy 和字段语义不变。
3. 用既有成功、异常、Story 和历史工作项场景验证上游 Backend。
4. 删除已被上游覆盖的 Lite 实现。
5. 上游未覆盖的大仓库策略通过其公开 hook 接入；若上游已经等价覆盖，则删除本地实现。
6. 保留一个灰度周期的兼容开关，然后删除旧 Backend 和旧配置。

禁止在同一个提交中同时接入上游 Provider、修改 TAPD 字段语义、修改 object cache 和调整工作项状态流转。

### 5.7 Agent Rule

新建一份覆盖 TAPD + GitLab Lite 开发的 `AGENTS.md`。推荐将详细规则放在：

```text
extensions/maestro_tapd_gitlab_lite/AGENTS.md
```

同时在项目级 Agent 指引中增加一个简短入口，告知 Agent 所有 TAPD + GitLab Lite 工作必须先阅读上述规则。若仓库根目录尚无适合的项目级 `AGENTS.md`，则新增根级文件；若已有上级规则，则只增加最小导航和 Core 保护条款，避免复制通用规则。

该 Agent Rule 至少必须说明：

1. **目录所有权**：GitLab API、TAPD AI 字段、Lite workflow、模板、脚本、测试和文档默认只能新增在 `extensions/maestro_tapd_gitlab_lite/`。
2. **Core 保护**：不得为了单一 Lite 需求直接修改 Core 业务逻辑；确需修改时，必须先证明这是平台中性的扩展能力，并将改动限制为 behaviour、registry、facade、hook 或 contract。
3. **依赖方向**：Core 不得引用 `MaestroTapdGitlabLite.*`；扩展通过公开 contract 或 `host_adapters/` 使用 Core。
4. **禁止硬编码**：Core 中不得新增 `GitLab`、`GITLAB_API_TOKEN`、`AI特殊工作流`、`AI模型等级`、`tapd_git_codex` 等 Lite 专属判断或字符串。
5. **变更归类**：Agent 开始实现前必须把拟修改文件归类为 `CORE-GENERIC`、`PLUGIN` 或 `INTEGRATION-SEAM`；无法归类时先停止扩大修改面。
6. **测试要求**：扩展改动必须运行 Lite 定向测试；涉及 Core 扩展接口时，还必须在禁用扩展的模式下验证原 TAPD + GitHub。
7. **文档同步**：配置、模板、工具 inventory 或生命周期变化必须同步扩展目录内文档；只有通用 contract 变化才更新 Core 文档。
8. **升级友好**：禁止无关 Core 重构、全仓格式化或把 Core 与扩展迁移混进同一提交。

Agent Rule 应提供一个提交前检查清单：

```text
- [ ] 本次 Lite 业务代码均位于独立扩展目录
- [ ] Core 改动是平台中性的最小扩展接口
- [ ] Core 未新增 Lite 专属字符串或条件分支
- [ ] 禁用扩展时 TAPD + GitHub 仍通过
- [ ] 启用扩展时 TAPD + GitLab Lite 定向测试通过
- [ ] 文档、模板和工具 inventory 已同步
```

验收时需要安排一次“新 Agent 冷启动验证”：由未参与重构、只读取仓库 Agent Rule 和任务描述的 Agent 完成一个小型 Lite 改动，确认其能把代码放入正确目录且不会误改 Core。

## 6. User Stories

### 上游同步维护者

- 作为维护者，我希望直接 merge `upstream/main`，使冲突主要集中在少量扩展接口和装配文件，而不是散布在百余个文件中。
- 作为维护者，我希望通过 `git diff upstream/main...HEAD` 清楚区分通用 Core 改动和 GitLab Lite 业务代码。
- 作为维护者，我希望禁用扩展后运行原始测试，以快速判断问题来自上游还是本地功能。

### Maestro 操作者

- 作为操作者，我希望继续使用现有 `tapd/git/codex` 别名和环境变量启动流程，迁移不改变日常操作。
- 作为操作者，我希望扩展缺失或配置不完整时启动即失败，而不是任务执行中途才发现工具不可用。

### 原始 TAPD + GitHub 用户

- 作为原始功能用户，我希望 GitLab Lite 的安装、禁用或升级不改变 TAPD + GitHub 的工具、状态流转和交付方式。

### 扩展开发者

- 作为扩展开发者，我希望业务代码、模板、测试和部署资源集中在一个目录，并通过稳定接口使用 Maestro 能力。

## 7. Requirements

### 7.1 Must-Have（P0）

#### P0-1：建立可审计基线

- [ ] 保存 `33c970b..337d5b1` 的提交、文件和行为差异清单。
- [ ] 处理原始工作区的未提交 GitHub 测试修改。
- [ ] 在重构前保存核心模式和 GitLab Lite 模式的测试结果。
- [ ] 为两个已验证真实 Bug 的交付信息保留脱敏回归记录。

验收：任何迁移后的行为都能追溯到原实现、明确的新扩展接口或已批准的行为修复。

#### P0-2：通用扩展接口

- [ ] Repo Provider Adapter 继续支持通过配置注册。
- [ ] Dynamic Tool 支持由外部 OTP application 贡献工具定义和执行器。
- [ ] Core 提供一个统一、平台中性的 `IssuePolicy` contract，覆盖 enrichment、派发决策、完成和失败处理。
- [ ] 未注册 `IssuePolicy` 时，原 TAPD Adapter 行为不变。
- [ ] Workflow Template Catalog 支持从外部 OTP `priv` 目录发现模板。
- [ ] Worker 终止路径支持通用 terminal outcome callback，不直接判断 TAPD 自定义字段。
- [ ] 如迁移需要，Workspace 只增加平台中性的 repository bootstrap policy/hook，不直接实现 Lite object cache 策略。

验收：Core 扩展机制测试使用中性 fake extension，不依赖 GitLab Lite 模块。

#### P0-3：独立 OTP 扩展

- [ ] 创建 `extensions/maestro_tapd_gitlab_lite` Mix project。
- [ ] 使用独立 application 名和 module namespace。
- [ ] 扩展 manifest 声明 id、版本和所需 Core contract version。
- [ ] 扩展通过 source/catalog 注册 Repo、Tracker、Tool 和 Template 能力。
- [ ] 第一阶段通过同仓 path dependency 装配，禁止直接依赖 Core 私有模块。
- [ ] Core 只通过 behaviour/facade 调用扩展。

验收：扩展目录可以独立编译和运行单元测试；移除装配配置后 Core 仍可编译。

#### P0-4：业务代码等价迁移

- [ ] 迁移 GitLab blob search、参数校验、结果规范化和 token 脱敏。
- [ ] 将 GitLab Lite 迁移为可替换 Repo Backend，并且不被 TAPD Policy 直接引用。
- [ ] 将 TAPD Bug AI workflow、model level、候选筛选和完成工具迁移为长期 `IssuePolicy`。
- [ ] 迁移 Confusions、异常收尾、返工轮次和 final workpad 规则。
- [ ] 迁移 `tapd/git/codex` 模板和 partial。
- [ ] 将 object-cache helper、配置和启用策略迁入扩展的 `repo_bootstrap/`。
- [ ] 保留原模板别名和必要环境变量兼容层。

验收：迁移前后的工具 inventory、配置错误、成功结果和失败结果一致。

#### P0-5：Core 去业务化

- [ ] Core 通用模块中不再包含 `AI特殊工作流`、`AI模型等级` 等客户字段名。
- [ ] Core Orchestrator 中不再包含 `tapd_git_codex` 专属分支。
- [ ] Core Repo Tool Executor 中不直接依赖 GitLab CodeSearch 实现。
- [ ] Core Template Catalog 不硬编码 `tapd/git/codex` 条目。
- [ ] Core 默认运行不要求 GitLab token 或 Lite 扩展配置。

验收命令示例：

```bash
rg -n "AI特殊工作流|AI模型等级|tapd_git_codex|GITLAB_API_TOKEN" elixir/lib
```

除兼容边界或明确批准的通用配置声明外，结果应为空。

#### P0-6：三模式回归验证

- [ ] 未启用扩展时，原 TAPD + GitHub 测试和模板 inventory 通过。
- [ ] 启用扩展时，TAPD + GitLab Lite 定向测试通过。
- [ ] `tapd/git/codex` Repo inventory 精确包含预期工具，不包含 MR/review/checks/merge 工具。
- [ ] GitLab token 不出现在 Agent shell、tool schema、tool result、错误日志或测试快照中。
- [ ] `make all` 和 `make secret-scan` 通过。

#### P0-7：升级演练

- [ ] 增加 `upstream` remote 并保留当前 fork 为 `origin`。
- [ ] 从当时最新 `upstream/main` 创建升级分支并执行一次真实 merge 演练。
- [ ] 记录冲突文件、解决方式和测试结果。
- [ ] 确认插件内部文件不会因普通上游升级产生冲突。

验收：升级冲突仅允许出现在通用扩展接口、依赖装配、配置或 lockfile 等少量白名单文件。

#### P0-8：Agent Rule 与边界守护

- [ ] 新建 `extensions/maestro_tapd_gitlab_lite/AGENTS.md`，完整描述分离后的目录结构和所有权。
- [ ] 在项目级 Agent 指引中增加到扩展规则的入口以及“Lite 开发不得直接进入 Core”的保护条款。
- [ ] Rule 明确允许修改 Core 的条件、禁止的 Lite 硬编码和三模式测试要求。
- [ ] Rule 包含提交前边界检查清单和常用验证命令。
- [ ] 使用一个小型模拟需求执行新 Agent 冷启动验证。

验收：新 Agent 仅根据仓库规则即可识别正确开发目录；除非任务明确需要通用扩展接口，否则不会修改 Core 文件。

#### P0-9：上游 Provider 可替换性

- [ ] TAPD `IssuePolicy` 测试使用 Repo facade/fake backend，不依赖 GitLab Lite 具体模块。
- [ ] GitLab Lite Backend 和模拟上游 GitLab Backend 通过同一组最小 Repo contract tests。
- [ ] 支持通过注册或配置选择 Repo Backend，不在 TAPD 业务代码中按 provider 名称分支。
- [ ] 建立上游 GitLab 能力矩阵和删除 Lite 重复能力的迁移模板。
- [ ] Object cache 可以接入替代 Backend，或在上游等价覆盖时整体关闭。

验收：将 Repo Backend 从 GitLab Lite 切换到 fake upstream backend 后，公司 TAPD Policy 测试无需修改。

### 7.2 Nice-to-Have（P1）

- [ ] 为扩展增加独立 CI job 和测试报告。
- [ ] 增加 Core/Extension contract compatibility check。
- [ ] 扩展模板别名和工具 inventory 生成快照。
- [ ] 增加升级冲突文件数和 Core delta 文件数检查。
- [ ] 将通用 Core 改动整理成可向上游提交的独立 PR。
- [ ] 为部署包增加明确的 `lite_extension_enabled` 状态输出。

### 7.3 Future Considerations（P2）

- [ ] 将扩展拆为独立 Git 仓库并通过 Git dependency 发布。
- [ ] 为外部模板、Dynamic Tool 和 lifecycle hook 定义版本化 manifest schema。
- [ ] 支持多个外部扩展并存及能力冲突诊断。
- [ ] 如果未来需要完整 GitLab MR 能力，建立新的 Full Provider 扩展，不扩大 Lite 扩展职责。

## 8. Migration Plan

### Phase 0：冻结与基线（预计 0.5—1 天）

1. 处理原始工作区未提交修改。
2. 添加 upstream remote，建立 baseline tag。
3. 保存当前差异清单和测试结果。
4. 冻结新的 GitLab Lite 功能开发，迁移期间只接受阻塞性修复。

退出条件：基线可重复、工作区干净、现有行为有测试记录。

### Phase 1：分类与 Characterization Tests（预计 1—2 天）

1. 给 133 个差异文件标记 `CORE-GENERIC`、`PLUGIN` 或 `INTEGRATION-SEAM`。
2. 为当前工具 inventory、候选筛选、字段闭环、终止路径和模板渲染补 characterization tests。
3. 明确哪些通用改动应保留，哪些必须回收到扩展。

退出条件：每一项现有行为都有所有者和目标位置。

### Phase 2：先分离长期 TAPD Policy（预计 3—5 天）

1. 外部 Dynamic Tool source。
2. 外部 Template Catalog source。
3. 增加一个统一 `IssuePolicy` contract，不包装整个 TAPD Adapter。
4. 将字段 enrichment、候选筛选、成功完成和失败收尾迁入公司 Policy。
5. 将字段编号、接受值、完成值、异常值、活动状态和 Story/Bug 差异配置化。
6. 使用 fake Repo backend 验证 Policy 不依赖 GitLab Lite。

退出条件：禁用 Policy 时原 TAPD 行为不变；启用 Policy 时公司 AI 工作流通过，并且 Policy 不引用 GitLab Lite 模块。

### Phase 3：把 GitLab Lite 收缩为临时 Backend（预计 3—5 天）

迁移顺序：

1. 定义最小 Repo backend/capability contract。
2. 迁移 Git-only Adapter 和 GitLab code search。
3. 移除 TAPD Policy 对 GitLab Lite 具体模块的引用。
4. 用 fake upstream backend 运行相同 TAPD Policy 测试。
5. 保持 Lite 不实现 MR、review、pipeline、approval 和 merge。

每一步先复制到新边界、切换注册、验证，再删除旧实现，避免一次性大搬迁。

退出条件：Repo Backend 可以通过注册替换；更换 Backend 不改变公司 TAPD Policy。

### Phase 4：分离大仓库 Bootstrap 策略（预计 2—3 天）

1. 把 object-cache helper、锁、cache key、clone 参数和清理策略迁入扩展。
2. Core 仅在必要时提供平台中性的 repository bootstrap contract 或安全 Git 原语。
3. 验证禁用扩展时 Core 不创建 object cache，也不读取其环境变量。
4. 验证 cache policy 可以作用于 fake upstream backend。

退出条件：Object cache 是可选扩展策略，不是 Core 默认行为，也不与 GitLab Lite 实现硬绑定。

### Phase 5：完成独立 OTP 应用并收缩 Core Delta（预计 3—5 天）

1. 以同仓 path dependency 装配独立 Mix project/OTP application。
2. 迁移 Workflow capability gate、模板、partial、启停脚本、环境配置和文档。
3. 新建扩展级 Agent Rule，并在项目级指引中增加导航和 Core 保护条款。
4. 删除 Core 中所有 Lite 特判和硬编码模板条目。
5. 将通用改动拆分为可独立审查的提交。
6. 检查 Core 与 upstream 的剩余差异。
7. 运行 Agent Rule 中的边界扫描，确认 Core 未残留或新增 Lite 专属实现。

退出条件：Lite 业务路径全部由独立 OTP application 提供；Core 只剩通用扩展接口、通用修复和薄装配。

### Phase 6：三模式验证与灰度（预计 2—4 天）

1. Mode A：公司 TAPD Policy + GitLab Lite Backend。
2. Mode B：公司 TAPD Policy + fake upstream GitLab Backend。
3. Mode C：原始 TAPD + GitHub，不加载公司 Policy。
4. 重放本地 bare Git smoke。
5. 在授权测试工作项上验证 Bug 成功、Bug 异常、历史工作项和 Story 成功路径。
6. 运行全量测试、Dialyzer 和 secret scan。
7. 保持单并发灰度，观察 workspace 清理、object cache 和重试。

退出条件：P0 验收项全部通过，且现有 Pilot 行为无回归。

### Phase 7：上游升级与 Provider 替换演练（预计 1—2 天）

```bash
git fetch upstream
git switch -c upgrade/maestro-<date>
git merge --no-ff upstream/main
```

依次执行：

1. 解决通用扩展接口和装配文件冲突。
2. 禁用扩展运行上游 Core 测试。
3. 启用扩展运行 Lite 测试。
4. 比较工具 inventory 和模板渲染快照。
5. 用 fake/upstream-compatible Backend 替换 Lite Backend，确认 TAPD Policy 测试不变。
6. 生成上游 GitLab 能力矩阵，标记可删除、需保留和待适配的 Lite 能力。
7. 运行 `make all`、`make secret-scan`。
8. 记录升级耗时与冲突数。

退出条件：形成可重复的升级 runbook。

## 9. Commit and Branch Strategy

### 9.1 Remote

```text
origin    -> kingpowervrg/Maestro_TAPD_Codex_GitLab.git
upstream  -> joosure/Maestro.git
```

### 9.2 分支

- `main`：可运行的发行分支，包含上游 Core、通用扩展点和启用的 Lite 扩展。
- `refactor/tapd-gitlab-lite-extension`：本次隔离重构。
- `upgrade/maestro-<date>`：每次上游升级的临时集成分支。

### 9.3 提交顺序

```text
1. test: characterize existing tapd gitlab lite behavior
2. core: add generic issue policy and extension contracts
3. extension: migrate company tapd ai policy
4. extension: add replaceable gitlab lite backend
5. extension: isolate repository bootstrap and object cache policy
6. extension: add maestro_tapd_gitlab_lite otp app packaging
7. extension: migrate templates and workspace automation
8. core: remove tapd gitlab lite special cases
9. ops/docs: enable and document the extension
```

禁止把 Core 接口、业务迁移和格式化全仓库混在同一个提交中。

## 10. Test Strategy

### Core 模式：扩展禁用

- Repo/Tracker registry contract tests。
- 原有 TAPD + GitHub 模板和工具测试。
- Orchestrator、Worker、Workspace 全量测试。
- 断言不需要 GitLab 环境变量。

### Lite 模式：扩展启用

- GitLab search 请求、响应、路径过滤、超时和脱敏。
- Sparse add、branch checkout、commit、push、published SHA。
- TAPD Story/Bug 候选筛选。
- `AI已解决`、`AI异常`、Confusions 和返工。
- capability gate、tool inventory、模板渲染。
- object cache、workspace cleanup 和启动脚本。

### 三种兼容模式

| 模式 | TAPD 策略 | Repo Backend | 验证目的 |
| --- | --- | --- | --- |
| A | 公司 `IssuePolicy` | GitLab Lite | 当前生产行为 |
| B | 公司 `IssuePolicy` | fake/upstream-compatible GitLab | 证明未来只需替换 Backend |
| C | 原始 TAPD 行为 | GitHub | 证明扩展不影响上游原功能 |

Mode A 和 Mode B 必须共享同一组 TAPD Policy 测试。Mode C 不得要求 GitLab token、object-cache 配置或公司 TAPD 字段。

### 历史工作流保护

- 未启用公司 Policy 时，所有 TAPD 行为与原始实现一致。
- 工作项缺少扩展字段时，不进入公司 AI 流程，也不修改历史状态。
- `AI特殊工作流` 不是接受值时，不派发、不改字段。
- Bug 成功只更新公司 AI 字段，不改变 Bug 原状态。
- 异常写入必须重新确认字段仍为接受值、状态仍允许，不能覆盖人工修改或 `AI已解决`。
- Story 使用独立可配置策略，不默认套用 Bug 字段规则。

### 升级兼容模式

- Core contract version 与 extension manifest 匹配。
- 禁用扩展时 Core 可以独立启动。
- 扩展版本不兼容时 fail-fast 并返回明确错误。
- GitHub Provider 测试不得依赖 GitLab Lite 测试支持代码。

### Agent Rule 验证

- 检查项目级指引能导航到扩展 `AGENTS.md`。
- 检查扩展 Rule 覆盖目录所有权、依赖方向、Core 修改条件和三模式测试。
- 使用模拟 Lite 需求执行一次新 Agent 冷启动验证。
- 检查模拟改动未向 Core 引入 Lite 专属字符串或条件分支。

## 11. Success Metrics

### Leading Indicators

- Lite 专属实现位于扩展目录的比例：成功阈值 ≥ 90%，目标 ≥ 95%。
- Core 中 Lite 专属字段名和条件分支：0。
- 后续 Lite 需求默认落入扩展目录的比例：100%。
- Mode A/B/C 三种模式的必需测试通过率：100%。
- GitLab token 泄漏次数：0。
- `tapd/git/codex` 工具 inventory 偏差：0。
- Lite Backend 替换为 fake upstream backend 后需要修改的 TAPD Policy 测试数：0。

### Lagging Indicators

- 下一次上游升级的人工冲突文件：成功阈值 ≤ 10，目标 ≤ 5。
- 下一次上游升级用于辨认本地业务代码的时间：目标低于半天。
- 因上游升级导致 TAPD + GitHub 回归：0。
- 因上游升级导致已验证 GitLab Lite 成功路径回归：0。

## 12. Risks and Mitigations

| 风险 | 影响 | 缓解措施 |
| --- | --- | --- |
| 现有扩展框架只覆盖部分生命周期 | 业务仍会回流 Core | 先用 fake extension 驱动最小 contract，再迁移业务 |
| 外部模板发现尚不完整 | 仍需改核心硬编码 catalog | 增加 template source registry，并从扩展 OTP `priv` 加载 |
| TAPD Adapter 内部 API 不稳定 | Policy 意外依赖内部模块 | 通过稳定 `IssuePolicy` context/facade 暴露所需数据，禁止包装 Adapter 或调用其私有实现 |
| 上游 GitLab Provider 与 Lite contract 不完全一致 | 切换时需要重写业务流程 | TAPD Policy 只依赖 Repo facade/capability，并提前维护 Mode B contract tests |
| IssuePolicy hook 过多或过细 | Core 形成回调意大利面 | 只保留 enrichment、dispatch、complete、failure 四个生命周期级入口 |
| 迁移同时改变行为 | 无法区分重构回归与产品变化 | Characterization tests 先行，产品改动另立提交/计划 |
| path dependency 修改 `mix.exs`/lockfile | 上游升级仍可能冲突 | 把装配改动限制在一处并保持独立提交 |
| 通用改动与 Lite 改动难以拆分 | Core delta 无法收敛 | 按功能逐项迁移，并为每项指定最终所有者 |
| 真实 GitLab 搜索仍有 5xx/延迟 | 灰度不稳定 | 保持既有 fallback 和单并发，稳定性修复不阻塞结构迁移 |

## 13. Rollback

1. 在迁移完成前保留当前 `337d5b1` 可运行 tag/branch。
2. 每个迁移步骤先注册新实现，再删除旧实现；若失败可恢复旧 registry 配置。
3. 扩展启用失败时，禁用扩展并回到原 TAPD + GitHub Core 模式。
4. 灰度失败时停止 GitLab Lite 服务，不删除已推送远端分支，不回滚人工 MR 操作。
5. 不自动回滚已写入的 `AI已解决` 或 `AI异常`；按审计记录人工处理。
6. 不删除仍被 workspace clone 引用的共享 object cache。

## 14. Engineering Decisions and Open Questions

### Decided

1. **[Engineering] TAPD 扩展方式**：Core 增加一个平台中性的 `IssuePolicy` contract，公司 TAPD AI 工作流作为独立 Policy 实现；不包装完整 TAPD Adapter。Core 不感知公司字段名和值。
2. **[Engineering] OTP 应用交付方式**：第一阶段使用同仓 path dependency，同时保持独立 Mix project、OTP application、namespace、测试和版本。Contract 稳定后可切换为 Git dependency，业务代码不随交付方式改变。
3. **[Engineering] Object cache 所有权**：具体实现、配置和启用策略第一阶段留在扩展；Core 仅在确有需要时提供平台中性的 repository bootstrap contract。出现第二个 Provider 使用者或上游等价能力后，再决定复用、上移或删除。
4. **[Engineering] 上游 GitLab 采用策略**：GitLab Lite 是临时 Backend。上游正式 Provider 到来后，以能力矩阵为依据优先替换 Lite；公司 TAPD Policy 保持不变。

### Non-Blocking Open Questions

1. **[Maintainer]** 通用 Core 改动是否向原始 Maestro 上游提交独立 PR。
2. **[Operations]** 扩展版本是否需要出现在 Dashboard 和 health endpoint。
3. **[Operations]** 独立扩展将来是否采用单独版本号和发布节奏。

## 15. Definition of Done

- [ ] `extensions/maestro_tapd_gitlab_lite` 是独立、可编译、可测试的 OTP application。
- [ ] 禁用扩展后，原 TAPD + GitHub 功能无行为变化。
- [ ] 启用扩展后，GitLab Lite 已验证行为无回归。
- [ ] 公司 TAPD Policy 不引用 GitLab Lite 具体模块，并可在 fake upstream backend 上通过相同测试。
- [ ] 缺少公司字段或未接受 AI 处理的历史工作项不会被派发或修改。
- [ ] GitLab Lite 已明确标记为可替换临时 Backend，没有扩展到 MR、Pipeline、审批或合并。
- [ ] Object cache 实现和启用策略位于扩展，禁用扩展时 Core 不创建或配置 cache。
- [ ] Core 中不存在 Lite 客户字段、GitLab API 或专属终止逻辑。
- [ ] Core 剩余差异均已归类为通用扩展点或通用修复。
- [ ] 已建立项目级导航和扩展级 Agent Rule，后续 Agent 能识别并遵守新目录边界。
- [ ] 新 Agent 冷启动验证通过，模拟 Lite 改动未误改 Core。
- [ ] 全量测试、格式、Lint、Dialyzer 和 secret scan 通过。
- [ ] 完成至少一次真实 upstream merge 演练并形成记录。
- [ ] 升级 runbook 可以由未参与本次重构的维护者按文档执行。
