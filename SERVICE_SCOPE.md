# 自建服务范围

Typebar 的远程功能必须使用自建身份、数据库和 API，不能访问或代理 Monkeytype 的服务。

第一批契约：

- 身份：注册、登录、设备会话、密码重置、邮箱验证、账户删除与受限开发者密钥。
- 同步：设置、结果、预设、主题和标签的增量上传、下载与冲突解决。
- 社交：公开资料、好友请求、屏蔽、通知与举报。
- 排行榜：经过服务端验证的结果提交、全局/每日/好友 WPM 榜与 ISO 本周 XP 榜。
- 内容：引语提交、收藏、评分、审核与举报。

安全门槛：速率限制、结果签名/行为校验、审计记录、最小化数据保留和用户导出/删除。开发者密钥只允许读取或上传其所有者的成绩元数据，明文仅在创建时显示，服务端只保存哈希。

账户邮件：`POST /v1/auth/password-reset/request`、`POST /v1/auth/password-reset/complete`、`POST /v1/auth/email-verification/request` 与 `POST /v1/auth/email-verification/complete` 已实现。部署者设置 `TYPEBAR_PASSWORD_RESET_WEBHOOK_URL`（必须是 HTTPS）后，密码重置继续向该受信任 webhook 发送邮箱、一次性码与过期时间；验证邮件在相同字段外附加 `kind: "emailVerification"`，以兼容既有重置收件端。可选 `TYPEBAR_PASSWORD_RESET_WEBHOOK_TOKEN` 作为 Bearer 认证。服务端只持久化令牌 SHA-256 哈希：重置码 20 分钟后过期、只能消费一次，完成重置会撤销所有会话且不自动登录；注册和改邮箱会自动投递验证邮件，验证码 24 小时后过期、只能消费一次，手动重发或改邮箱会撤销旧码，完成验证不轮换会话。重置请求对已注册、未知和无效邮箱给出相同响应；投递失败会撤销新令牌。未配置投递时能力接口如实标为计划中，相关请求返回 `503`。

当前状态：`server/` 是独立的 Vapor 服务。已提供并验证 `GET /health`、`GET /v1/capabilities`、`POST /v1/auth/register`、`POST /v1/auth/login`、`POST /v1/auth/password-reset/request`、`POST /v1/auth/password-reset/complete`、`POST /v1/auth/email-verification/request`、`POST /v1/auth/email-verification/complete`、`POST /v1/auth/password`、`POST /v1/auth/email`、`DELETE /v1/auth/account`、`GET /v1/profiles?query=`、`GET /v1/profiles/{id}`、`GET/PATCH /v1/profiles/me`、`GET/POST /v1/connections`、`POST /v1/connections/{requesterID}/accept`、`DELETE /v1/connections/{userID}`、`GET /v1/notifications`、`POST /v1/notifications/{id}/read`、`POST /v1/reports/profiles`、`GET /v1/moderation/profile-reports`、`PATCH /v1/moderation/profile-reports/{id}`、`POST /v1/reports/quotes`、`GET/POST /v1/sync`、`POST /v1/results`、`GET /v1/leaderboards`、`GET /v1/leaderboards/friends`、`GET /v1/leaderboards/experience`、`GET /v1/leaderboards/experience/friends`、`GET /v1/quotes`、`POST /v1/quotes`、`PUT /v1/quotes/{id}/rating`、`GET /v1/moderation/quotes` 与 `PATCH /v1/moderation/quotes/{id}`。身份基础会验证邮箱/显示名/密码长度，使用 bcrypt 哈希密码，生成随机 30 天访问令牌，并原子写入服务端自己的 JSON 用户库；更新密码、更新邮箱和删除账户均要求旧密码，前两者会撤销该账户的既有会话并发行一个新令牌，邮箱另校验格式与唯一性、将验证状态复位并撤销旧验证码；删除账户会清除服务端所有用户作用域数据。公开搜索只按展示名匹配，且不返回邮箱；资料、同步、好友关系、通知、举报、好友榜与提交成绩要求 Bearer 令牌。资料和引语举报均私有保存、不通知目标且不自动处罚；重复同类举报及自举报会拒绝。部署者配置 `TYPEBAR_MODERATION_TOKEN` 后，可用相同密钥读取按状态筛选的资料或引语审核队列；资料队列只含目标的公开资料、分类、说明和状态，引语队列只含引语和举报原因/说明，两者均不含举报者身份。资料举报审核只更新私有处理状态，绝不自动改变被举报账户。已审核社区引语可由非作者登录用户一人一票评分、改评或撤销，公共列表仅展示聚合票数；评分与相关投稿或账户一并删除。同步变更按用户、UUID、版本与游标存储；版本未前进时返回冲突。成绩按用户保存，重复 UUID 提交幂等；WPM 排行榜可按模式、语言、服务端当天或 ISO 本周筛选，先按 WPM、准确率和完成时间选定每位用户最佳的一次成绩，再按该成绩排序；好友榜仅聚合当前用户及已接受好友。另有按 ISO 本周聚合、最多 100 人的全局与好友 XP 榜：XP 只由服务端从已验证成绩的时长、准确率和模式重算，禅模式为零，重复成绩 ID 不重复奖励。默认数据目录为启动目录下的 `typebar-server-data`，可用 `TYPEBAR_DATA_DIRECTORY` 重设。

