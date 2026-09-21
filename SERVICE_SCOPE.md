# 自建服务范围

Typebar 的远程功能必须使用自建身份、数据库和 API，不能访问或代理 Monkeytype 的服务。

第一批契约：

- 身份：注册、登录、设备会话、密码重置、邮箱验证、账户删除与受限开发者密钥。
- 同步：设置、结果、预设、主题和标签的增量上传、下载与冲突解决。
- 社交：公开资料、好友请求、屏蔽、通知与举报。
- 排行榜：经过服务端验证的结果提交、全局/每日/昨日/好友 WPM 榜与 ISO 本周/上周 XP 榜，以及常规会话的自身排名。
- 内容：引语提交、收藏、评分、审核与举报。

安全门槛：速率限制、结果签名/行为校验、审计记录、最小化数据保留和用户导出/删除。开发者密钥只允许读取或上传其所有者的成绩元数据，明文仅在创建时显示，服务端只保存哈希。

账户邮件：`POST /v1/auth/password-reset/request`、`POST /v1/auth/password-reset/complete`、`POST /v1/auth/email-verification/request` 与 `POST /v1/auth/email-verification/complete` 已实现。部署者设置 `TYPEBAR_PASSWORD_RESET_WEBHOOK_URL`（必须是 HTTPS）后，密码重置继续向该受信任 webhook 发送邮箱、一次性码与过期时间；验证邮件在相同字段外附加 `kind: "emailVerification"`，以兼容既有重置收件端。可选 `TYPEBAR_PASSWORD_RESET_WEBHOOK_TOKEN` 作为 Bearer 认证。服务端只持久化令牌 SHA-256 哈希：重置码 20 分钟后过期、只能消费一次，完成重置会撤销所有会话且不自动登录；注册和改邮箱会自动投递验证邮件，验证码 24 小时后过期、只能消费一次，手动重发或改邮箱会撤销旧码，完成验证不轮换会话。重置请求对已注册、未知和无效邮箱给出相同响应；投递失败会撤销新令牌。未配置投递时能力接口如实标为计划中，相关请求返回 `503`。

外部人机验证：部署者可同时设置 `TYPEBAR_TURNSTILE_SITE_KEY`、`TYPEBAR_TURNSTILE_SECRET` 与 `TYPEBAR_TURNSTILE_ALLOWED_HOSTNAMES`（逗号分隔的 Turnstile hostname）。三项完全缺失时服务保持兼容模式，`/v1/capabilities` 将 `humanVerification` 报告为 `planned`；任一项缺失、为空或 hostname 非法时服务拒绝启动，防止误以为已受保护。三项完整时，服务把能力报告为 `available`，并在注册、密码重置请求、资料举报、社区引语投稿和引语举报前要求一个 5 分钟内、单用途且只能消费一次的证明。macOS 仅在能力为 `available` 时通过系统认证会话打开服务自身的最小 Turnstile 页；私密 key、第三方 token 和证明不进入客户端持久化、日志或服务端数据文件。公开部署须使用 HTTPS，且 Turnstile 配置必须包含服务的公开 hostname；真实密钥绝不提交到仓库。

