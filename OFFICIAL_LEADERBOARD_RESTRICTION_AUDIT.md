# 排行榜部署限制审计

固定参考提交：`91bd24bb8513785c7364cbea29296ff7adafac41`。

## 参考可见契约

参考的排行榜资格会排除主动隐藏、被封禁或需要改名的账户；个人没有名次时会区分这些状态。成绩提交仍可被服务接受，但不为不合格账户提供排行榜名次。

## Typebar 原生映射

Typebar 新增独立的“共享排行榜限制”状态，由自建服务部署者持有的审核密钥通过私有审核工作台设置或恢复。它即时排除该账户在全局、好友、个人 WPM 与 XP 榜中的条目，并使后续成绩回执不再宣称榜单合格。账户本人只会在自己的账户与排行榜界面得到这一状态说明；公开资料、公开榜单、好友资料及举报者身份都不会得到该标记。

限制不删除成绩、XP、个人最佳、归档、本机历史或同步数据，也不影响登录和练习。恢复后，现有满足其他条件的成绩会重新参与计算。状态随自建服务归档持久化，旧归档缺少字段时安全默认为未限制；账户重置不能绕过部署方限制。

## 重写边界与待续覆盖

这是 Typebar 自有、可逆的榜单可见性策略，不复用参考的封禁字段、改名工作流、MongoDB 查询、代码、文案、资产或用户数据。它刻意不把“共享榜单限制”扩大为全账户禁用，也不自动从资料举报生成限制决定。

参考中的账户封禁与“需要改名”是不同的用户可见治理功能，仍保留在功能矩阵中，计划以独立的 Typebar 原生契约审计和实现继续覆盖；本条不将它们混同或伪称已实现。

## 验证

- 红灯到绿色：`swift test --filter HealthRouteTests.testLeaderboardRestrictionHidesExistingResultsWithoutDeletingOrBlockingPractice`，覆盖限制后 WPM/XP 全局与好友榜、个人排名和成绩回执即时失效，成绩仍可保存、恢复后重新出现。
- 权限与可逆性：`swift test --filter HealthRouteTests.testLeaderboardRestrictionRouteRequiresDeploymentKeyAndIsReversible`，覆盖无部署密钥拒绝、受密钥限制与恢复。
- 持久化与防绕过：`swift test --filter HealthRouteTests.testLeaderboardRestrictionPersistsAndSurvivesAccountReset`，覆盖服务重载和账户重置。
- 原生协议兼容：`swift test --filter TypingEngineTests.testLeaderboardRankResponsesDecodeAnAbsentStanding`，覆盖旧服务缺少限制字段时安全回退及新字段解码。
- 已串行验收：服务端 `swift test` 91 项、0 失败；原生 `swift test` 650 项、0 失败（163 秒）。全程未启动 Typebar 图形程序，结束时未留下 Typebar、`xctest` 或 Swift 测试进程。
