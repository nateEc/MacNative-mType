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
| `account`（历史、统计、图表、个人最佳、资料） | `ArchiveManagementView.swift`、`ResultsAnalytics.swift`、`PersonalBestTable.swift`、`RemoteAccount.swift` | 已覆盖。本机成绩是权威副本；远端服务是显式可选发布与同步目标。固定官方路径与速度／准确率、10／100 次均值、PB 轨迹、单局分析、直方图及日活动的原生等价实现见 [OFFICIAL_ACCOUNT_ANALYTICS_AUDIT.md](OFFICIAL_ACCOUNT_ANALYTICS_AUDIT.md)。 |
| `account settings`（身份方法、邮箱／密码／显示名、密钥、拉黑、危险操作） | `PreferencesView.swift`、`RemoteAccount.swift`、`LocalAccountReset.swift` | 已覆盖。密码、OAuth、邮箱验证、密码重置、账号删除、开发者密钥及展示名预检均有自建契约；显示名实际写入仍由服务端权威校验。 |
| `profile`／`profile search` | `RemoteAccount.swift`、`ConnectionsView.swift`、`ProfileReportView.swift` | 已覆盖。公开资料只暴露最小公开字段，搜索、关系、屏蔽与举报均通过自建服务。 |
| `friends` | `ConnectionsView.swift`、`DirectConversationView.swift`、`NotificationsView.swift` | 已覆盖。好友请求、接受、解除、屏蔽、通知和已接受好友间受控私信由自建 API 提供。 |
| `leaderboards` | `CloudSyncView.swift`、`LeaderboardParameterFilter.swift`、`LeaderboardPagination.swift`、`LeaderboardRankStanding.swift` | 已覆盖。全局／好友 WPM 和 XP 范围、个人名次与隐身选择均是原生界面与自建 API。 |
| `about`／版本历史 | `AboutTypebar.swift`、`ReleaseHistory.swift`、`PublicPracticeStatistics.swift` | 已覆盖，以 Typebar 自己的产品资料、许可和版本信息取代参考品牌内容；About 打开时还可无令牌读取自建服务的匿名全局练习总览与 English 60 秒个人最佳速度分布。旧服务不可用时明确降级，不使用本机成绩伪造全局数据；完整来源、隐私与验收见 [OFFICIAL_PUBLIC_PRACTICE_STATISTICS_AUDIT.md](OFFICIAL_PUBLIC_PRACTICE_STATISTICS_AUDIT.md)。 |
| `login` | `PreferencesView.swift`、`OAuthWebAuthenticationSession.swift`、`RemoteHumanVerification.swift` | 已覆盖。完整配置自建 Turnstile 后，密码注册、OAuth 新用户注册及密码重置请求会通过系统认证会话完成一次性验证；未配置旧服务保留已有请求契约并如实报告能力未启用。 |
| `404` | 无 URL 路由 | 不适用。原生应用没有用户可访问的网页路由；导航错误由本机命令和工作表状态处理。 |

## 模态与工作表能力