当前状态：`server/` 是独立的 Vapor 服务。已提供并验证 `GET /health`、`GET /v1/capabilities`、`POST /v1/human-verification/challenges`、`GET /v1/human-verification/challenges/{id}/web`、`POST /v1/human-verification/challenges/{id}/complete`、`POST /v1/auth/register`、`POST /v1/auth/login`、`POST /v1/auth/password-reset/request`、`POST /v1/auth/password-reset/complete`、`POST /v1/auth/email-verification/request`、`POST /v1/auth/email-verification/complete`、`POST /v1/auth/password`、`POST /v1/auth/email`、`DELETE /v1/auth/account`、`GET /v1/profiles?query=`、`GET /v1/profiles/display-name-availability?name=`、`GET/PATCH /v1/profiles/me`、`GET/POST /v1/connections`、`POST /v1/connections/{requesterID}/accept`、`DELETE /v1/connections/{userID}`、`GET /v1/notifications`、`POST /v1/notifications/{id}/read`、`GET /v1/announcements`、`POST /v1/moderation/announcements`、`DELETE /v1/moderation/announcements/{id}`、`POST /v1/reports/profiles`、`GET /v1/moderation/profile-reports`、`PATCH /v1/moderation/profile-reports/{id}`、`POST /v1/reports/quotes`、`GET/POST /v1/sync`、`POST /v1/results`、`GET /v1/leaderboards`、`GET /v1/leaderboards/rank`、`GET /v1/leaderboards/friends`、`GET /v1/leaderboards/friends/rank`、`GET /v1/leaderboards/experience`、`GET /v1/leaderboards/experience/rank`、`GET /v1/leaderboards/experience/friends`、`GET /v1/leaderboards/experience/friends/rank`、`GET /v1/quotes`、`POST /v1/quotes`、`PUT /v1/quotes/{id}/rating`、`GET /v1/moderation/quotes` 与 `PATCH /v1/moderation/quotes/{id}`。身份基础会验证邮箱/显示名/密码长度，使用 bcrypt 哈希密码，生成随机 30 天访问令牌，并原子写入服务端自己的 JSON 用户库；更新密码、更新邮箱和删除账户均要求旧密码，前两者会撤销该账户的既有会话并发行一个新令牌，邮箱另校验格式与唯一性、将验证状态复位并撤销旧验证码；删除账户会清除服务端所有用户作用域数据。公开搜索只按展示名匹配，且不返回邮箱；同一公开读路径还可只读取一个名称的可用性，不会预留名称或返回资料，认证账户查询自身名称时可正确排除自己。资料、同步、好友关系、通知、举报、好友榜、当前账户排名与提交成绩要求 Bearer 令牌。资料和引语举报均私有保存、不通知目标且不自动处罚；重复同类举报及自举报会拒绝。部署者配置 `TYPEBAR_MODERATION_TOKEN` 后，可用相同密钥读取按状态筛选的资料或引语审核队列，并发布或删除公告；公告公开读取、不需要账户，内容限 1–500 字，可附加计划日期；有计划日期时，原生客户端会把正文中的 `{date}`、`{dateNoTime}` 和 `{dateDifference}` 按当前地区替换为日期时间、日期或相对时间。普通公告只可由客户端本机关闭，置顶公告持续展示至删除。资料队列只含目标的公开资料、分类、说明和状态，引语队列只含引语和举报原因/说明，两者均不含举报者身份。资料举报审核只更新私有处理状态，绝不自动改变被举报账户。已审核社区引语可由非作者登录用户一人一票评分、改评或撤销，公共列表仅展示聚合票数；评分与相关投稿或账户一并删除。同步变更按用户、UUID、版本与游标存储；版本未前进时返回冲突。成绩按用户保存，重复 UUID 提交幂等；WPM 排行榜可按模式、语言、服务端当天、前一个完整日或 ISO 本周筛选，先按 WPM、准确率和完成时间选定每位用户最佳的一次成绩，再按该成绩排序；好友榜仅聚合当前用户及已接受好友。常规会话可读取同一排序中的自身 WPM 或 XP 条目，即使其名次超出公开列表的前 100 名；开启隐身或没有合资格成绩时返回空值。另有按 ISO 本周或前一完整周聚合、最多 100 人的全局与好友 XP 榜：客户端以 `period=week` 或 `period=lastWeek` 请求，服务端会回显范围；XP 只由服务端从已验证成绩的时长、准确率和模式重算，禅模式为零，重复成绩 ID 不重复奖励。默认数据目录为启动目录下的 `typebar-server-data`，可用 `TYPEBAR_DATA_DIRECTORY` 重设。

公开练习统计：`GET /v1/public/practice-stats` 与 `GET /v1/public/speed-distribution` 是无认证只读接口，并由能力键 `publicPracticeStatistics=available` 声明。前者仅返回完成成绩数、开始测试数与完成成绩的实际累计秒数；后者固定聚合 English、60 秒、time 成绩，每账户只取一个最高 WPM，按十 WPM 的非空桶返回。两个响应都不返回账户、邮箱、提示、输入、回放、令牌、单条时间戳或单条成绩。开启隐身、被排行榜限制、要求改名或被封禁的账户立即不贡献公开统计；解除相应状态后才会重新纳入既有合格结果。macOS 只在 About 窗口打开或用户明确重读时无令牌请求，旧服务或网络失败会在窗口中如实显示不可用，绝不以本机历史伪造全局数据。

当前限制：通用令牌认证中间件、数据库迁移与部署仍未实现。服务端已有自有进程内固定窗口限速：注册/登录按来源 10 次/分钟，密码重置与邮箱验证请求各按来源每 15 分钟 3 次，成绩提交按访问令牌 30 次/分钟，其余写操作按令牌 60 次/分钟，读取接口 180 次/分钟；达到限制返回 `429` 和 `Retry-After`。部署者可用 `TYPEBAR_MAINTENANCE_MODE=true` 启动维护模式；它保留 `GET /health`（响应会标记 `maintenanceMode: true`）和全部只读请求，同时以 `503`、`Retry-After: 300` 与 `X-Typebar-Maintenance: true` 拒绝一切写请求，客户端会提示本机离线练习仍可继续。账户可通过 `PATCH /v1/profiles/me` 设置 `leaderboardOptedOut: true`，立即从全局及好友 WPM/XP 榜排除，绝不删除其成绩、XP 或同步记录。限速器不记录令牌、邮箱或正文，但重启会清空，且没有分布式协调、持久化审计或异常登录惩罚。同步拉取已有每页上限；服务端仍以整包归档版本为粒度，不做内容级三方合并或冲突审计。原生客户端会在版本冲突时保留本机设置，合并双方成绩，并将冲突的远端预设、文本、主题和自定义键盘布局另存为带标记副本后重试上传。结果接口只做请求形状、合理数值和时间窗口检查，尚未具备签名、事件回放或反作弊；客户端仅在用户明确开启后提交完成成绩，并只能浏览基础全局/好友榜和不含邮箱的基础公开资料。资料与引语审核队列都只能由单个部署密钥访问，原生设置页已有两类队列工作台，密钥只保存在当前内存会话，队列不显示举报者身份；资料举报只能标记已处理或驳回，不能自动处置账户。细粒度审核权限与申诉流程尚未实现。服务端已有最小展示名搜索与好友请求/接受/解除关系、屏蔽及关系事件通知，并支持已接受好友间的受控私信；推送和内容 API 仍按本文档与 [SERVICE_CONTRACTS.md](SERVICE_CONTRACTS.md) 逐项建设。

