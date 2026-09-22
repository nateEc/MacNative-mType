# 官方服务面审计

## 范围与证据

- 固定参考：`monkeytypegame/monkeytype` 提交 `91bd24bb8513785c7364cbea29296ff7adafac41`。
- 直接检查的主证据为 `backend/src/api/routes/index.ts`，以及其中注册的 `users`、`configs`、`presets`、`quotes`、`results`、`connections`、`leaderboards`、`configuration`、`ape-keys`、`public`、`psas`、`webhooks`、`admin` 与 `dev` 路由模块。
- 本表审计用户能完成的远程任务，**不**把 URL、JSON 字段、Firebase/Express/TypeScript 实现或参考线上数据当作兼容目标。Typebar 的服务仅使用自己的 Vapor 路由、数据模型和凭据。

## 用户服务能力映射

| 固定参考路由族 | 可观察的用户任务 | Typebar 独立实现与边界 |
| --- | --- | --- |
| `users` | 注册、账户资料、展示名、账户重置/删除、个人最佳、标签、主题、收藏、结果筛选、连续天数、收件箱与举报 | `RemoteAccount.swift`、`AppSettings.swift`、`ActiveResultTagEditor.swift`、`LocalAccountReset.swift` 与自建 `auth`／`profiles`／`notifications`／`reports` 路由覆盖账户、资料、个人最佳、标签、收藏、本机设置及公共资料任务。公开徽章默认只含用户选择的一枚；仅账户所有者可在现有资料 PATCH 明确开启额外已获得徽章的资料卡展示，缺失字段安全回退为关闭/空数组且榜单不扩大披露。配置、主题、预设、收藏与筛选保持本机优先；其中成绩筛选预设作为 v4 活跃字段、并从 v5 起携带显式删除标记，成绩从 v6 起同样携带显式删除标记；自定义主题从 v9 起也携带稳定 UUID 与显式删除标记，均随导出、导入和 Typebar 同步传输，而非复制参考的按资源 API。 |
| `configs`、`presets` | 跨设备保存、读取、编辑或删除配置与预设 | `DataTransfer.swift`、`TestPresets.swift`、`SavedTexts.swift`、`RemoteAccount.swift` 与 `GET/POST /v1/sync` 传输版本化 Typebar 归档；本机测试预设从 v7、保存文本从 v8、自定义主题和 Typebar 自定义键盘布局从 v9 起携带稳定 UUID 与显式删除标记，阻止旧设备快照复活；冲突显式保留本机标量并另存冲突副本。 |
| `results` | 提交、读取、查看单条、编辑标签和删除自己成绩 | `ResultPersistence.swift`、`RemoteAccount.swift` 与 `/v1/results`、`/v1/results/{id}`、`/v1/results/{id}/tags` 实现。所有练习先保留在本机；本机历史删除会写入 v6 归档删除标记，阻止旧设备快照复活，明确导入旧本机备份可恢复。远端发布是用户选择，令牌与受限开发者密钥均只限自己的元数据。 |
| `quotes` | 浏览、提交、审核、评分和举报社区引语 | `OfflineContent.swift`、`QuoteSearch.swift`、`QuoteRatings.swift`、`QuoteResultFeedback.swift` 与 `/v1/quotes`、`/v1/reports/quotes`、审核路由实现。内置词流和引语始终是 Typebar 自有内容；社区内容只在用户明确选择时从自建服务读取。 |
| `connections` | 搜索资料、发起/接受/解除好友、屏蔽与关系通知 | `ConnectionsView.swift`、`NotificationsView.swift`、`ProfileReportView.swift`、`DirectConversationView.swift` 与自建连接、屏蔽、通知、私信及资料举报路由实现。公开响应不含邮箱、提示或回放。 |
| `leaderboards` | 全局/好友 WPM、每日/每周范围与 XP 榜、查看自己的名次 | `CloudSyncView.swift`、`LeaderboardParameterFilter.swift`、`LeaderboardRankStanding.swift` 与 Typebar 的 WPM/XP 榜路由实现。服务从 Typebar 成绩重新计算 XP；它不冒充参考的赛季或可信竞赛基础设施。 |
| `public` | 匿名全局练习统计与速度分布 | `AboutTypebar.swift`、`PublicPracticeStatistics.swift` 和无认证的 `/v1/public/practice-stats`、`/v1/public/speed-distribution` 实现。只返回去标识聚合；隐身、治理限制、整改与封禁账户不贡献数据。 |
| `psas` | 接收公开服务公告 | `RemoteAnnouncements.swift` 与 `/v1/announcements` 实现。公告仅来自 Typebar 部署者，不使用或镜像参考公告。 |
| `ape-keys` | 管理受限的程序化访问密钥 | `RemoteAccount.swift` 与 `/v1/developer-keys` 实现。明文只在创建时返回，服务端保存哈希；密钥不能读取资料、同步或其他账户数据。 |
| `configuration` | 获取服务能力和处理服务端维护状态 | `/v1/capabilities`、`MaintenanceMode.swift`、`RemoteHumanVerification.swift` 与原生本地设置实现。原生应用不复制参考的网页全局配置/Schema 编辑页；本机设置由 SwiftData、UserDefaults 和归档负责。 |

## 明确不作为用户兼容目标的服务表面

| 固定参考路由族 | 判定 | 原因 |
| --- | --- | --- |
| `webhooks` | 不适用 | 这是参考部署接收 GitHub 事件的入口，不是终端用户执行的产品任务。Typebar 版本历史只读取自己的 GitHub Releases；任何部署 webhook 都必须由 Typebar 部署者另行配置。 |
| `admin`、`dev` | 不适用 | 参考运维者/开发环境工具不属于普通练习用户的可见能力。Typebar 的审核密钥只用于自建服务的明确审核工作台；不复用参考后台、权限或数据。 |
| `/docs` 与 Express/Swagger 配置 | 不适用 | 它们是参考 API 的运维/开发资料面。Typebar 的公开契约由 [SERVICE_CONTRACTS.md](SERVICE_CONTRACTS.md) 描述，不要求复制网页文档生成器。 |

## 结论与未验证运行条件

固定源码的每个会驱动用户可见远程任务的路由族，都已有 Typebar 的原生客户端入口和自建服务映射；平台/运维路由被明确列为不适用，而非遗漏。该结论仅证明固定源码的静态服务面已被盘点，不能替代真实部署验证。

以下仍依赖部署者提供的运行条件，必须保持为未完成验收，而不能凭单元测试标记为上线：真实 HTTPS 下的 OAuth、邮件 webhook 与 Turnstile 流程；真实多设备同步；多副本部署前的共享、原子 TTL 人机验证存储；以及不可伪造成绩证明、完整事件回放、分布式限速、持久化审计与数据保留策略。它们不会使 Typebar 回退到或连接参考服务。
