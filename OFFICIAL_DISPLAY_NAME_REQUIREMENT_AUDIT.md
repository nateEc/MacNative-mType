# 官方显示名整改要求审计

固定参考提交：`91bd24bb8513785c7364cbea29296ff7adafac41`。

## 参考可见契约

固定参考的账户状态包含“需要改名”。该状态会使服务端拒绝新的成绩提交，也会从排行榜资格条件中排除该账户；账户成功更新名称后会清除该状态，前端会提示用户完成名称更新。

## Typebar 原生映射

Typebar 新增独立、可逆的“显示名整改要求”。自建服务部署者凭仅内存审核密钥，通过私有审核工作台设置或撤销它。设置后，账户仍可登录、浏览、同步和进行本机练习；但服务端在保存成绩前拒绝新的成绩提交，且该账户立即从全局、好友、个人 WPM 与 XP 榜排除。账户本人仅在自己的账户与排行榜界面看到行动提示，部署方只在私有资料审核队列看到状态；公开资料、公开榜单、好友资料和举报者身份均不包含它。

整改要求在 Typebar 已有显示名规则下，只会在账户提交一个实际不同且有效的显示名后自动解除。提交原名称、仅编辑其他资料、重启服务或执行完整账户重置均不能绕过要求。撤销要求不会删除历史成绩、XP、个人最佳、归档、本机历史或同步数据；解除后，既有满足其他资格条件的成绩会重新计算榜单资格。旧服务响应和旧持久化状态缺字段时安全默认为未要求整改。

## 重写边界

这不是参考项目的源码、数据或账户治理模型移植。Typebar 不实现自动重复名检测、姓名历史、30 天改名冷却、姓名要求理由、举报者披露或全账户封禁；也不读取、打包或运行参考的 MongoDB 查询、前端组件、文案、资产或用户数据。是否设置整改要求始终是部署方的显式、可撤销决定，资料举报不会自动触发它。

## 验证

- 核心链路：`swift test --filter HealthRouteTests.testDisplayNameRequirementBlocksServerResultsUntilTheNameActuallyChanges`，覆盖即时榜单排除、成绩拒绝、相同名称不解除与实际改名恢复。
- 权限与可逆性：`swift test --filter HealthRouteTests.testDisplayNameRequirementRouteRequiresDeploymentKeyAndIsReversible`，覆盖无部署密钥拒绝、受密钥设置与撤销。
- 持久化与防绕过：`swift test --filter HealthRouteTests.testDisplayNameRequirementPersistsAndSurvivesAccountReset`，覆盖服务重载与账户重置。
- 原生协议兼容：`swift test --filter 'TypingEngineTests.test(RemoteAccountUserDefaultsLegacyServersToPasswordAndDecodesOAuthMethods|LeaderboardRankResponsesDecodeAnAbsentStanding|ModerationProfileReportDefaultsAndDecodesDeploymentAccountControls)'`，覆盖账户、资格和审核队列的旧字段回退及新字段解码。
- 已串行验收：服务端 `swift test` 94 项、0 失败；原生 `swift test` 650 项、0 失败（162 秒）。全程未启动 Typebar 图形程序，结束时未留下 Typebar、`xctest` 或 Swift 测试进程。