人机验证的运行限制：挑战及其消费状态是单个服务进程内的短期内存状态；进程重启会让未完成或未消费证明安全失效。当前不得以多副本或负载均衡部署该功能；扩容前必须使用共享、原子、带 TTL 的挑战存储，不能把黏性会话当作安全替代。自动化测试通过注入的 Siteverify 响应验证协议和错误路径，不会请求 Cloudflare；部署验收仍需要部署者在真实 HTTPS hostname 与自己的 Turnstile 密钥下手动完成一次挑战。

成绩校验更新：上段关于“只做请求形状”的描述已过期。当前成绩接口会验证输入量/错误数、准确率、raw/WPM 与起止耗时的数学一致性；计时成绩还会核对实际耗时与配置时长。仍未具备不可伪造签名或完整事件回放。

私有成绩读取更新：`GET /v1/results` 和 `GET /v1/results/{id}` 已实现；只返回认证账户已提交成绩的最小元数据，按完成时间倒序，列表可按 UTC 秒级 `finishedOnOrAfter`、`offset` 与最多 1,000 条的 `limit` 分页。Bearer 令牌和受限开发者密钥均可访问这一用户作用域资源；密钥不能访问任何资料、同步或账户路由。

私有成绩标签更新：`PATCH /v1/results/{id}/tags` 已实现；只有 Bearer 会话可编辑当前账户自己的一条成绩，标签最多五个，每个去首尾空白后为 1–24 个字符，按大小写与重音无关的比较不得重复。开发者密钥保持只能读取或上传成绩，不能编辑标签；旧数据缺少标签时按空数组返回。

远端成绩删除更新：`DELETE /v1/results` 已实现，且仅接受 Bearer 令牌。密码账户必须提供当前密码，纯第三方账户必须提交一次性重新验证凭据；每令牌每小时最多 10 次。它只删除当前账户的远端成绩及相应 XP，不删除本机历史、同步数据或其他账户数据，开发者密钥无法调用。

成绩回执更新：当天完成且未退出排行榜的成绩会返回同模式、同语言的当前全局 WPM 日榜名次；结果页可据此打开预设为相同筛选的现有排行榜。该字段可选，旧服务与旧客户端均可继续工作。重复 UUID 的回执始终从首次保存的权威记录生成，重试正文不能改变 XP 回执或榜单筛选。

账户治理更新：部署者可凭 `TYPEBAR_MODERATION_TOKEN` 和 `X-Typebar-Moderation-Key` 设置或撤销共享排行榜限制、独立的显示名整改要求，以及独立的账户封禁。显示名整改会立即将账户从公共、好友和个人 WPM/XP 榜排除，并在保存前拒绝新的服务端成绩；只有用户提交一个实际不同且有效的显示名才会自动解除。账户封禁也会排除共享榜，却仍接受和保存成绩；它只把公开资料降级为基础统计和个人最佳，并拒绝资料更新与账户重置。封禁不会暂停登录、同步、本机练习、密码或删号，也不会删除历史数据；撤销后既有合格成绩会重新纳入共享榜。三项状态由部署者显式、可逆设置，旧响应和旧持久化缺字段时默认未设置；不实现自动封禁、反作弊判定、原因/举报者披露、外部账号联动、申诉或细粒度审核角色。

显示名可用性更新：密码/OAuth 注册与后续实际改名现在拒绝其他账户以大小写或重音等价方式使用的展示名。新账户与旧 JSON 状态缺少改名时间时可立即改名；成功的实际改名只在服务端私有持久化时间，严格不足 30 个 24 小时会返回冲突，恰好到期允许。隐身/其他资料、认证方式/邮箱变更和账户重置均不会清除或刷新冷却；部署方已设置显示名整改要求时，账户可以优先改为不同的可用名称。既有重复名状态不会在升级时自动合并、改写或删号，仍可登录读取，但新注册和未来实际改名会按可用性规则验证；不实现官方姓名黑名单、姓名历史或自动处罚。
