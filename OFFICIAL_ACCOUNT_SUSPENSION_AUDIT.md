# 官方账户封禁审计

固定参考提交：`91bd24bb8513785c7364cbea29296ff7adafac41`。

## 参考可见契约

固定参考的管理员操作会切换账户 `banned` 状态，并在封禁时清除日榜与周 XP 榜展示。排行榜查询排除该状态；公开资料保留基础资料后不再返回扩展资料。参考控制器还拒绝已封禁账户的账户重置、显示名更改和公开资料更新。该参考路径本身不把“已封禁”定义成禁止登录、删除账户或一律拒绝成绩保存。

## Typebar 原生映射

Typebar 的部署方可在私有审核工作台明确设置或撤销 `accountSuspended`。设置后，公共、好友和个人 WPM/XP 榜立即排除该账户；公开资料仍提供基础统计和个人最佳，但隐藏可编辑详情、活动、连胜、徽章与头像。服务端仍验证并保存该账户的新成绩，回执则标记为不具备共享榜资格。

封禁期间服务端拒绝公开资料更新和完整账户重置；登录、同步、本机练习、已有成绩、成绩读取、密码、认证方式及删号保持可用。撤销后，既有满足其他规则的成绩会重新进入共享榜，公开资料也恢复完整展示。状态同时回传给账户本人、公开资料和部署方私有审核队列；老服务响应及旧 JSON 状态未出现该字段时，原生客户端和服务端均安全地当作未封禁。

## 重写边界

这是 Typebar 的独立 Swift/Vapor 实现，不复用参考的 TypeScript、MongoDB 查询、前端组件、文案、资产、用户数据或外部账号联动。Typebar 不实现自动封禁、反作弊触发、外部 Discord 同步、封禁原因、举报者披露、申诉、角色体系或参考的账户黑名单；资料举报从不自动处罚。

## 验证

- `swift test --filter HealthRouteTests.testAccountSuspension`：覆盖可逆状态、即时 WPM/XP 榜排除、成绩继续保存但回执失去资格、公开资料降级、资料/重置拒绝、部署密钥和 JSON 持久化。
- `swift test --filter 'TypingEngineTests.test(RemoteAccountUserDefaultsLegacyServersToPasswordAndDecodesOAuthMethods|LeaderboardRankResponsesDecodeAnAbsentStanding|ModerationProfileReportDefaultsAndDecodesDeploymentAccountControls|LegacyPublicProfileResponseDefaultsMissingHighestConsistencyToZero)'`：覆盖账户、资格、审核队列和公开资料的新旧协议解码。
- 已串行验收：服务端 `swift test` 97 项、0 失败（1.221 秒）；原生 `swift test` 650 项、0 失败（161.373 秒）。全程未启动 Typebar 图形程序，结束时未留下 Typebar、xctest 或 Swift 测试进程。
