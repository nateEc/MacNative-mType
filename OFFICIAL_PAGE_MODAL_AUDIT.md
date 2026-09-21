# 官方页面与模态能力审计

## 范围与方法

- 固定参考：`work/monkeytype-reference` 的 `91bd24bb8513785c7364cbea29296ff7adafac41`。
- 本表审计官方 `frontend/src/ts/components/pages` 与 `frontend/src/ts/components/modals` 中面向用户的领域能力；通用按钮、布局、异步包装器和网页样式组件不单独计数。
- 配置键的逐项守恒另见 [OFFICIAL_CONFIG_AUDIT.md](OFFICIAL_CONFIG_AUDIT.md)。本表不以组件同名、DOM 结构或网页视觉作为重写目标，只追踪用户能完成的任务及其重要失败路径。
- Typebar 只使用独立编写的 Swift/SwiftUI/SwiftData 代码、原创或授权内容和自建服务；不导入参考的代码、词表、引语或资产。

## 根页面与练习界面

| 官方入口／可见意图 | Typebar 原生入口 | 状态与证据 |
| --- | --- | --- |
| `test`（模式、提示、输入、实时统计、计时条、大小写／失焦提示、结果提示） | `TypingCompanion.swift`、`TypingEngine.swift`、`LivePracticeContent.swift`、`NativeTypingInput.swift`、`PaceGuide.swift`、`KeyboardGuide.swift` | 已覆盖。配置语义由固定 schema 测试守护；本机输入、提示和结果不是网页 DOM 的移植。 |
| `settings`（可搜索设置、快捷导航和自定义设置编辑器） | `PreferencesView.swift`、`SettingsSearch.swift`、`CommandPalette.swift` 及各设置编辑器 | 已覆盖。94 个参考配置键的 92 项映射、1 项原生字体适配和 1 项无广告不适用由 `OfficialLayoutCoverageTests` 守护。 |
| `account`（历史、统计、图表、个人最佳、资料） | `ArchiveManagementView.swift`、`ResultsAnalytics.swift`、`PersonalBestTable.swift`、`RemoteAccount.swift` | 已覆盖。本机成绩是权威副本；远端服务是显式可选发布与同步目标。 |
| `account settings`（身份方法、邮箱／密码／显示名、密钥、拉黑、危险操作） | `PreferencesView.swift`、`RemoteAccount.swift`、`LocalAccountReset.swift` | 已覆盖。密码、OAuth、邮箱验证、密码重置、账号删除、开发者密钥及展示名预检均有自建契约；显示名实际写入仍由服务端权威校验。 |
| `profile`／`profile search` | `RemoteAccount.swift`、`ConnectionsView.swift`、`ProfileReportView.swift` | 已覆盖。公开资料只暴露最小公开字段，搜索、关系、屏蔽与举报均通过自建服务。 |
| `friends` | `ConnectionsView.swift`、`DirectConversationView.swift`、`NotificationsView.swift` | 已覆盖。好友请求、接受、解除、屏蔽、通知和已接受好友间受控私信由自建 API 提供。 |
| `leaderboards` | `CloudSyncView.swift`、`LeaderboardParameterFilter.swift`、`LeaderboardPagination.swift`、`LeaderboardRankStanding.swift` | 已覆盖。全局／好友 WPM 和 XP 范围、个人名次与隐身选择均是原生界面与自建 API。 |
| `about`／版本历史 | `AboutTypebar.swift`、`ReleaseHistory.swift` | 已覆盖，以 Typebar 自己的产品资料、许可和版本信息取代参考品牌内容。 |
| `login` | `PreferencesView.swift`、`OAuthWebAuthenticationSession.swift` | 已覆盖，**但外部 CAPTCHA 人机验证仍是 `SEC-01` 未关闭缺口**。 |
| `404` | 无 URL 路由 | 不适用。原生应用没有用户可访问的网页路由；导航错误由本机命令和工作表状态处理。 |

## 模态与工作表能力

