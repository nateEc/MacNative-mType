# 官方排行榜测试参数映射审计

固定参考提交：`91bd24bb8513785c7364cbea29296ff7adafac41`。

## 参考行为

固定参考的 `packages/contracts/src/leaderboards.ts` 将 `language`、`mode` 和 `mode2` 作为速度榜、个人名次及每日榜的共同查询条件。`frontend/src/ts/queries/leaderboards.ts` 在读取榜单与读取个人名次时都会传递这三个值；`frontend/src/ts/event-handlers/test.ts` 从完成页打开每日榜时同样携带当前 `mode2`。`Sidebar.tsx` 根据服务端有效规则组合模式、参数和语言，标题也显示该参数。

对 Typebar 的时间和词数练习，`mode2` 的独立含义分别是完成时长和设定词数。它们已作为成绩字段持久化，因而速度、名次和完成回执必须只在同一参数桶内比较。禅模式和自定义文本在该参考契约中用固定字符串表示，不产生第二个可变的速度参数，保持 Typebar 原有按模式的单一桶。

## 原生映射

| 参考可见意图 | Typebar 原生实现 | 边界 |
| --- | --- | --- |
| 用模式、参数、语言读取速度榜 | `LeaderboardQuery.durationSeconds` / `wordLimit` 与 `AuthStore.leaderboardEntries` | 时长仅接受 time 模式的 5–3600 秒；词数仅接受 words 模式的 1–1000 词；不能混用 |
| 用相同条件获得本人名次 | `leaderboardRank` / `friendLeaderboardRank` 复用同一查询 | 不会因分页或榜单范围改变比较桶 |
| 完成页打开每日排行榜 | `TypebarApp` 将当前时长或词数带入 `RemoteLeaderboardSelection` | 原生同步窗口在服务确认能力后自动重载精确桶 |
| 从同步窗口选择参数 | `LeaderboardParameterPicker` 与有限范围的自定义编辑器 | 标准快捷项为 15/30/60/120 秒和 10/25/50/100 词；仍可选择其他服务允许值 |
| 兼容旧自建服务 | `LeaderboardResponse.parameterFilterSupported` | 旧响应没有该布尔值时，客户端不发送参数筛选，不把混合榜单伪称为精确名次 |

## 兼容与重写边界

这是 Typebar 自建服务的增量协议，不使用参考项目的 TypeScript、组件、文字、样式、词表、图标或资产。新服务明示支持参数过滤；旧客户端会自然忽略响应中的附加布尔字段。反向兼容时，新客户端先读取未带参数的页面，只有服务明示支持才重新请求精确桶；旧服务不会因未知查询字段被误判为支持。

该变更只读取既有成绩中的时长和词数字段，没有迁移、回填或改写历史账户、成绩、XP、好友或本机 SwiftData 数据。

## 验证记录

- 行为红灯/绿灯：`swift test --filter HealthRouteTests/testLeaderboardRoutesSeparateSpeedBucketsByConfiguredLimit`。
- 原生旧/新响应兼容：`swift test --filter TypingEngineTests/testLeaderboardPageCompatibilityGatesPaginationForLegacyResponses`。
- 原生筛选互斥策略：`swift test --filter TypingEngineTests/testLeaderboardParameterFilterKeepsTimeAndWordBucketsMutuallyExclusive`。
- 收尾前会串行运行服务端和原生完整测试；不启动 Typebar 图形程序。
