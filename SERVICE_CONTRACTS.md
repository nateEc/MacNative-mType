# 服务端契约 v1（草案）

所有响应使用 JSON。账户管理使用 Typebar 发行的短期访问令牌；读取或上传自己的服务端成绩还可使用受限的开发者密钥。客户端不会发送原始密码以外的敏感本地数据。

服务运行时会以 Typebar 自有固定窗口策略限制请求：注册/登录为每来源 10 次/分钟，密码重置与验证邮件请求各为每来源 15 分钟 3 次，成绩提交为每令牌 30 次/分钟，其余写操作为每令牌 60 次/分钟，读取接口为每键 180 次/分钟。拒绝响应为 `429`，含 `Retry-After` 和 `X-RateLimit-Remaining: 0`；计数只在进程内保存，重启后清空。部署者可设置 `TYPEBAR_MAINTENANCE_MODE=true`：健康检查和只读请求仍可访问，所有写请求统一得到 `503`、`Retry-After: 300`、`X-Typebar-Maintenance: true` 与提示本机离线练习可继续的 JSON reason。

| 操作 | 方法与路径 | 核心请求 / 响应 |
| --- | --- | --- |
| 注册 | `POST /v1/auth/register` | 邮箱、密码、显示名 → 用户与会话（已实现服务端基础） |
| 登录 | `POST /v1/auth/login` | 邮箱、密码 → 用户与会话（已实现服务端基础） |
| 请求密码重置 | `POST /v1/auth/password-reset/request` | 邮箱 → `accepted: true`；只有配置 HTTPS 投递 webhook 时可用，已注册、未注册和无效邮箱始终得到相同响应。服务端只保存 20 分钟的一次性令牌 SHA-256 哈希；投递失败会撤销令牌（已实现） |
| 完成密码重置 | `POST /v1/auth/password-reset/complete` | 重置码、新密码 → `reset: true`；重哈希密码、消费令牌并撤销所有设备会话，不签发新会话（已实现） |
| 请求邮箱验证 | `POST /v1/auth/email-verification/request` | Bearer 令牌 → `accepted: true`；只有配置 HTTPS 投递 webhook 时可用。未验证账户会获得新的 24 小时一次性验证码，重发会撤销旧码；已验证账户不再投递（已实现） |
| 完成邮箱验证 | `POST /v1/auth/email-verification/complete` | 验证码 → `verified: true`；消费验证码并将当前账户标为已验证，不轮换会话令牌（已实现） |
| 更新密码 | `POST /v1/auth/password` | Bearer 令牌、当前密码、新密码 → 新会话；验证当前密码、bcrypt 重哈希，并撤销该账户既有会话（已实现） |
| 更新邮箱 | `POST /v1/auth/email` | Bearer 令牌、当前密码、新邮箱 → 新会话；验证当前密码、邮箱格式与唯一性，并撤销该账户既有会话（已实现） |
| 删除账户 | `DELETE /v1/auth/account` | Bearer 令牌、当前密码 → `deleted: true`；永久清除该账户的会话、成绩、同步、好友关系、屏蔽、通知、投稿、社区评分及其私有引语举报，不影响客户端本地记录（已实现） |
| 开发者密钥 | `GET/POST /v1/developer-keys`、`PATCH/DELETE /v1/developer-keys/{id}` | 管理端始终需要 Bearer 令牌。名称为 1–20 位 ASCII 字母/数字/`-`/`_` 且首位为字母或数字，每账户最多 5 个；创建响应只一次返回明文，后续仅返回名称、启用状态和时间元数据，服务端只保存 SHA-256 哈希（已实现） |
| 同步拉取 | `GET /v1/sync?cursor=` | → 变更列表、下一游标（已实现服务端基础） |
| 同步推送 | `POST /v1/sync` | 带 UUID、版本和删除标记的变更 → 接受/冲突结果（已实现服务端基础） |
| 私有成绩 | `GET /v1/results`、`GET /v1/results/{id}` | 接受 Bearer 令牌或 `X-Typebar-Access-Key`；只返回认证账户已提交成绩的最小元数据，不含提示、输入回放、邮箱或资料。列表按完成时间倒序，可用 UTC 秒级 `finishedOnOrAfter`、`offset` 和最多 1,000 条的 `limit` 过滤分页（部分实现） |
| 私有成绩标签 | `PATCH /v1/results/{id}/tags` | 仅接受 Bearer 令牌，且只可修改当前账户自己的成绩；标签为最多五个非空、去首尾空白后最长 24 个字符的字符串，不允许大小写或重音差异的重复项。旧服务或旧数据未提供标签时客户端安全回退为空数组，开发者密钥无此权限（部分实现） |
| 清除私有成绩 | `DELETE /v1/results` | 仅接受 Bearer 令牌；密码账户必须提交当前密码，纯第三方账户必须携带一次性 `X-Typebar-Reauthentication`。只删除当前账户的远端成绩与相应 XP，返回删除数量；本机历史、同步和其他账户不受影响。每令牌每小时最多 10 次（部分实现） |
| 提交结果 | `POST /v1/results` | 接受 Bearer 令牌或 `X-Typebar-Access-Key`；保存具 UUID 的结果，基本范围/时间校验与重复提交幂等；响应包含服务端重算的本次 XP、总 XP 与可选本周 XP 名次（部分实现） |
| 排行榜 | `GET /v1/leaderboards`、`GET /v1/leaderboards/friends` | 前者为公开全局结果榜；后者需要 Bearer 令牌且仅包含当前用户和已接受好友。两者都可按模式、语言与 `all`/`day`/`yesterday`/`week` 周期筛选；`yesterday` 是服务端当前日历日前的完整一天。每位用户仅保留该筛选下的最佳一条成绩，按此成绩排名，最多返回 100 位用户（部分实现） |
| 我的 WPM 排名 | `GET /v1/leaderboards/rank`、`GET /v1/leaderboards/friends/rank` | 仅接受 Bearer 令牌，使用与相应全局/好友 WPM 榜完全相同的筛选、隐身和排序规则，返回当前账户的条目或空值；结果不受列表前 100 名限制，开发者密钥无此权限（部分实现） |
| XP 排行榜 | `GET /v1/leaderboards/experience`、`GET /v1/leaderboards/experience/friends` | 前者为公开全局 ISO XP 榜；后者需要 Bearer 令牌且仅包含当前用户和已接受好友。`period` 可为 `week` 或 `lastWeek`，后者只包含前一个完整 ISO 周；响应回显实际范围，避免旧服务静默把上周请求当成本周。两者最多返回 100 位用户，返回展示名、服务端计算 XP 与名次（部分实现） |
| 我的 XP 排名 | `GET /v1/leaderboards/experience/rank`、`GET /v1/leaderboards/experience/friends/rank` | 仅接受 Bearer 令牌，按相应全局/好友 ISO 周 XP 榜的既有规则返回当前账户条目或空值；`period` 可为 `week` 或 `lastWeek`，响应回显实际范围。结果不受前 100 名列表限制，开发者密钥无此权限（部分实现） |
| 资料 | `GET /v1/profiles?query=&limit=`、`GET /v1/profiles/{id}`、`GET/PATCH /v1/profiles/me` | 公开资料仅返回展示名、加入时间与聚合成绩；可按展示名搜索（2–40 字符，最多 50 项）；本人可读取/更新显示名及 `leaderboardOptedOut`。设为 `true` 会立即从全局和好友 WPM/XP 榜移除该账户，但不删除其服务端成绩、XP 或同步数据（部分实现） |
| 好友 | `GET/POST /v1/connections`、`POST /v1/connections/{requesterID}/accept`、`DELETE /v1/connections/{userID}` | 受令牌保护的好友请求、接受、列表与解除关系（部分实现） |
| 通知 | `GET /v1/notifications`、`POST /v1/notifications/{id}/read` | Bearer 令牌保护；仅返回当前账户的好友请求、接受与新私信事件及触发者公开资料，不携带私信正文，可单条标记已读（部分实现） |
| 服务公告 | `GET /v1/announcements`、`POST /v1/moderation/announcements`、`DELETE /v1/moderation/announcements/{id}` | 读取公开且不需要账户；每项仅返回 UUID、1–500 字纯文本、等级、置顶标记、可选计划日期和发布时间。发布/删除要求部署者显式配置 `TYPEBAR_MODERATION_TOKEN`，客户端以 `X-Typebar-Moderation-Key` 提交；有计划日期时，正文的 `{date}`、`{dateNoTime}` 和 `{dateDifference}` 分别由原生客户端按当前地区替换为日期时间、日期和相对时间；普通公告可仅在当前 Mac 关闭，置顶项不能由客户端关闭，且不会携带账户、提示、输入、成绩、邮箱或令牌（已实现） |
| 资料举报与审核 | `POST /v1/reports/profiles`、`GET /v1/moderation/profile-reports`、`PATCH /v1/moderation/profile-reports/{id}` | 投稿者提交受 Bearer 令牌保护；审核读写要求部署者显式配置的 `TYPEBAR_MODERATION_TOKEN` 与 `X-Typebar-Moderation-Key`。队列可按 `open`、`resolved` 或 `dismissed` 筛选，最多 100 条，只返回目标的公开资料、分类、说明、状态和时间，绝不返回举报者身份或邮箱；审核修改只更新举报状态，不通知或自动改变目标账户（部分实现） |
| 引语举报 | `POST /v1/reports/quotes` | Bearer 令牌保护；仅可举报已批准且非本人投稿的社区引语，原因相同不可重复提交，说明最多 400 字。报告只进入私有待审核队列，不通知作者或自动下架（部分实现） |
| 社区引语评分 | `PUT /v1/quotes/{id}/rating` | Bearer 令牌保护；仅可对已批准且非本人投稿设为 `-1`、`0` 或 `1`。`0` 撤销评分；公共引语列表仅返回聚合支持/不适合计数，带本人令牌时才附带本人的评分（部分实现） |
| 私信 | `GET /v1/messages/{friendID}`、`POST /v1/messages`、`POST /v1/messages/{friendID}/read` | Bearer 令牌保护；仅双方已接受好友且未屏蔽时可读取、发送（1–1,000 字）和标记已读。屏蔽或账户删除会清除相关会话（部分实现） |
| 引语投稿与审核 | `POST /v1/quotes`、`GET /v1/quotes/mine`、`GET /v1/quotes`、`GET /v1/moderation/quotes`、`PATCH /v1/moderation/quotes/{id}` | 投稿读取受 Bearer 令牌保护并以 `pending` 保存；公共查询可按语言、最多 100 条且只返回 `approved` 内容及聚合社区评分。两个审核端点都要求部署者显式配置的 `TYPEBAR_MODERATION_TOKEN` 与 `X-Typebar-Moderation-Key`；队列可按 `pending`、`approved` 或 `rejected` 筛选，最多 100 条，并返回引语及举报原因/说明但不返回举报者身份；审核修改可设为 `approved` 或 `rejected`（部分实现） |

