# 官方服务面审计

2026-10-06 [PB 配置保存合同](PERSONAL_BEST_CONFIGURATION_CONTRACT.md) 为 results 的真实投稿、首次接受记录和私有历史补充完整配置证据。resultPersonalBestConfiguration 的 available 仅声明自有字段可保存和读取，不代表 users 的独立 PB 或 leaderboards 全等价；既有模块映射数和 partial 状态不变。旧数据无配置仍未知。

2026-10-06 [PB 比较与生命周期合同](PERSONAL_BEST_COMPARISON_CONTRACT.md) 明确 users／leaderboards 的剩余语义差异：当前公开 PB 新纪元不是原版公开 clearPb，历史派生 PB／全部榜尚未改为独立账本，旧成绩缺少完整分组证据。模块映射只代表原生入口与自有服务面，不代表上述功能等价；状态继续 partial，不提升映射数量。

当前 [日榜任务与交付合同](DAILY_LEADERBOARD_SETTLEMENT_CONTRACT.md) 增加 leaderboards 的实际持久任务与邮件、admin 的只读状态及 psas 的原生榜首公告证据。未升级映射计数或 partial 状态；原版 Discord 渠道、全部模式、小数 WPM、原协议及真实窗口仍开放，原生公告不充当 Discord 验收。

当前 [奖励收件箱与周任务交付](REWARD_INBOX_CONTRACT.md) 增加 users 的真实 inbox 路由／原生入口、leaderboards 的持久周任务和 admin 的只读状态证据，相关路径已进入服务矩阵。领取源码、HTTP 和恢复自动化不升级模块计数或 partial 状态，不证明原 HTTP、徽章目录、真实 Mongo／BullMQ 或完整功能等价；人工验收仍待单窗口执行。

2026-10-03 完成统计增量见 [完成统计提交与历史边界](RESULT_CONSISTENCY_SERVICE_CONTRACT.md)：实际运行固定完整 buildDbResult 确认原版只保存输入节奏与按键稳定度，WPM 仅属完成请求。自有能力协商、匿名校验、按键历史保存与读取的新增回归已接入；不要求官方 URL／payload 身份，不增加官方模块覆盖或把 partial 改为全等价。本机归档 22 不变，真实部署／账户切换／旧二进制和完整反作弊仍未验。

## 范围与证据

- 固定参考：`monkeytypegame/monkeytype` 提交 `91bd24bb8513785c7364cbea29296ff7adafac41`。
- 直接检查的主证据为 `backend/src/api/routes/index.ts`，以及其中注册的 `users`、`configs`、`presets`、`quotes`、`results`、`connections`、`leaderboards`、`configuration`、`ape-keys`、`public`、`psas`、`webhooks`、`admin` 与 `dev` 路由模块。
- 本表审计用户能完成的远程任务，**不**把 URL、JSON 字段、Firebase/Express/TypeScript 实现或参考线上数据当作兼容目标。Typebar 的服务仅使用自己的 Vapor 路由、数据模型和凭据。
- `Compatibility/official-service-surfaces.json` 固定 `ts-rest` route registry 的 14 个模块标识、分区和 Typebar 自有证据路径。`zsh Scripts/check-reference-service-surface-audit.sh /absolute/path/to/monkeytype-reference` 会重新读取固定提交的 registry，检查总数、唯一性、分类互斥、完整覆盖和所有证据路径；它只保存标识级元数据，不复制参考路由、payload、内容或资产。
- `Compatibility/official-reference-behavior-specs.json` 中每个固定 controller 规格还声明其 route module 标识。`zsh Scripts/check-reference-service-behavior-alignment.sh /absolute/path/to/monkeytype-reference` 将两个独立 fixture 交叉检查：14 个标识必须一一对应，且直接用户行为只能映射到已实现服务分区。该检查只处理路径、分类和标识，不读取或保存参考实现、请求/响应或内容。

## 用户服务能力映射

