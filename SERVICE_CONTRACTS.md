# 服务端契约 v1（草案）

2026-10-02 最终验证（本机日期精度）：客户端 1390 项（0 跳过、0 失败，含显式十万词）、服务端 131 项、固定参考／原创性、649 场景清单和未启动 GUI 的应用包通过，下方本轮“完整门禁待执行”由此取代。未改变服务 DTO、真实存储或部署，旧二进制降级与设备验收仍未执行。

2026-10-02 本机归档精度增量（非服务 DTO 变更）：`TypebarArchive.exportedAtReferenceTime` 与 `CompletedTestResult.startedAtReferenceTime`／`finishedAtReferenceTime` 为可选 JSON 数字，按 Apple [timeIntervalSinceReferenceDate](https://developer.apple.com/documentation/foundation/date/timeintervalsincereferencedate-swift.property) 定义为距 2001-01-01 UTC 的秒。原 ISO 日期字段仍写入；补充值只恢复小于一秒的兼容差异，有限性、类型和偏离校验失败即拒绝。旧缺失／null 保留旧值，不推算历史精度。归档版本仍为 10，设置／分享版本和数据库结构不变，不新增服务器日期字段或发布流程。11 项回归覆盖旧版本形状、旧字段投影、错误单位、不同 JSON 日期策略、精度及合并导出时刻排序；投影不是实际旧二进制证据。旧客户端重新编码可丢新增键，降级前保留原始归档；本轮不操作真实库、不回填、不重发成绩、不部署。完整门禁待执行。

2026-10-01 本机派生消费补充：本机统计／历史排序与曲线／同类平均／PB 资格和提示／原创成就已读取既有精确准确率；99.6 不参与遇错停止的满分 PB，旧 nil 只按原整数消费。此改动不新增持久化字段、不改服务请求响应、不发布或回填历史。旧记录重新派生的统计、PB 和本机成就显示可能纠正，保存的成绩与远程奖励不改。原生展示经过联编而非 GUI 人工验收，先前关于这些本机路径“仍是整数消费者”的描述由本条取代；完整事件／Unicode 恢复、实际旧库升级和降级备份风险仍有效。

所有响应使用 JSON。账户管理使用 Typebar 发行的短期访问令牌；读取或上传自己的服务端成绩还可使用受限的开发者密钥。客户端不会发送原始密码以外的敏感本地数据。

## 2026-10-01 输入计量与准确率精度补充

`GET /v1/capabilities` 的 `resultInputMetrics=available` 表示支持新计量。原生客户端仅对 `apiVersion=v1`、`service=typebar` 且明确 available 的服务发送可选 `inputMetrics`；能力请求失败、旧服务、旧成绩缺少快照时不发送，不从回放补造被阻止输入。

- 请求仍保留整数 `accuracy`、`wpm`、`rawWpm`、原生书写簇 `eventCount` 和残留 `errorCount`。新增 `inputMetrics` 含 `version=1`、UTF-16 正确／总尝试 `correctAttempts`／`totalAttempts`、正确词信用 `creditedUnits` 和保留文本 `retainedUnits`，不含文本、提示、回放或键码。
- 退格不抹去尝试，错误完整词可以有正确尝试却没有词信用；因此不能用最终残留错误反推准确率，也不能用零散正确字符反推 WPM。服务验证版本、计量关系、最多 1,800,000 单位及既有范围／时间／速度一致性；旧可见字符数也在浮点转整数前检查上限。新结果无尝试准确率为 0，旧无事件请求继续按 100 处理。
- 服务私有保存计量，以同一结果 UUID 保持幂等；私有成绩、公开 PB 和榜单只增加可选 `preciseAccuracy`，不公开计量。旧 `accuracy` 类型不变；缺快照的旧成绩不推算精度。新 XP／徽章与同速排名消费两位精确准确率，99.6 不被整数显示 100 冒充满分，旧整数成绩按原值处理。
- 本机／远端 CSV 的既有 `accuracy_percent` 列保留两位小数，整数值仍用旧整数拼写，不增列；原有只按整数解析该列的外部消费者需升级。新远程表格／PB／榜单展示精度，旧响应保持整数回退；本地聚合、个人最佳、历史等更多整数消费者仍待补齐，不将此契约冒称全链路完成。
- 先升级服务端，再升级客户端；没有执行部署、回填、真实网络发布或真实账户变更。旧服务原路径仍可使用，但其残留字符模型会拒绝部分纠错／Unicode／错词成绩，需升级后才能支持新计量，不能把“字段可解码”当作全功能等价。
- 原生完成快照、JSON 归档、可空 SwiftData 数据字段及服务 JSON 存档保存新计量。旧记录保持 nil；合成混合服务存档已验证重载和幂等。真实旧 SwiftData 磁盘库升级、实际部署／TLS 与降级二进制尚未验收；降级程序若重写归档或服务文件，可能丢弃未知字段，必须保留升级前备份。代码回退不会撤销已保存的新数值／奖励，也不重发历史成绩。这些匿名自报计量只是数学一致性证据，不是不可伪造反作弊证明。

服务运行时会以 Typebar 自有固定窗口策略限制请求：注册/登录为每来源 10 次/分钟，密码重置与验证邮件请求各为每来源 15 分钟 3 次，成绩提交为每令牌 30 次/分钟，其余写操作为每令牌 60 次/分钟，读取接口为每键 180 次/分钟。拒绝响应为 `429`，含 `Retry-After` 和 `X-RateLimit-Remaining: 0`；计数只在进程内保存，重启后清空。部署者可设置 `TYPEBAR_MAINTENANCE_MODE=true`：健康检查和只读请求仍可访问，所有写请求统一得到 `503`、`Retry-After: 300`、`X-Typebar-Maintenance: true` 与提示本机离线练习可继续的 JSON reason。

| 操作 | 方法与路径 | 核心请求 / 响应 |
| --- | --- | --- |
| 人机验证挑战 | `POST /v1/human-verification/challenges`、`GET /v1/human-verification/challenges/{id}/web`、`POST /v1/human-verification/challenges/{id}/complete` | 仅完整配置 Turnstile 时可用。创建请求为 `purpose`（`registration`、`passwordResetRequest`、`profileReport`、`quoteSubmission` 或 `quoteReport`），返回 UUID 和相对 `verificationPath`；网页端点只提供 Typebar 自写的最小组件容器；完成请求携带第三方 `token`，服务端独立校验 Siteverify 的 `success`、固定 action、challenge cData 和允许 hostname 后，以 `302` 重定向至固定 `typebar://human-verification/callback?id=&proof=`。proof 为 5 分钟、单用途、一次性且不持久化（已实现） |
| 注册 | `POST /v1/auth/register` | 邮箱、密码、显示名、可选 `humanVerification` → 用户与会话。能力 `humanVerification=available` 时证明必填且在注册前消费；旧／未配置服务维持原请求契约（已实现） |
| 登录 | `POST /v1/auth/login` | 邮箱、密码 → 用户与会话（已实现服务端基础） |
| 请求密码重置 | `POST /v1/auth/password-reset/request` | 邮箱、可选 `humanVerification` → `accepted: true`；配置验证时在投递前消费用途匹配的 proof，否则不发送邮件。只有配置 HTTPS 投递 webhook 时可用，已注册、未注册和无效邮箱始终得到相同响应。服务端只保存 20 分钟的一次性令牌 SHA-256 哈希；投递失败会撤销令牌（已实现） |
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
| 重置公开个人最佳 | `DELETE /v1/personal-bests` | 仅接受 Bearer 令牌；密码账户提交当前密码，纯第三方账户使用一次性 `X-Typebar-Reauthentication`。成功后返回新的 `resetAt`，从此时开始计算公开资料的个人最佳；既有服务端成绩、XP、徽章、排行榜、本机历史和本机个人最佳均保留。重新认证证明只能消费一次，旧服务缺少 `personalBestResetAt` 时客户端安全显示为从未重置（已实现；固定来源与本机边界见 [OFFICIAL_PERSONAL_BEST_RESET_AUDIT.md](OFFICIAL_PERSONAL_BEST_RESET_AUDIT.md)） |
| 提交结果 | `POST /v1/results` | 接受 Bearer 令牌或 `X-Typebar-Access-Key`；保存具 UUID 的结果，基本范围/时间校验与重复提交幂等；响应包含服务端重算的本次 XP、总 XP、可选本周 XP 名次，以及当天且未退出榜单时同模式同语言的可选全局 WPM 名次。重复 UUID 的回执始终从首次保存记录生成，不信任重试正文（部分实现） |
| 匿名公开练习统计 | `GET /v1/public/practice-stats`、`GET /v1/public/speed-distribution` | 两者均为无认证只读接口。前者只返回完成成绩数、开始测试数和完成成绩的实际累计秒数；后者固定为 English、60 秒、time 成绩，每个允许公开统计的账户只取一个最高 WPM，并以十 WPM 非空桶返回。隐身、排行榜限制、显示名整改和账户封禁均即时排除贡献。响应绝不包含账户身份、邮箱、提示、输入、回放、令牌、单条时间戳或单条成绩；客户端只在 About 打开或用户主动重读时调用，旧服务不可用时不回退为本机统计（已实现） |
| 排行榜 | `GET /v1/leaderboards`、`GET /v1/leaderboards/friends` | 前者为公开全局结果榜；后者需要 Bearer 令牌且仅包含当前用户和已接受好友。两者都可按模式、语言与 `all`/`day`/`yesterday`/`week` 周期筛选；`yesterday` 是服务端当前日历日前的完整一天。每位用户仅保留该筛选下的最佳一条成绩，按此成绩排名，最多返回 100 位用户（部分实现） |
| 我的 WPM 排名 | `GET /v1/leaderboards/rank`、`GET /v1/leaderboards/friends/rank` | 仅接受 Bearer 令牌，使用与相应全局/好友 WPM 榜完全相同的筛选、隐身和排序规则，返回当前账户的条目或空值；结果不受列表前 100 名限制，开发者密钥无此权限（部分实现） |
| XP 排行榜 | `GET /v1/leaderboards/experience`、`GET /v1/leaderboards/experience/friends` | 前者为公开全局 ISO XP 榜；后者需要 Bearer 令牌且仅包含当前用户和已接受好友。`period` 可为 `week` 或 `lastWeek`，后者只包含前一个完整 ISO 周；响应回显实际范围，避免旧服务静默把上周请求当成本周。两者最多返回 100 位用户，返回展示名、服务端计算 XP 与名次（部分实现） |
| 我的 XP 排名 | `GET /v1/leaderboards/experience/rank`、`GET /v1/leaderboards/experience/friends/rank` | 仅接受 Bearer 令牌，按相应全局/好友 ISO 周 XP 榜的既有规则返回当前账户条目或空值；`period` 可为 `week` 或 `lastWeek`，响应回显实际范围。结果不受前 100 名列表限制，开发者密钥无此权限（部分实现） |
| 资料 | `GET /v1/profiles?query=&limit=`、`GET /v1/profiles/{id}`、`GET/PATCH /v1/profiles/me`、`GET /v1/profiles/display-name-availability?name=` | 公开资料仅返回展示名、加入时间与聚合成绩；可按展示名搜索（2–40 字符，最多 50 项）。显示名预检为公开只读布尔查询，不预留名称或返回资料；带有效 Bearer 令牌时会排除当前账户，供仅大小写/重音调整使用，注册与改名写入仍是最终权威校验。本人可读取/更新显示名及 `leaderboardOptedOut`。已解锁徽章默认只以用户选择的一枚出现在资料和榜单；本人可通过可选 `showAllBadges` 明确开启公开资料的 `earnedBadges` 附加数组，省略 PATCH 字段会保留既有选择，旧账户/旧服务缺字段分别按 `false`/空数组处理，榜单永远不读取该数组。显示名在密码/OAuth 注册及改名时均按大小写与重音无关规则保证跨账户可用；首次改名可立即进行，之后每次实际改名须相隔至少 30 个 24 小时，部署方已设置显示名整改要求时可优先改为不同的可用名称。冷却时间只私有持久化，旧记录缺失时可立即改名；隐身/资料等无关更新、认证变更和账户重置不会绕过或刷新它。设为 `true` 会立即从全局和好友 WPM/XP 榜移除该账户，但不删除其服务端成绩、XP 或同步数据（部分实现） |
| 好友 | `GET/POST /v1/connections`、`POST /v1/connections/{requesterID}/accept`、`DELETE /v1/connections/{userID}` | 受令牌保护的好友请求、接受、列表与解除关系（部分实现） |
| 通知 | `GET /v1/notifications`、`POST /v1/notifications/{id}/read` | Bearer 令牌保护；仅返回当前账户的好友请求、接受与新私信事件及触发者公开资料，不携带私信正文，可单条标记已读（部分实现） |
| 服务公告 | `GET /v1/announcements`、`POST /v1/moderation/announcements`、`DELETE /v1/moderation/announcements/{id}` | 读取公开且不需要账户；每项仅返回 UUID、1–500 字纯文本、等级、置顶标记、可选计划日期和发布时间。发布/删除要求部署者显式配置 `TYPEBAR_MODERATION_TOKEN`，客户端以 `X-Typebar-Moderation-Key` 提交；有计划日期时，正文的 `{date}`、`{dateNoTime}` 和 `{dateDifference}` 分别由原生客户端按当前地区替换为日期时间、日期和相对时间；普通公告可仅在当前 Mac 关闭，置顶项不能由客户端关闭，且不会携带账户、提示、输入、成绩、邮箱或令牌（已实现） |
| 资料举报与审核 | `POST /v1/reports/profiles`、`GET /v1/moderation/profile-reports`、`PATCH /v1/moderation/profile-reports/{id}` | 投稿者提交受 Bearer 令牌保护，并在启用人机验证时附用途为 `profileReport` 的 proof；审核读写要求部署者显式配置的 `TYPEBAR_MODERATION_TOKEN` 与 `X-Typebar-Moderation-Key`。队列可按 `open`、`resolved` 或 `dismissed` 筛选，最多 100 条，只返回目标的公开资料、分类、说明、状态和时间，绝不返回举报者身份或邮箱；审核修改只更新举报状态，不通知或自动改变目标账户（部分实现） |
| 部署账户治理 | `PATCH /v1/moderation/profiles/{id}/leaderboard-restriction`、`PATCH /v1/moderation/profiles/{id}/display-name-requirement`、`PATCH /v1/moderation/profiles/{id}/account-suspension` | 三个路由都要求部署者显式配置的 `TYPEBAR_MODERATION_TOKEN` 与 `X-Typebar-Moderation-Key`，并接受可逆的布尔请求。排行榜限制只影响共享榜资格；显示名整改立即排除 WPM/XP 的公共、好友和个人榜，并在持久化前拒绝新的成绩，直到用户提交不同且有效的显示名；账户封禁同样排除共享榜、把公开资料降级为基础统计和个人最佳，并拒绝资料更新与账户重置。封禁期间登录、同步、本机练习、成绩保存、密码和删号均可用，不删除历史数据；封禁状态回传账户本人、公开资料和私有审核队列，其他两个状态只回传账户本人和私有队列。旧响应或旧持久化状态缺字段时默认未设置（已实现） |
| 引语举报 | `POST /v1/reports/quotes` | Bearer 令牌保护；启用人机验证时附用途为 `quoteReport` 的 proof。仅可举报已批准且非本人投稿的社区引语，原因相同不可重复提交，说明最多 400 字。报告只进入私有待审核队列，不通知作者或自动下架（部分实现） |
| 社区引语评分 | `PUT /v1/quotes/{id}/rating` | Bearer 令牌保护；仅可对已批准且非本人投稿评分。请求明确携带 `scale: "fivePoint"` 时只接受 `1`–`5`，返回 `ratingScale`、总人数、总分和当前用户分数；同一账户重评只替换自己的记录。省略 `scale` 永远保留旧 `-1`／`0`／`1` 协议，`0` 撤销评分；旧客户端仍读取聚合“支持/不适合”和本人二元投票。旧持久化评分缺 `scale` 时仍按旧值解释，并为五级聚合投影为 `-1`→1 星、`1`→5 星。评分者身份不公开（部分实现） |
| 私信 | `GET /v1/messages/{friendID}`、`POST /v1/messages`、`POST /v1/messages/{friendID}/read` | Bearer 令牌保护；仅双方已接受好友且未屏蔽时可读取、发送（1–1,000 字）和标记已读。屏蔽或账户删除会清除相关会话（部分实现） |
| 引语投稿与审核 | `POST /v1/quotes`、`GET /v1/quotes/mine`、`GET /v1/quotes`、`GET /v1/moderation/quotes`、`PATCH /v1/moderation/quotes/{id}` | 投稿读取受 Bearer 令牌保护，并在启用人机验证时附用途为 `quoteSubmission` 的 proof，以 `pending` 保存；公共查询可按语言、最多 100 条且只返回 `approved` 内容及聚合社区评分。两个审核端点都要求部署者显式配置的 `TYPEBAR_MODERATION_TOKEN` 与 `X-Typebar-Moderation-Key`；队列可按 `pending`、`approved` 或 `rejected` 筛选，最多 100 条，并返回引语及举报原因/说明但不返回举报者身份；审核修改可设为 `approved` 或 `rejected`（部分实现） |

冲突规则：同一 UUID 使用单调版本和服务器时间；服务端会拒绝未前进版本。原生客户端遇到整包归档版本冲突时，会重新拉取服务器权威归档，以本机标量设置为准合并成绩、预设、成绩筛选预设和文本；同名但内容不同的远端预设、成绩筛选预设或文本，以及同 UUID 但内容不同的远端主题/自定义键盘布局，会另存并标记“同步冲突”，随后按服务器最新版本重试上传。成绩筛选预设使用 v4 活跃字段，并从 v5 加入持久删除 ID；v1–v3 缺筛选字段安全为空，v4 缺删除 ID 安全为空。成绩从 v6 加入持久删除 ID；v1–v5 缺该字段安全为空。本机测试预设从 v7 加入稳定 ID 与持久删除 ID；v1–v6 缺这两个字段时继续按名称和内容去重。云端删除优先，因而旧快照不能复活已删除预设或本机成绩；用户从本机文件明确导入同 UUID 项时可恢复它。服务端内容级三方合并和冲突审计尚未实现。成绩接口会校验枚举、数值范围、完成时间窗口、输入量与错误数、准确率、raw/WPM 和起止耗时的相互一致性，并限制提交速率；尚未实现不可伪造的签名或完整事件回放，因此排行榜仍不应被视作可信竞赛成绩。

归档兼容补充：保存文本从 v8 起保留本机 UUID 并携带持久删除 ID；v1–v7 缺这两个字段时继续按标题、文本和长文本进度去重。云端删除优先于旧快照，用户明确导入本机文件的同 UUID 文本可恢复该项。

归档兼容补充：自定义主题与 Typebar 自定义键盘布局从 v9 起保留本机 UUID 并分别携带持久删除 ID；v1–v8 缺这些字段时安全视为空。云端删除优先于旧快照；删除主题会移除失效的活动主题和收藏，删除当前自定义布局会将输入与键盘提示来源回退为可用默认值。用户明确导入本机文件的同 UUID 项可恢复该项并清除对应删除标记。

当前认证限制：资料、同步、好友 WPM/XP 榜、通知、资料举报、引语投稿、开发者密钥管理与账户删除均由各自路由校验 Bearer 令牌。原生客户端以规范化服务地址分隔钥匙串令牌，切换 endpoint 会清除内存中的当前身份，活动请求期间拒绝切换，因而不会把一个自建服务的 Bearer 令牌发送到另一个服务。旧版全局钥匙串令牌只允许在启动时记录的同一 endpoint 迁移，成功写入 v2 槽后即删除；回退旧客户端可能需要重新登录。`X-Typebar-Access-Key` 只能读取或提交其所有者的成绩元数据，不能调用其他路由；原始密钥只在创建响应中出现，服务端以哈希保存，禁用或删除后立即失效。密码或邮箱更新均要求当前密码并轮换会话令牌、撤销其他既有会话，邮箱更新还校验格式与唯一性且会清除未消费的旧验证码；账户删除会永久删除服务端所有用户作用域数据。密码重置与邮箱验证在配置 HTTPS webhook 后可用：两种令牌绝不写入持久化状态或日志，只以哈希短时保存；重置码 20 分钟过期且成功后不自动登录，验证码 24 小时过期、重发或改邮箱会撤销旧码且成功后不轮换会话。未配置投递时接口明确拒绝。资料与引语审核队列仅供持有部署密钥的运维者读取，且不包含举报者身份；资料举报的审核只改变其私有处理状态，不会自动处置账户。原生客户端提供两类队列工作台，并且审核密钥只留在当前内存会话。通用认证中间件与细粒度审核员权限模型尚未实现。原生客户端仅在用户明确启用后提交完成成绩，并可浏览自己的服务端成绩及全局或好友 WPM/XP 榜。

好友关系当前限制：只实现单向请求与双向接受后的好友关系；公开搜索仅按展示名匹配且不返回邮箱。已提供屏蔽与解除屏蔽（会移除双方关系、相关站内信并拒绝双方后续请求），以及仅展示本人和已接受好友成绩的好友榜。好友请求与接受会生成仅接收者可读取、可标记已读的站内通知；已接受好友可交换并标记已读私有站内信，但没有隐私设置或推送。原生客户端已提供搜索、请求/接受/取消/解除、屏蔽/解除屏蔽、好友榜、通知中心、好友会话、资料举报表单、社区引语举报表单及不落盘密钥的引语审核工作台。

周期语义：`day` 按服务端当前日历日计算；`week` 与 XP 榜均按 ISO 周（周一开始）计算。Typebar XP 是独立设计：服务端根据验证后的成绩时长、准确率与模式计算，禅模式不产生 XP；它不是用户本地时区、每日重置时间或赛季系统的替代品。