冲突规则：同一 UUID 使用单调版本和服务器时间；当前实现会拒绝未前进版本。不可自动合并的文本、主题和预设保留双方副本并标记冲突尚未实现。成绩接口会校验枚举、数值范围、完成时间窗口、输入量与错误数、准确率、raw/WPM 和起止耗时的相互一致性，并限制提交速率；尚未实现不可伪造的签名或完整事件回放，因此排行榜仍不应被视作可信竞赛成绩。

当前认证限制：资料、同步、好友 WPM/XP 榜、通知、资料举报、引语投稿、开发者密钥管理与账户删除均由各自路由校验 Bearer 令牌。`X-Typebar-Access-Key` 只能读取或提交其所有者的成绩元数据，不能调用其他路由；原始密钥只在创建响应中出现，服务端以哈希保存，禁用或删除后立即失效。密码或邮箱更新均要求当前密码并轮换会话令牌、撤销其他既有会话，邮箱更新还校验格式与唯一性且会清除未消费的旧验证码；账户删除会永久删除服务端所有用户作用域数据。密码重置与邮箱验证在配置 HTTPS webhook 后可用：两种令牌绝不写入持久化状态或日志，只以哈希短时保存；重置码 20 分钟过期且成功后不自动登录，验证码 24 小时过期、重发或改邮箱会撤销旧码且成功后不轮换会话。未配置投递时接口明确拒绝。资料与引语审核队列仅供持有部署密钥的运维者读取，且不包含举报者身份；资料举报的审核只改变其私有处理状态，不会自动处置账户。原生客户端提供两类队列工作台，并且审核密钥只留在当前内存会话。通用认证中间件与细粒度审核员权限模型尚未实现。原生客户端仅在用户明确启用后提交完成成绩，并可浏览自己的服务端成绩及全局或好友 WPM/XP 榜。

好友关系当前限制：只实现单向请求与双向接受后的好友关系；公开搜索仅按展示名匹配且不返回邮箱。已提供屏蔽与解除屏蔽（会移除双方关系、相关站内信并拒绝双方后续请求），以及仅展示本人和已接受好友成绩的好友榜。好友请求与接受会生成仅接收者可读取、可标记已读的站内通知；已接受好友可交换并标记已读私有站内信，但没有隐私设置或推送。原生客户端已提供搜索、请求/接受/取消/解除、屏蔽/解除屏蔽、好友榜、通知中心、好友会话、资料举报表单、社区引语举报表单及不落盘密钥的引语审核工作台。

周期语义：`day` 按服务端当前日历日计算；`week` 与 XP 榜均按 ISO 周（周一开始）计算。Typebar XP 是独立设计：服务端根据验证后的成绩时长、准确率与模式计算，禅模式不产生 XP；它不是用户本地时区、每日重置时间或赛季系统的替代品。
