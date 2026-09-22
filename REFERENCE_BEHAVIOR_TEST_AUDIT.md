# 固定参考行为测试盘点

## 目的与边界

- 固定参考提交为 `91bd24bb8513785c7364cbea29296ff7adafac41`。
- 本文盘点参考前端 `frontend/__tests__` 的 39 个规格测试文件、后端 `backend/__tests__/api/controllers` 的 14 个 controller 规格测试文件，以及 `packages/contracts`、`packages/funbox`、`packages/schemas`、`packages/util` 的 11 个包级规格测试：合计 47 个直接约束用户可见的练习、配置、展示、账户或远端数据行为，17 个只是网页/服务运行时内部或运营专用测试。
- 清单只保留路径、领域、Typebar 证据路径和原生测试函数名；不复制测试步骤、参考代码、词表、视觉资产或线上数据。
- `Compatibility/official-reference-behavior-specs.json` 是机器可读来源；每个直接规格都附有可定位的 `nativeTests` 函数名。`zsh Scripts/check-reference-behavior-audit.sh /absolute/path/to/monkeytype-reference` 会核对固定提交、64 个路径的完备分类、直接行为的原生证据路径和函数符号，以及本文覆盖。

## 直接用户行为规格

| 参考规格路径 | 可观察领域 | Typebar 原生证据 |
| --- | --- | --- |
| `frontend/__tests__/commandline/util.spec.ts`、`frontend/__tests__/root/config-metadata.spec.ts` | 命令面板目录、可搜索设置、枚举和输入约束 | `CommandPalette.swift` 与 `TypingEngineTests.swift` 的命令目录、严格 ID、数值输入和设置路由回归。 |
| `frontend/__tests__/components/pages/account/utils.spec.ts`、`frontend/__tests__/elements/test-activity-calendar.spec.ts`、`frontend/__tests__/utils/date-and-time.spec.ts` | 历史指标、活动日历、首日和跨月/年边界 | `ResultsAnalytics.swift`、`CloudSyncView.swift` 与 `TypingEngineTests.swift` 的活动、趋势、连续天数、日界，以及随系统首日设置调整热力图周列/跨月标签的回归。 |
| `frontend/__tests__/components/pages/test/keymapConverter.spec.ts`、`frontend/__tests__/test/layout-emulator.spec.ts`、`frontend/__tests__/utils/key-converter.spec.ts` | 键盘图、物理键位、ISO/ANSI 和布局模拟 | `KeyboardGuide.swift`、`KeyboardLayoutEmulator.swift` 与 `TypingEngineTests.swift` 的 239 项布局、层、反查和输入模拟回归。 |
| `frontend/__tests__/components/ui/form/utils.spec.ts` | 自定义参数的有效性与提示 | `TestLimitEditor.swift`、`TypingEngineTests.swift` 的安全整数、边界和取消/确认策略回归。 |
| `frontend/__tests__/controllers/preset-controller.spec.ts` | 完整/部分预设与标签作用域 | `PresetApplicationPolicy.swift`、`TypingEngineTests.swift` 的分组应用、标签和旧格式回归。 |
| `frontend/__tests__/controllers/url-handler.spec.ts` | 可分享测试选择、旧版 `testSettings` 压缩元组及非法链接拒绝 | `TestConfigurationShare.swift`、`LegacyTestSettingsLinkImporter.swift`、`TypingEngineTests.swift` 的自有链接往返、固定版本真实 URI 向量、旧版自定义文本、funbox 边界和离线拒绝回归。 |
| `frontend/__tests__/input/handlers/insert-text.spec.ts`、`frontend/__tests__/input/helpers/fail-or-finish.spec.ts`、`frontend/__tests__/input/helpers/util.spec.ts`、`frontend/__tests__/input/helpers/validation.spec.ts` | 输入接受、错误策略、完成/失败、词边界 | `TypingEngine.swift`、`ResultsAnalytics.swift`、`ResultCelebration.swift`、`ResultPersistence.swift`、`RemoteAccount.swift`、`DataTransfer.swift`、`TypebarApp.swift`、自建服务端的结果模型与 `TypingEngineTests.swift`/`HealthRouteTests.swift` 的逐字符状态、难度、停止/删除错误、阈值和完成回归；阈值失败仍会呈现本次可检查的结果，但不会保存为完成成绩；完成但过短、同提示词重测、异常速度/Raw 或未达准确率门槛的结果同样可复盘，却不会进入本机历史、同步或发布；所有已终止结果（含阈值失败、主动中止和 AFK 无效）都会以已扣除闲置时间计入本次会话的今日练习累计；零速度且持续至少 5 秒的终止结果会显示原生重试提示，难度失败则保留其失败原因；参照 `frontend/src/ts/test/result.ts`，新 PB 或符合条件的零速度结果会从左右各发射 5 个代码绘制粒子，持续 125ms，且遵从 Typebar 与系统的降低动效偏好；同一快照的标签会在所有终止结果中只读展示，只有已保存结果可编辑标签；无压力结果模式仅在本次启动期间隐藏结果详情，不写入任何设置或成绩数据；参照 `frontend/src/ts/test/test-logic.ts`、`frontend/src/ts/test/events/stats.ts`、`frontend/src/ts/db.ts` 与 `frontend/src/ts/collections/results.ts`，保存成绩前的重开、阈值失败或非引文重测会只累计有效键入秒数和重开次数，随后在一条可保存成绩中进入历史与日活动统计；原生端以不可变前序时长快照实现该行为，旧归档/本机记录缺字段时归零，结果页与当前进程今日摘要仍只展示最后一段测试；自建服务通过可选、版本化的能力协商载荷把最终局和前序局的有效秒数用于个人/公开练习统计与 CSV，缺字段的历史记录保持墙钟回退；该载荷不参与排行榜资格、WPM 或经验值计算。 |
| `frontend/__tests__/root/config.spec.ts`、`frontend/__tests__/utils/config.spec.ts` | 设置写入、冲突归一化、持久化和旧值迁移 | `AppSettings.swift`、`TypingEngineTests.swift` 的快照、JSON、配置锁、迁移，以及字体大小保留有限正数、将非正或非有限导入值归一化的回归。 |
| `frontend/__tests__/stores/notifications.spec.ts` | 连接状态与短暂状态提示 | `TypebarApp.swift`、`TypingEngineTests.swift` 的离线横幅、真实恢复提示和终止状态回归；网页 Toast 内部历史不作为 macOS UI 架构目标。 |
| `frontend/__tests__/test/british-english.spec.ts`、`frontend/__tests__/test/lazy-mode.spec.ts` | 专项英语与简化输入 | `OfflineContent.swift`、`TypingEngine.swift`、`TypingEngineTests.swift` 的独立词流、语言特例和 Unicode 简化回归。 |
| `frontend/__tests__/test/events/data.spec.ts`、`frontend/__tests__/test/events/helpers.spec.ts`、`frontend/__tests__/test/events/stats.spec.ts`、`frontend/__tests__/test/test-words.spec.ts` | 输入事件、统计、提示词段和提交分隔符 | `TypingEngine.swift`、`TypingEngineTests.swift` 的重放、WPM/Raw/准确率、文本段和完成回归。 |
| `frontend/__tests__/test/funbox.spec.ts`、`frontend/__tests__/test/funbox/funbox-validation.spec.ts` | Funbox 注册、冲突和配置限制 | `CommandPalette.swift`、`TypingEngine.swift`、`TypingEngineTests.swift` 的 48 项目录、互斥和归一化回归。 |
| `frontend/__tests__/utils/colors.spec.ts` | 自定义主题颜色解析和显示 | `AppTheme.swift`、`TypingEngineTests.swift` 的颜色、主题持久化和回退回归。 |
| `frontend/__tests__/utils/format.spec.ts`、`frontend/__tests__/utils/date-and-time.spec.ts`、`frontend/__tests__/utils/misc.spec.ts` | WPM、准确率、结果用时与计数 | `AppSettings.swift`、`TypingEngine.swift`、`ResultsAnalytics.swift`、`ResultPersistence.swift` 与 `TypingEngineTests.swift`：单位换算后在普通展示中取整；完成结果的主速度在 1000 WPM 起显示“无限”，Raw 保持数值；准确率默认向下取整、普通百分比四舍五入；结果页开启小数时保留未取整速度和非满分准确率至两位、满分仍显示 `100%`，并让稳定度也固定两位；总用时按参考的 61 秒阈值在四舍五入秒数、两位小数和时钟格式间切换，且验证 JSON/本机记录往返；计数和结果摘要保持回归。 |
| `frontend/__tests__/utils/numbers.spec.ts` | XP 与公开统计数字呈现 | `ExperiencePresentation.swift`、`PublicPracticeStatistics.swift`、`CloudSyncView.swift`、`AboutTypebar.swift`、`TypingEngineTests.swift` 将千以上 XP 紧凑呈现为一位小数的 `k/m/b…`；公开统计以两位小数内的数量级卡显示次数；两者均回归边界、舍入及不可信负数处理。 |
| `frontend/__tests__/utils/generate.spec.ts`、`frontend/__tests__/utils/ip-addresses.spec.ts` | 生成的符号流、IPv4/IPv6 格式 | `OfflineContent.swift`、`TypingEngineTests.swift` 的原创符号流、CIDR 网络位与 IPv6 压缩格式回归。 |
| `frontend/__tests__/utils/strings.spec.ts` | Unicode 词界、RTL 和视觉等价输入 | `TypingEngine.swift`、`TypingEngineTests.swift` 的组合文本、等价标点、空白、俄语和双向文本回归。 |

