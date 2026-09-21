# 排行榜相对名次审计

固定参考提交：`91bd24bb8513785c7364cbea29296ff7adafac41`。

## 参考可见契约

个人排名卡在有名次和榜单总人数时，以 `rank / total` 计算相对位置并保留两位小数；第一名使用单独的榜首状态。总人数或名次尚在加载时不会猜测百分位。此信息与上次查看的名次变化并列呈现。

## Typebar 原生映射

Typebar 新增独立的 `LeaderboardRankStanding`。它只接受当前个人名次和同一次、同一筛选、同一范围的自建服务分页响应中的 `total`：第一名显示 Typebar 自有的“榜首”，其他有效名次显示“前 X.XX%”。速度和 XP 榜复用该策略，且名次变化仍保持原有行为。

## 兼容与重写边界

旧自建服务返回仅有条目的历史响应时没有 `total`，策略返回空，原生界面继续只显示既有 `#N`，不会从当前页条数推断总体。无效名次、零人数或名次超过总数也不显示相对位置。该增量不修改服务端接口、成绩、XP、账户、同步、提示、输入或任何参考代码、文案、资产与数据。

## 验证

- `swift test --filter TypingEngineTests/testLeaderboardRankStandingUsesOnlyTheConfirmedFilteredPopulation`：覆盖榜首、普通百分位、末位以及缺失/非法总数。
- 已串行验收：原生 `swift test` 649 项、0 失败（164 秒）。全程未启动 Typebar 图形程序，结束时未留下 Typebar、`xctest` 或 Swift 测试进程。
