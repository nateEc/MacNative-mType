# 官方显示名整改要求审计

固定参考提交：`91bd24bb8513785c7364cbea29296ff7adafac41`。

## 参考可见契约

固定参考的账户状态包含“需要改名”。该状态会使服务端拒绝新的成绩提交，也会从排行榜资格条件中排除该账户；账户成功更新名称后会清除该状态，前端会提示用户完成名称更新。其专用显示名更新还要求名称在大小写与重音无关的比较下可用；正常账户成功改名后会记录时间，并在严格不足 30 天时拒绝再次改名。被要求改名的账户可优先提交一次实际不同的可用名称来解除要求。

## Typebar 原生映射

Typebar 新增独立、可逆的“显示名整改要求”。自建服务部署者凭仅内存审核密钥，通过私有审核工作台设置或撤销它。设置后，账户仍可登录、浏览、同步和进行本机练习；但服务端在保存成绩前拒绝新的成绩提交，且该账户立即从全局、好友、个人 WPM 与 XP 榜排除。账户本人仅在自己的账户与排行榜界面看到行动提示，部署方只在私有资料审核队列看到状态；公开资料、公开榜单、好友资料和举报者身份均不包含它。

整改要求在 Typebar 已有显示名规则下，只会在账户提交一个实际不同且有效的显示名后自动解除。提交原名称、仅编辑其他资料、重启服务或执行完整账户重置均不能绕过要求。撤销要求不会删除历史成绩、XP、个人最佳、归档、本机历史或同步数据；解除后，既有满足其他资格条件的成绩会重新计算榜单资格。旧服务响应和旧持久化状态缺字段时安全默认为未要求整改。

Typebar 同时以自有 Swift/Vapor 实现补齐正常显示名的可用性与冷却：密码注册、直接 OAuth 注册、完成 OAuth 注册以及后续改名都会拒绝已被其他账户使用的大小写/重音等价名称。新账户及旧持久化记录没有改名时间时可立即完成一次改名；一旦实际名称改变，服务端私有地持久化时间，在不足 30 个 24 小时内拒绝下一次真实改名，恰好满 30 天允许。只更新隐身或其他资料、提交同一名称、登录方式/邮箱变更和账户重置都不会消除或刷新该冷却；部署方已经设置整改要求时，账户可立即用实际不同的可用名称解除要求。该私有时间不进入公开资料、排行榜或账户响应。

固定参考的注册、第三方补名和改名输入均会在停止输入约一秒后预检名称。Typebar 以原创只读 `GET /v1/profiles/display-name-availability?name=` 映射这一反馈：它只返回布尔可用性、不会预留名称或返回账户资料，仍由注册与改名写入端作最终原子校验。匿名调用用于密码注册与 OAuth 补名；带有效 Bearer 令牌时会排除当前账户，以支持仅改大小写/重音的预检。三个原生输入同样采用一秒防抖，切换服务器或继续输入会丢弃过期结果；旧服务或临时网络失败只提示预检不可用，不会阻止最终提交。该公开布尔查询受既有读取限速保护，且显示名本已可通过公开资料搜索发现。

历史服务状态如已存在重复展示名，不会在升级时自动合并、改写或删除账户：它们仍可登录和读取现有资料，但新注册和任何实际改名将按新可用性规则验证。

## 重写边界

这不是参考项目的源码、数据或账户治理模型移植。Typebar 不实现参考的姓名黑名单、姓名历史、姓名要求理由、举报者披露或自动处罚；也不读取、打包或运行参考的 MongoDB 查询、前端组件、文案、资产或用户数据。是否设置整改要求始终是部署方的显式、可撤销决定，资料举报不会自动触发它。

## 验证

- 核心链路：`swift test --filter HealthRouteTests.testDisplayNameRequirementBlocksServerResultsUntilTheNameActuallyChanges`，覆盖即时榜单排除、成绩拒绝、相同名称不解除与实际改名恢复。
- 权限与可逆性：`swift test --filter HealthRouteTests.testDisplayNameRequirementRouteRequiresDeploymentKeyAndIsReversible`，覆盖无部署密钥拒绝、受密钥设置与撤销。
- 持久化与防绕过：`swift test --filter HealthRouteTests.testDisplayNameRequirementPersistsAndSurvivesAccountReset`，覆盖服务重载与账户重置。
- 可用性、冷却与迁移：`swift test --filter HealthRouteTests.testDisplayNameAvailabilityAndCooldownPersistWithoutBlockingRequiredRename`，覆盖大小写/重音等价的密码与 OAuth 注册拒绝、无关资料更新不刷新冷却、重载后仍生效、30 天边界和整改要求的优先改名。
- 可用性预检：`swift test --filter HealthRouteTests.testDisplayNameAvailabilityRouteSupportsPublicAndAuthenticatedChecks`，覆盖匿名占用/空闲查询、当前账户大小写变体的可用例外与非法名称拒绝。
- 原生预检状态：`swift test --filter TypingEngineTests.testDisplayNameAvailabilityStateBlocksOnlyKnownUnavailablePreflight`，覆盖检查中/已占用时阻止提交，以及旧服务或临时失败时保留最终写入机会。
- HTTP 契约：`swift test --filter HealthRouteTests.testProfileRouteReportsDisplayNameCooldownAsConflict`，覆盖第二次改名返回明确的 `409`。
- 原生协议兼容：`swift test --filter 'TypingEngineTests.test(RemoteAccountUserDefaultsLegacyServersToPasswordAndDecodesOAuthMethods|LeaderboardRankResponsesDecodeAnAbsentStanding|ModerationProfileReportDefaultsAndDecodesDeploymentAccountControls)'`，覆盖账户、资格和审核队列的旧字段回退及新字段解码。
- 已串行验收：服务端 `swift test` 100 项、0 失败（1.242 秒）；原生 `swift test` 651 项、0 失败（160.958 秒）。全程未启动 Typebar 图形程序，结束时未留下 Typebar、xctest 或 Swift 测试进程。