| 官方组件族 | Typebar 原生等价能力 | 状态 |
| --- | --- | --- |
| 自定义练习：`CustomText`、`SaveCustomText`、`SavedTexts`、`CustomGenerator`、`WordFilter`、`CustomTestDuration`、`CustomWordAmount`、`ShareTestSettings` | `CustomTextGenerator.swift`、`SavedTexts.swift`、`WordFilter.swift`、`TestLimitEditor.swift`、`TestConfigurationShare.swift` | 已覆盖：输入、保存、筛选、时长／词数、自定义生成与可分享测试选择均是本机数据。 |
| 预设：`AddPreset`、`EditPreset`、完整／部分应用 | `TestPresets.swift`、`ActiveTestSelectionStore.swift` | 已覆盖：创建、编辑、应用和同步冲突处理使用版本化原生选择。 |
| 成绩：`AddTag`、`EditResultTags`、`PbTables`、`LastSignedOutResult` | `ActiveResultTagEditor.swift`、`PersonalBestTable.swift`、`ResultPersistence.swift`、`CloudSyncView.swift` | 已覆盖且本机优先。官方仅在登出后暂存一局、认证成功后询问是否上传；Typebar 始终先保存本机，用户开启发布后才发送，网络／认证可恢复失败会按账户与服务端范围持久化排队重试。 |
| 社区引语：`QuoteSearch`、`QuoteRate`、`QuoteReport`、`QuoteSubmit`、`QuoteApprove` | `QuoteSearch.swift`、`QuoteRatings.swift`、`QuoteResultFeedback.swift`、`RemoteAccount.swift`、`RemoteHumanVerification.swift` | 已覆盖：搜索、投稿、撤回、评分、举报及自建审核队列均有独立模型和 API；部署者启用 Turnstile 时，投稿与举报在写入前消费用途绑定的一次性证明。 |
| 账户：`GoogleSignUp`、`ForgotPassword`、`EditProfile`、更新名字／邮箱／密码、添加／移除身份方式、重新认证、Ape key | `PreferencesView.swift`、`RemoteAccount.swift`、`OAuthWebAuthenticationSession.swift`、`RemoteHumanVerification.swift` | 已覆盖，身份／会话与密钥只进入 Typebar 自建服务。Google、GitHub 和 Discord 是可配置 OAuth 提供方，而不是复用参考服务。固定参考已证实密码注册和 Google 首次补名注册都要求验证码；Typebar 以同一注册用途保护这两条路径，并将该协议统一应用于其余可配置 OAuth 提供方。 |
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

## SEC-01 外部人机验证：代码与契约已实现

官方密码注册的 `RegisterCaptchaModal` 与 OAuth 首次补名的 `GoogleSignUpModal` 都要求用户完成验证码；`CreateUserRequest` 传递不透明 token，服务端 `verifyCaptcha` 使用部署私密的 `RECAPTCHA_SECRET` 验证。相同验证还用于找回密码、用户举报、社区引语投稿和引语举报。这是公开写入入口的防滥用能力，不能用当前进程内速率限制替代，也不能标为网页专属。

Typebar 现已提供可部署的 Cloudflare Turnstile 适配：服务端创建 5 分钟、单用途挑战，提供自写的最小网页容器并在服务器侧验证 `success`、action、cData 与允许 hostname；成功后才签发不持久化的一次性 callback proof。原生客户端只接受 `https` 服务地址返回的相对挑战路径和固定 `typebar://human-verification/callback` 回调，再把 proof 附到相应写请求。服务端在业务写入之前的 actor 临界区消费 proof，缺失、错误用途、过期、重放、验证拒绝和提供方不可达均不放行。

服务端测试覆盖五个用途、六条具体写入路径（密码注册、OAuth 新用户注册、密码重置请求、资料举报、引语投稿、引语举报）的缺 proof、成功、重放／用途替换、到期与 provider 失败；原生测试覆盖能力协商、相对 HTTPS URL 与固定 callback 解析；完整服务端 109 项和原生 653 项套件验证已有功能无回归。设计审查见 [SECURITY_HUMAN_VERIFICATION_DECISION.md](SECURITY_HUMAN_VERIFICATION_DECISION.md)。这不是对第三方服务的“已上线”声明：部署者仍须使用自己的密钥和真实 HTTPS hostname 进行一次手工部署验收，并且当前实现只支持单服务进程；多副本前需引入共享、原子 TTL 挑战存储。

## 验收规则

- 每一行的“已覆盖”必须能指向 Typebar 原生源文件及自动化测试；不以视觉相似或参考组件名称作为验收。
- 平台专属行必须说明输入、存储或集成边界，不能用“尚未实现”伪装成不适用。
- SEC-01 的回归必须保留五用途（其中注册含密码和 OAuth 两条路由）服务端拒绝／消费测试、原生 URL／callback 边界测试、完整套件与单进程部署限制；真实第三方密钥不属于仓库测试数据。