当前限制：通用令牌认证中间件、数据库迁移与部署仍未实现。服务端已有自有进程内固定窗口限速：注册/登录按来源 10 次/分钟，密码重置与邮箱验证请求各按来源每 15 分钟 3 次，成绩提交按访问令牌 30 次/分钟，其余写操作按令牌 60 次/分钟，读取接口 180 次/分钟；达到限制返回 `429` 和 `Retry-After`。部署者可用 `TYPEBAR_MAINTENANCE_MODE=true` 启动维护模式；它保留 `GET /health`（响应会标记 `maintenanceMode: true`）和全部只读请求，同时以 `503`、`Retry-After: 300` 与 `X-Typebar-Maintenance: true` 拒绝一切写请求，客户端会提示本机离线练习仍可继续。账户可通过 `PATCH /v1/profiles/me` 设置 `leaderboardOptedOut: true`，立即从全局及好友 WPM/XP 榜排除，绝不删除其成绩、XP 或同步记录。限速器不记录令牌、邮箱或正文，但重启会清空，且没有分布式协调、持久化审计或异常登录惩罚。同步没有分页/批量上限、不可自动合并文本副本、主题冲突分支或服务端审计。结果接口只做请求形状、合理数值和时间窗口检查，尚未具备签名、事件回放或反作弊；客户端仅在用户明确开启后提交完成成绩，并只能浏览基础全局/好友榜和不含邮箱的基础公开资料。资料与引语审核队列都只能由单个部署密钥访问，原生设置页已有两类队列工作台，密钥只保存在当前内存会话，队列不显示举报者身份；资料举报只能标记已处理或驳回，不能自动处置账户。细粒度审核权限与申诉流程尚未实现。服务端已有最小展示名搜索与好友请求/接受/解除关系、屏蔽及关系事件通知，并支持已接受好友间的受控私信；推送和内容 API 仍按本文档与 [SERVICE_CONTRACTS.md](SERVICE_CONTRACTS.md) 逐项建设。

成绩校验更新：上段关于“只做请求形状”的描述已过期。当前成绩接口会验证输入量/错误数、准确率、raw/WPM 与起止耗时的数学一致性；计时成绩还会核对实际耗时与配置时长。仍未具备不可伪造签名或完整事件回放。

私有成绩读取更新：`GET /v1/results` 和 `GET /v1/results/{id}` 已实现；只返回认证账户已提交成绩的最小元数据，按完成时间倒序，列表可按 UTC 秒级 `finishedOnOrAfter`、`offset` 与最多 1,000 条的 `limit` 分页。Bearer 令牌和受限开发者密钥均可访问这一用户作用域资源；密钥不能访问任何资料、同步或账户路由。
