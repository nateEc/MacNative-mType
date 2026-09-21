# 排行榜累计练习资格审计

固定参考提交：`91bd24bb8513785c7364cbea29296ff7adafac41`。

## 参考可见契约

参考的配置 schema 将 `leaderboards.minTimeTyping` 定义为进入排行榜前需要的累计打字秒数；默认服务配置为两小时。排行榜更新会排除未超过该门槛、被封禁、主动隐藏或需要改名的账户。排行榜页面在个人没有名次时优先说明隐藏状态、账户状态、累计练习尚未达到门槛或当前筛选不合格；结果提交回执也以同一资格判断是否返回日榜名次。

## Typebar 原生映射

| 参考可见意图 | Typebar 原生实现 | 边界 |
| --- | --- | --- |
| 以累计练习建立共享榜资格 | 服务启动时读取 `TYPEBAR_LEADERBOARD_MIN_PRACTICE_SECONDS`，默认 7,200 秒 | 只接受 0 至一年；非法值使启动失败 |
| 合格前不出现于速度或 XP 榜 | `AuthStore` 从已接受服务端成绩的开始/结束时间累计，并以严格大于门槛判断 | 不使用客户端传入的累计值，也不读取提示或回放 |
| 没有个人名次时说明原因 | 认证个人排名响应返回仅属于当前账户的 `LeaderboardEligibility`，原生同步窗口显示剩余练习时长 | 公开榜、公开资料及好友条目不返回他人的累计时长 |
| 历史与部署兼容 | 门槛是启动配置，成绩数据无需迁移；旧响应中资格字段可缺失 | 旧自建服务仍保持既有的“无有效成绩”呈现 |

## 重写与隐私边界

这套策略由 Typebar 的 Swift/Vapor 服务独立实现，不复制参考的 MongoDB 聚合、配置代码、文案、账户字段或任何成绩内容。Typebar 只聚合自己已接受结果中的两个时间戳，资格摘要仅由已认证的个人排名路由返回。改变门槛只重新解释现有榜单可见性：不会删除、重写或导出成绩、XP、个人最佳、同步档案、本机历史、提示、输入或凭据。

## 验证

- 行为红灯与绿色：`swift test --filter HealthRouteTests/testLeaderboardQualificationRequiresPracticeBeyondConfiguredThreshold`；验证未满、恰好门槛和超过门槛的 WPM/XP 榜、个人响应与提交回执。另以 `testLeaderboardQualificationUsesFractionalAcceptedPracticeTimeForItsStrictBoundary` 验证 120.5 秒会超过 120 秒门槛，整数秒只用于进度显示。
- 原生旧/新协议：`swift test --filter TypingEngineTests/testLeaderboardRankResponsesDecodeAnAbsentStanding`；验证资格字段缺失时安全回退，以及新字段可解码。
- 已串行验收：服务端 `swift test` 88 项、0 失败；原生 `swift test` 648 项、0 失败（162 秒）。全程未启动 Typebar 图形程序，结束时未留下 Typebar、`xctest` 或 Swift 测试进程。
