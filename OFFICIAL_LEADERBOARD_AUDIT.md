# 官方排行榜分页映射审计

固定参考提交：`91bd24bb8513785c7364cbea29296ff7adafac41`。

## 参考行为

固定参考的 `frontend/src/ts/states/leaderboard-selection.ts` 将榜单页大小设为 50，并把 URL 页码转换为从零开始的页索引。`LeaderboardPage.tsx` 会依据账户排名计算所在页，`Navigation.tsx` 提供首页、个人所在页、上一页、指定页与下一页。其 contracts 将分页响应的总数量和实际页大小与 entries 一同返回，并允许的最大请求页大小为 200。

## 原生映射

| 参考可见意图 | Typebar 原生实现 | 边界 |
| --- | --- | --- |
| 每页浏览排行榜 | `CloudSyncView` 调用 `leaderboardPage` / `experienceLeaderboardPage`，固定每页 50 条 | WPM 与 XP、全局与已接受好友范围均适用 |
| 首页、前后页、输入页码 | `LeaderboardPaginationControls` | 页码从 1 开始显示，内部转换为安全的零开始偏移 |
| 打开自己所在页 | 由已加载的排名和 `LeaderboardPaginationPolicy.pageIndex` 计算 | 当前页就是本人页时不重复显示动作 |
| 服务端页数据 | `LeaderboardResponse` / `ExperienceLeaderboardResponse` 返回 `entries`、`total`、`offset`、`pageSize` | 请求页大小上限为 200；既有调用未传分页参数时保留原先的 25 条 WPM 与 100 条 XP 默认值 |

## 兼容与重写边界

这是面向自建服务的增量协议：新服务接受可选的 `offset`、`limit` 并附加分页元数据；旧客户端自然忽略新增 JSON 字段。反过来，新 macOS 客户端可以解码旧服务的仅 `entries` 响应，但会停在首批结果、提示该服务没有分页元数据，并禁用翻页与“前往我的页”，不会伪造总页数或重复条目。

本实现只根据可见行为和公开契约重新设计 SwiftUI、Swift 并发及 Vapor 数据模型；不复制参考项目的 TypeScript、组件、路由、文字、图标、词表或其他资产。分页只改变读取切片，不迁移、回填或改写任何账户、成绩、XP 与好友数据。

## 验证记录

- 原生兼容策略：`swift test --filter TypingEngineTests/testLeaderboardPageCompatibilityGatesPaginationForLegacyResponses`。
- 服务端分页边界：`swift test --filter HealthRouteTests/testLeaderboardsExposeStablePagesWithTotalsAndOffsets`。
- HTTP 参数透传：`swift test --filter HealthRouteTests/testResultRoutesRequireAuthenticationAndReturnLeaderboard`。
- 后续完整验收会在本次变更收尾前串行执行原生及服务端全部测试；遵守当前任务约束，不启动 Typebar 图形程序。