## 自建服务的 controller 行为规格

| 参考规格路径 | 可观察领域 | Typebar 原生证据 |
| --- | --- | --- |
| `backend/__tests__/api/controllers/admin.spec.ts` | 审核队列、资料/账户治理与权限边界 | `Routes.swift`、`AuthStore.swift` 与 `HealthRouteTests.swift` 的审核部署密钥、资料审核和账户暂停回归。 |
| `backend/__tests__/api/controllers/ape-key.spec.ts` | 开发者访问密钥的创建、作用域和撤销 | 同一自建服务路由与测试守护哈希保存、仅限本人结果、撤销后失效。 |
| `backend/__tests__/api/controllers/config.spec.ts`、`backend/__tests__/api/controllers/preset.spec.ts` | 账户配置和预设的版本化保存/同步 | 自建同步路由以用户作用域版本和分页 cursor 同步归档；测试守护无跳页和隔离。 |
| `backend/__tests__/api/controllers/connections.spec.ts` | 好友请求、接受、删除与屏蔽 | 自建连接路由和测试守护关系状态、用户隔离及屏蔽时的清理。 |
| `backend/__tests__/api/controllers/leaderboard.spec.ts` | 全局/好友榜、分页和个人可见范围 | 自建榜单路由和测试守护稳定分页、总数、offset 与仅已接受好友的范围。 |
| `backend/__tests__/api/controllers/psa.spec.ts` | 服务公告的公开读取和部署者发布/撤销 | 自建公告路由和测试守护公开读取、部署密钥与删除。 |
| `backend/__tests__/api/controllers/public.spec.ts` | 匿名公开资料和公共练习统计 | 自建公开路由只返回允许字段，测试守护邮箱隐藏和可分享的聚合统计。 |
| `backend/__tests__/api/controllers/quotes.spec.ts` | 社区引语提交、审核和公开读取 | 自建引语路由和测试守护内容校验、待审状态、审核与仅公开已批准条目。 |
| `backend/__tests__/api/controllers/result.spec.ts` | 成绩提交、历史和榜单写入 | 自建结果路由和测试守护认证、幂等提交、资格排序和榜单响应。 |
| `backend/__tests__/api/controllers/user.spec.ts` | 注册、登录与删除账户 | 自建身份路由和测试守护独立会话、密码验证及级联清理。 |