| 固定参考路由族 | 可观察的用户任务 | Typebar 独立实现与边界 |
| --- | --- | --- |
| `users` | 注册、账户资料、展示名、账户重置/删除、个人最佳、标签、主题、收藏、结果筛选、连续天数、收件箱与举报 | `RemoteAccount.swift`、`AppSettings.swift`、`ActiveResultTagEditor.swift`、`LocalAccountReset.swift` 与自建 `auth`／`profiles`／`notifications`／`reports` 路由覆盖账户、资料、个人最佳、标签、收藏、本机设置及公共资料任务。公开徽章默认只含用户选择的一枚；仅账户所有者可在现有资料 PATCH 明确开启额外已获得徽章的资料卡展示，缺失字段安全回退为关闭/空数组且榜单不扩大披露。配置、主题、预设、收藏与筛选保持本机优先；其中成绩筛选预设作为 v4 活跃字段、并从 v5 起携带显式删除标记，成绩从 v6 起同样携带显式删除标记；自定义主题从 v9 起也携带稳定 UUID 与显式删除标记，均随导出、导入和 Typebar 同步传输，而非复制参考的按资源 API。 |
| `configs`、`presets` | 跨设备保存、读取、编辑或删除配置与预设 | `DataTransfer.swift`、`TestPresets.swift`、`SavedTexts.swift`、`RemoteAccount.swift` 与 `GET/POST /v1/sync` 传输版本化 Typebar 归档；本机测试预设从 v7、保存文本从 v8、自定义主题和 Typebar 自定义键盘布局从 v9 起携带稳定 UUID 与显式删除标记，阻止旧设备快照复活；冲突显式保留本机标量并另存冲突副本。 |
| `results` | 提交、读取、查看单条、编辑标签和删除自己成绩 | `ResultPersistence.swift`、`RemoteAccount.swift` 与 `/v1/results`、`/v1/results/{id}`、`/v1/results/{id}/tags` 实现。所有练习先保留在本机；本机历史删除会写入 v6 归档删除标记，阻止旧设备快照复活，明确导入旧本机备份可恢复。远端发布是用户选择，令牌与受限开发者密钥均只限自己的元数据。 |
| `quotes` | 浏览、提交、审核、评分和举报社区引语 | `OfflineContent.swift`、`QuoteSearch.swift`、`QuoteRatings.swift`、`QuoteResultFeedback.swift` 与 `/v1/quotes`、`/v1/reports/quotes`、审核路由实现。自建服务以显式 `fivePoint` 请求保存每账户 1–5 星并返回聚合总分/人数；重评替换同一账户记录。省略该标记的旧客户端与旧持久化二元投票继续兼容，原生界面也在旧响应上安全回退。内置词流和引语始终是 Typebar 自有内容；社区内容只在用户明确选择时从自建服务读取。 |
| `connections` | 搜索资料、发起/接受/解除好友、屏蔽与关系通知 | `ConnectionsView.swift`、`NotificationsView.swift`、`ProfileReportView.swift`、`DirectConversationView.swift` 与自建连接、屏蔽、通知、私信及资料举报路由实现。公开响应不含邮箱、提示或回放。 |
| `leaderboards` | 全局/好友 WPM、每日/每周范围与 XP 榜、查看自己的名次 | `CloudSyncView.swift`、`LeaderboardParameterFilter.swift`、`LeaderboardRankStanding.swift` 与 Typebar 的 WPM/XP 榜路由实现。服务从 Typebar 成绩重新计算 XP；它不冒充参考的赛季或可信竞赛基础设施。 |
| `public` | 匿名全局练习统计与速度分布 | `AboutTypebar.swift`、`PublicPracticeStatistics.swift` 和无认证的 `/v1/public/practice-stats`、`/v1/public/speed-distribution` 实现。只返回去标识聚合；隐身、治理限制、整改与封禁账户不贡献数据。 |
| `psas` | 接收公开服务公告 | `RemoteAnnouncements.swift` 与 `/v1/announcements` 实现。公告仅来自 Typebar 部署者，不使用或镜像参考公告。 |
| `ape-keys` | 管理受限的程序化访问密钥 | `RemoteAccount.swift` 与 `/v1/developer-keys` 实现。明文只在创建时返回，服务端保存哈希；密钥不能读取资料、同步或其他账户数据。 |
| `configuration` | 获取服务能力和处理服务端维护状态 | `/v1/capabilities`、`RemoteAccount.swift`、`RemoteHumanVerification.swift` 与原生本地设置实现。原生应用不复制参考的网页全局配置/Schema 编辑页；本机设置由 SwiftData、UserDefaults 和归档负责。 |
| `admin` | 部署者审核引语/资料举报、发布公告与账户治理 | `PreferencesView.swift`、`ProfileReportView.swift`、`RemoteAccount.swift` 与自建审核路由提供明确的部署密钥工作台；审核密钥只保留在当前内存会话，队列不披露举报者身份。它不复用参考后台、权限或数据。 |

## 明确不作为用户兼容目标的服务表面

| 固定参考路由族 | 判定 | 原因 |
| --- | --- | --- |
| `webhooks` | 不适用 | 这是参考部署接收 GitHub 事件的入口，不是终端用户执行的产品任务。Typebar 版本历史只读取自己的 GitHub Releases；任何部署 webhook 都必须由 Typebar 部署者另行配置。 |
| `dev` | 不适用 | 参考开发环境接口不属于终端用户功能。 |
| `/docs` 与 Express/Swagger 配置 | 不适用 | 它们是参考 API 的运维/开发资料面。Typebar 的公开契约由 [SERVICE_CONTRACTS.md](SERVICE_CONTRACTS.md) 描述，不要求复制网页文档生成器。 |

## 结论与未验证运行条件

固定源码的每个会驱动用户可见远程任务的路由族，都已有 Typebar 的原生客户端入口和自建服务映射；平台/运维路由被明确列为不适用，而非遗漏。该结论仅证明固定源码的静态服务面已被盘点，不能替代真实部署验证。

以下仍依赖部署者提供的运行条件，必须保持为未完成验收，而不能凭单元测试标记为上线：真实 HTTPS 下的 OAuth、邮件 webhook 与 Turnstile 流程；真实多设备同步；多副本部署前的共享、原子 TTL 人机验证存储；以及不可伪造成绩证明、完整事件回放、分布式限速、持久化审计与数据保留策略。它们不会使 Typebar 回退到或连接参考服务。
