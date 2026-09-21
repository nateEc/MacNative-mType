# 官方排行榜名次记忆映射审计

固定参考提交：`91bd24bb8513785c7364cbea29296ff7adafac41`。

## 参考行为

固定参考的 `frontend/src/ts/components/pages/leaderboard/LeaderboardPage.tsx` 会从账户排行榜记忆计算当前名次与上次名次的差，并在读取到有效个人名次后更新该账户状态。`frontend/src/ts/components/pages/leaderboard/UserRank.tsx` 将上升、下降和不变呈现为箭头或等号，并标注为上次查看以来的变化。`packages/contracts/src/users.ts` 定义了经认证更新该记忆的请求；`backend/src/dal/user.ts` 将它保存到用户范围的数据中。

## 原生映射

| 参考可见意图 | Typebar 原生实现 | 边界 |
| --- | --- | --- |
| 查看个人名次相对上次的变化 | `LeaderboardRankChange` 与同步窗口的紧凑辅助标签 | 第一次查看没有比较基线，因此不显示虚构变化 |
| 跨设备记住上次名次 | `PUT /v1/profiles/me/leaderboard-memory` 在 `AuthStore` 中原子返回旧名次并写入新名次 | 仅认证账户可调用；内存随服务端存储重启保留 |
| 速度榜的准确比较范围 | 速度榜键含全局/好友、周期、模式、语言、时长或词数 | 不同参数桶不会互相污染“上次名次” |
| XP 榜的准确比较范围 | XP 键含全局/好友与周/上周范围 | 不附带速度榜专属字段 |
| 兼容旧自建服务 | `rankMemorySupported` 可选响应字段 | 缺失时仍显示静态个人名次，不调用未知写路由 |

## 兼容与重写边界

Typebar 以自己的 Swift/Vapor 模型和路由实现这一可见行为，不复制参考的 TypeScript、接口实现、文案、图标或用户数据结构。Typebar 的键覆盖其原生速度与 XP 榜的完整筛选范围，是面向自身服务的兼容超集；每条记录只含服务端内部的账户归属、受校验的筛选标识、名次和更新时间。

旧持久化状态没有该数组时按空状态解码，不迁移或改写既有账户、成绩、XP、好友和同步数据。重置或删除账户会删除所属名次记忆；公开资料、排行榜条目和归档均不暴露它。

## 验证记录

- 行为红灯/绿灯：`swift test --filter HealthRouteTests/testLeaderboardRankMemoryRouteReturnsPreviousRankAndIsolatesSelections`。
- 服务重启持久化：`swift test --filter HealthRouteTests/testLeaderboardRankMemoryPersistsAcrossServerStoreReload`。
- 原生变化语义：`swift test --filter TypingEngineTests/testLeaderboardRankChangeUsesOnlyConfirmedPositiveRanks`。
- 原生旧/新响应兼容：`swift test --filter TypingEngineTests/testLeaderboardPageCompatibilityGatesPaginationForLegacyResponses`。
- 验收已串行完成：服务端 `swift test` 为 85 项、0 失败；原生 `swift test` 为 648 项、0 失败（约 162 秒）。测试前后均未启动 Typebar 图形程序。
