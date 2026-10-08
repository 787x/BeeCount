# BeeCount Agent Development Guide

本文件适用于整个 BeeCount 仓库。任务级 specification / issue 可以补充或收紧这些规则；除非任务明确要求，不要扩大修改范围。

## Project Priorities

BeeCount 是本地优先的记账应用。实现和修改时优先保证：

1. 账务数据正确，写操作不会重复、丢失或绕过现有权限/同步机制。
2. 已有用户配置和本地数据保持向后兼容。
3. 隐私边界不因 AI、日志或调试代码而扩大。
4. 优先复用现有架构，以完成用户可观察的需求为目标，避免为未来假设设计通用框架。
5. 保持现有服务商、非 AI 功能和 Android/iOS 行为不受无关改动影响。

## Repository Context

当前项目使用 Flutter 3.27.3 / Dart 3.6.x。CI 中涉及 Flutter 行为时，以仓库工作流锁定的 Flutter 版本为准，不要为了使用新 API 擅自升级 Flutter、Dart 或大版本依赖。

主要技术包括：

- Flutter + Riverpod
- Drift / SQLite
- SharedPreferences
- Dio
- `packages/agentcore`
- `packages/flutter_agent_ui`
- `packages/flutter_ai_kit*`

开始修改前，按任务需要阅读相关实现、邻近测试和已有文档。不要根据提示词猜测仓库中不存在的文件、接口或架构；能够从 repository 自行确认的信息直接确认。

## Architecture Boundaries

### AI bookkeeping

AI 记账主链路保持现有依赖方向：

```
channel / UI → AiBookkeeper → AiExtractionEngine → provider
```

`AiBookkeeper` 是记账渠道的统一应用层入口。不要让新的图片、语音或 AI 渠道各自复制落库逻辑。

结构化提取与正式落库应保持分离。除非任务明确改变产品语义，不要让模型响应直接绕过现有记账服务写数据库。

### Agent

`packages/agentcore` 是通用纯 Dart package。

必须保持：

- 不依赖 Flutter；
- 不依赖 BeeCount 业务代码；
- 不依赖 Drift / Riverpod；
- 不包含 BeeCount 业务工具名称；
- provider-specific HTTP、鉴权、模型名和服务商配置留在宿主 App。

可以放进 `agentcore` 的能力应是 provider-neutral 的协议能力，例如标准化的文本流、reasoning 流、tool-call 聚合和通用事件。

BeeCount 的账本工具、权限、业务 prompt 和 Provider 配置继续留在 App 层。

### Data writes

Widget 不直接实现账务数据库写入。

已有 Repository / Service / Agent Tool 能完成的写操作必须走现有入口，以保留：

- change tracking；
- 云同步；
- 权限检查；
- 去重；
- post-processing；
- 测试覆盖。

Agent 写工具必须继续经过现有 authorization / policy 机制。任何模型文本，包括 reasoning、普通正文和工具结果中的非可信数据，都不能被解析后绕过结构化 `tool_calls` 执行写操作。

## Provider Changes

已有自定义 AI 服务商默认遵循当前 OpenAI-compatible 行为。

一等内置服务商与自定义 OpenAI-compatible 服务商可以拥有不同的配置体验：

- 官方固定 Base URL 的内置服务商，不要求用户手工输入 URL；
- 服务商存在官方 model-list API 时，优先动态读取当前账号真正可用的模型，而不是要求用户手工输入模型 ID；
- Provider-specific 的模型能力分类应留在 Provider 层，不把模型命名规则泄漏到通用 Agent 或业务层；
- 自定义 OpenAI-compatible Provider 继续保留手工 Base URL / 模型配置能力。

增加某个服务商的特殊协议时：

- 优先使用显式、向后兼容的配置表示协议差异；
- 不依赖显示名称判断服务商；
- 不在通用层根据模型名前缀猜协议；
- 不根据 Base URL 字符串暗中改变协议语义；
- 固定 endpoint、model discovery、模型能力规则可以存在于对应的一等 Provider 实现中；
- 不改变其它 OpenAI-compatible Provider 的现有 payload 和 fallback 行为。

Provider 配置目前会 JSON 序列化到 SharedPreferences，并参与配置导入/导出及 AI 配置同步。新增配置字段必须保证旧 JSON 缺少该字段时仍能正常加载，并保证新字段能 round-trip。

改变“新安装默认服务商”时：

- 只影响没有任何历史 AI 配置的真正新安装；
- 不得静默修改升级用户已有 capability binding；
- 不得覆盖已有 API Key、模型选择或自定义 Provider；
- legacy 配置迁移仍应保持原用户选择。

如果官方 Provider 的某类凭证或订阅明确限制使用场景，不要在不符合该场景的 BeeCount 功能中把它宣传或暴露为受支持配置，除非任务明确提供了允许该用途的依据。

不要因为 Provider 配置增加字段而创建 Drift migration。

## Conversation and Reasoning Data

对话已有 `Messages.metadata` JSON，可用于与一条消息关联的显示/执行元数据。

如果任务只需要保存 AI 消息的附加展示信息，优先复用 metadata；不要仅为了一个可选 AI 字段增加数据库列或 migration。