## 包级可观察行为规格

| 参考规格路径 | 可观察领域 | Typebar 原生证据 |
| --- | --- | --- |
| `packages/contracts/__test__/validation/validation.spec.ts` | 远端请求值、成绩与时间证据的有效边界 | 自建结果模型和路由拒绝不可能或格式错误的成绩；旧客户端仍可省略可选时间证据。 |
| `packages/funbox/__test__/validation.spec.ts` | Funbox 组合与冲突规则 | 原生输入引擎以独立矩阵拒绝冲突项、保留当前有效组合并覆盖词源组合。 |
| `packages/schemas/__tests__/config.spec.ts` | 设置 ID、枚举值和归档配置边界 | 原生命令面板与设置归档拒绝未知值，并守护全部可用选择的往返。 |

## 网页运行时支持规格

以下文件被完整枚举但不直接映射为独立 macOS 用户任务：`frontend/__tests__/hooks/createEvent.spec.ts`、`frontend/__tests__/hooks/createSignalWithSetters.spec.ts`、`frontend/__tests__/utils/local-storage-with-schema.spec.ts`、`frontend/__tests__/utils/sanitize.spec.ts`、`frontend/__tests__/utils/tag-builder.spec.ts`、`frontend/__tests__/utils/zod.spec.ts`，以及 `backend/__tests__/api/controllers/configuration.spec.ts`、`backend/__tests__/api/controllers/dev.spec.ts`、`backend/__tests__/api/controllers/webhooks.spec.ts`、`packages/schemas/__tests__/util.spec.ts`、`packages/util/__test__/arrays.spec.ts`、`packages/util/__test__/date-and-time.spec.ts`、`packages/util/__test__/json.spec.ts`、`packages/util/__test__/numbers.spec.ts`、`packages/util/__test__/predicates.spec.ts`、`packages/util/__test__/strings.spec.ts`、`packages/util/__test__/trycatch.spec.ts`。前六项验证 Solid/DOM/Zod/LocalStorage 的网页内部实现，后三项是部署配置、开发接口或上游发布 webhook，余下八项是可由 Swift 标准库/SwiftData 原生替代的 schema 或通用工具；Typebar 以 Swift observation、SwiftData、Codable、自建部署配置与版本资料替代，没有复制这些实现。任何未来从这些支持层暴露为新用户任务的行为，都必须移入上表、添加原生证据并更新验收。

## 验收结论

该盘点补充页面/模态、配置、输入、Funbox、语言和服务面审计：它证明固定参考的测试证据面没有被只按文件名的 UI 盘点遗漏，并拒绝指向不存在原生测试函数的伪证据。它不替代真实 macOS 窗口、IME、辅助功能、网络或多设备手工验收；这些仍按 `MANUAL_ACCEPTANCE.md` 和各专项审计保持未完成状态。