| 官方组件族 | Typebar 原生等价能力 | 状态 |
| --- | --- | --- |
| 自定义练习：`CustomText`、`SaveCustomText`、`SavedTexts`、`CustomGenerator`、`WordFilter`、`CustomTestDuration`、`CustomWordAmount`、`ShareTestSettings` | `CustomTextGenerator.swift`、`SavedTexts.swift`、`WordFilter.swift`、`TestLimitEditor.swift`、`TestConfigurationShare.swift` | 已覆盖：输入、保存、筛选、时长／词数、自定义生成与可分享测试选择均是本机数据。 |
| 预设：`AddPreset`、`EditPreset`、完整／部分应用 | `TestPresets.swift`、`ActiveTestSelectionStore.swift` | 已覆盖：创建、编辑、应用和同步冲突处理使用版本化原生选择。 |
| 成绩：`AddTag`、`EditResultTags`、`PbTables`、`LastSignedOutResult` | `ActiveResultTagEditor.swift`、`PersonalBestTable.swift`、`ResultPersistence.swift`、`CloudSyncView.swift` | 已覆盖且本机优先。官方仅在登出后暂存一局、认证成功后询问是否上传；Typebar 始终先保存本机，用户开启发布后才发送，网络／认证可恢复失败会按账户与服务端范围持久化排队重试。 |
| 社区引语：`QuoteSearch`、`QuoteRate`、`QuoteReport`、`QuoteSubmit`、`QuoteApprove` | `QuoteSearch.swift`、`QuoteRatings.swift`、`QuoteResultFeedback.swift`、`RemoteAccount.swift` | 已覆盖：搜索、投稿、撤回、评分、举报及自建审核队列均有独立模型和 API。 |
| 账户：`GoogleSignUp`、`ForgotPassword`、`EditProfile`、更新名字／邮箱／密码、添加／移除身份方式、重新认证、Ape key | `PreferencesView.swift`、`RemoteAccount.swift`、`OAuthWebAuthenticationSession.swift` | 已覆盖，身份／会话与密钥只进入 Typebar 自建服务。Google、GitHub 和 Discord 是可配置 OAuth 提供方，而不是复用参考服务。`RegisterCaptcha` 和同一官方验证码机制覆盖的忘记密码／举报路径单列为 `SEC-01`。 |
| 社交与治理：`UserReport`、`StreakHourOffset`、`EditProfile` | `ProfileReportView.swift`、`RemoteAccount.swift`、`AppSettings.swift` | 已覆盖：私有举报、审核状态、排行榜限制、显示名整改、封禁、连续天数日界线和资料编辑均由原生界面表达。 |
| 版本、联系、支持 | `ReleaseHistory.swift`、`AboutTypebar.swift` | 已覆盖为 Typebar 自己的版本信息、仓库／反馈入口；不链接或冒充 Monkeytype 的邮箱、资助或品牌。 |

## 明确不适用的网页／运营表面

| 官方表面 | 判定 | 原因 |
| --- | --- | --- |
| `Advertisement` 与 `SupportModal` 的广告／资助链路 | 不适用 | Typebar 的产品约束是无广告；配置守恒表也将官方 `ads` 标记为不适用。 |
| `CookiesModal` | 不适用 | 该组件管理浏览器 Cookie、分析和 Sentry 许可。原生本机数据遵循 macOS 沙盒、`UserDefaults`、SwiftData 和 Keychain，不写网页 Cookie。 |
| `MobileTestConfigModal` | 不适用 | 这是移动浏览器的紧凑测试配置入口；macOS 的窗口、命令和工作表可直接使用完整原生配置。 |
| `DevOptionsModal`、`EventLogViewerModal` | 不适用 | 它们是参考站的开发／运营工具，不是最终用户练习功能；Typebar 用自动化测试和本机开发工具验证，不把运营开关交付给用户。 |
| `Premid` | 不适用 | 参考源码明确写明它是供 PreMiD 浏览器扩展读取 Discord 富状态的隐藏 DOM，用户不可见。macOS 原生应用没有可供浏览器扩展读取的 DOM。 |

## 未关闭缺口：SEC-01 外部人机验证

官方在 `RegisterCaptchaModal` 中要求用户完成验证码；`CreateUserRequest` 传递不透明 token，服务端 `verifyCaptcha` 使用部署私密的 `RECAPTCHA_SECRET` 验证。相同验证还用于找回密码和用户举报。这是公开写入入口的防滥用能力，不能用当前进程内速率限制替代，也不能标为网页专属。

Typebar 当前已有每来源／令牌的固定窗口限速、最小化公开资料、私有举报和失败可重试的本机成绩发布，但**尚未提供可部署的外部人机验证提供方或原生验证流程**。因此本审计将其保留为唯一明确的页面／模态安全兼容缺口；不得据此文件宣称页面与账户流程已 100% 功能等价。

下一步需要以安全设计审查决定并实现一个不绑定 Monkeytype 的协议：部署者配置独立的人机验证提供方，原生客户端通过安全的认证会话取得一次性证明，服务端按用途验证并防重放。验证范围至少包括注册、密码重置请求和资料／引语举报；缺失配置、验证服务故障和重放 token 必须有可测试、不会放行写入的失败语义。

## 验收规则

- 每一行的“已覆盖”必须能指向 Typebar 原生源文件及自动化测试；不以视觉相似或参考组件名称作为验收。
- 平台专属行必须说明输入、存储或集成边界，不能用“尚未实现”伪装成不适用。
- `SEC-01` 未完成前，任何功能总账都必须保留该安全缺口；实现后应以先失败的服务端与原生客户端测试、端到端契约测试和本表更新关闭它。