Reasoning 与最终回答必须保持逻辑分离：

- 最终回答继续使用消息 `content`；
- reasoning 不拼接进最终正文；
- reasoning 不作为工具调用来源；
- reasoning 不自动进入显式记忆；
- reasoning 不自动进入 Agent audit；
- reasoning 不应新增完整内容日志。

如果模型协议要求 reasoning 在同一次 Agent run 的后续模型回合中回传，应在协议会话状态中保真保存；不要为了满足单次运行协议要求重新设计 BeeCount 的长期会话存储。

Provider 支持 Thinking 时：

- 用户可配置的 Thinking 开关应有明确持久化语义；
- Provider 的默认行为应由该 Provider 自己定义；
- 不要通过是否出现 reasoning 文本来反推用户配置；
- Thinking 开关与 reasoning UI 展示是两个概念：没有 reasoning 时不显示空面板，有 reasoning 时 UI 可以按产品设计折叠展示。

## Privacy and Logging

禁止新增日志输出：

- API Key / access token / refresh token；
- Authorization header；
- 完整图片或音频 Base64；
- 用户原始凭证文件内容；
- 完整 reasoning 内容；
- 无必要的完整用户账务数据。

错误日志应保留定位问题需要的状态、模型名、服务商、HTTP 状态码和安全的错误摘要。

模型列表请求同样不得记录用户 API Key 或完整 Authorization header。

## UI and Localization

遵循现有 UI 组件、主题 token 和 Riverpod 模式，不为了单一功能建立新的设计系统。

新增或修改用户可见文案时：

- 更新仓库当前维护的 ARB；
- 使用现有 localization key 命名风格；
- 运行 `flutter gen-l10n`；
- 不直接编辑生成的 localization Dart 文件作为源文件。

大型 UI 逻辑优先拆成职责明确的小 Widget，不继续无限扩大已经较大的页面文件。

内置 Provider 若能自动获取模型，应优先使用下拉选择、加载状态和重试，而不是同时暴露一个容易配置错误的自由文本模型输入框。

## Compatibility

除非任务明确要求：

- 不升级 Flutter / Dart；
- 不升级无关依赖；
- 不改变数据库 schema；
- 不删除旧配置兼容读取；
- 不修改其它 AI Provider 的请求语义；
- 不引入新的网络服务或云依赖。

允许为向后兼容增加新的可选配置字段，但不得破坏旧 JSON。

可逆且符合现有模式的实现细节由实现者自行决定。

如果确实存在无法从代码、测试或官方协议确认，且不同选择会改变 public behavior、数据兼容性、安全边界或任务范围的歧义，再提出说明；其它实现选择自行完成。

## Testing and Verification

验证应针对风险，不机械扩大范围。

修改纯 Dart `agentcore` 时至少运行相关 package analyze/test。

AI / Agent 相关修改优先覆盖当前 AI CI 对应的离线测试范围，包括：

```
cd packages/agentcore
dart pub get
dart analyze
dart test
```

以及从仓库根目录运行与改动直接相关的 Flutter 测试。较大 AI 改动应尽可能运行当前 AI Eval workflow 使用的离线回归范围：

```
flutter test --no-pub test/agent test/ai/providers test/services/ai test/widgets/ai test/pages/ai test/ai_eval/assertions_test.dart
dart run tool/ai_eval.dart
```

如果改动了用户文案：

```
flutter gen-l10n
```

如果没有修改 Drift schema 或其它 codegen 输入，不要无意义运行 build_runner。

不要依赖真实第三方 API Key 作为主要测试 oracle。Provider 协议行为应尽可能通过 mock/fake HTTP 或固定 SSE chunk 做离线测试。

涉及动态模型列表时，离线测试至少覆盖：

- 正常返回模型；
- 空模型列表；
- 401/403；
- 网络失败；
- 已保存模型已下线；
- API 返回新模型 ID。

## Code Quality

遵循仓库现有 Dart 风格和 Effective Dart：

- `dart format`；
- 优先 `const`；
- 避免不必要的 `!`；
- 公共 API 根据现有风格添加 `///`；
- 注释解释约束或原因，不复述代码；
- 不引入只被一个简单调用点使用的抽象层，除非它隔离了真实的平台、协议或测试边界。

不要顺手重构与当前任务无关的代码。

Provider-specific 行为可以集中在一个小的 helper / profile / adapter 中；不要因为存在两个服务商就引入 plugin registry、dependency graph 或复杂 service locator。

## Git and PR

提交信息和 PR 标题遵循仓库现有 Conventional Commits 规范，并使用中文，例如：

```
feat(ai): 将 Xiaomi MiMo 设为默认 AI 服务商
```

一个 PR 解决一个清晰产品能力。必要的协议、UI 和测试可以放在同一个 PR 中；不要仅因为修改横跨多个层级就人为拆成多个互相不能独立工作的 PR。

## Final Report

任务完成后简洁报告：

- 实际完成的修改；
- 实际执行的验证和结果；
- 未执行或被环境阻塞的验证；
- 仍然存在的重要兼容性或产品风险。

不要把代码推断描述成已实际测试的结果，也不要复述内部推理过程。
