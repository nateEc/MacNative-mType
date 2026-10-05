# 原生奖励收件箱与周任务交付

Typebar 已独立接通周任务、持久邮件、一次性领取及 SwiftUI 收件箱。送达不会增加账户 XP；领取才入账，领取 XP 不写回周练习榜。此增量不是完整 Monkeytype 重写完成声明，整个 goal 保持 active。生产代码与文案为自有实现，固定参考只供只读 QA 动态执行，不进入应用包。

[日榜任务与交付](DAILY_LEADERBOARD_SETTLEMENT_CONTRACT.md) 也已沿用此原生收件箱及领取链路；日榜生产与恢复的新增证据见该合同，不将本文件的上一阶段测试汇总当作日榜全量结果。

## 接口与原生入口

| 入口 | 身份要求 | 行为 |
| --- | --- | --- |
| GET v1/inbox | 当前账户会话 | 返回该账户 inbox 与 maxMail |
| PATCH v1/inbox | 当前账户会话 | 领取或删除指定邮件，返回邮箱及刷新后的 user |
| GET v1/moderation/weekly-rewards | 非空部署者审核密钥 | 只读任务状态，不提供外部发奖或触发任务接口 |
| 工具栏收件箱与命令打开奖励收件箱 | 原生登录账户 | 显示邮件、单封或批量领取、无待领取奖励时批量删除 |

PATCH 严格接受可选 mailIdsToMarkRead 和 mailIdsToDelete UUID 数组，允许空对象、重复 ID 和不属于当前账户的未知 ID；显式空数组、null、额外字段及非 UUID 拒绝。认证和配置门禁先于解码，禁用收件箱返回 503。Typebar 使用自有平铺响应及完整账户回执，不是原版返回 null 的 HTTP 协议兼容实现。

原生端要求 v1／typebar 服务明确宣告 rewardInbox available；旧服务、未知能力和禁用配置不会被当作空邮箱。领取没有乐观加分；成功回执才刷新账户。响应写入前同时检查原始地址、会话 token 和账户 scope，错误 user ID 或账户切换后的响应不应用。视图也检查操作身份，切换账户清掉旧列表和删除确认。原生列表按时间降序、当前系统语言区域的标题升序排序，标题相等时自选保持原顺序；零 XP 仍显示待领取。未读奖励行只显示领取，无奖励行显示删除。

原版查询未指定标题 collation，但实际锁定 TanStack DB 0.6.8 继承集合 locale 排序。QA 动态执行该确切 npm 包完整 comparison 模块和集合默认配置函数，原先 UTF-16 实现已被十二组反例推翻。Foundation String.compare 修正后仍复现一处中文重音顺序差异；原生改用公开 CoreFoundation 区域比较，并仅对比较操作数规范到 NFC，保留可见标题与同值原顺序，不引入 JS 运行时。四个显式区域样例对照不等于所有浏览器语言／系统 ICU 版本或完整查询的同值键排序等价。

## 领取与容量规则

[固定用户 DAL](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/dal/user.ts) 的 updateInbox 仅领取未读目标邮件，先取读集合，再取删集合；删除优先，重复 ID 去重。XP 直接相加，不使用成绩奖励的 BSON 低位转换。标记已读同时清空 rewards，删除则移除邮件，重试不再领取。徽章保留原库存先出现的同 ID，再按奖励顺序追加新 ID。

自有 version=1 邮箱状态分离邮件、交付回执、领取账本和徽章库存。同一用户／邮件 UUID 的交付回执在删除或容量淘汰后仍保留，这是明确增加的幂等保证，不冒称原 DAL 也具有此保证。前插并保留 maxMail 封，淘汰未读邮件不领取；启用且容量零不保留邮件。坏状态、重复回执、不安全算术及领取／已读不一致拒绝加载。邮件和领取账本在一次文件提交保存，失败全部回滚。

删除成绩不删除领取信用；账户重置及删除账户清除该账户邮箱、交付、领取和徽章库存，不触及其他账户。全球任务去重记录保留，避免重放已经完成的周交付。邮件 XP 可为负，算术独立限制在 JavaScript 安全整数域；这不等于原 schema 全数值域兼容，后续成绩报告仍受既有上下文校验约束。

自有徽章使用字符串 ID、标题和 SF Symbol，不导入原版数值徽章目录、图片或 selected 资产字段。首次邮箱更新将当前已解锁的自有徽章纳入持久库存，使旧徽章先于新邮件奖励；它不是原版徽章 schema 或账户导入兼容证明。现有好友通知保持原独立机制，不冒充奖励邮箱。

## 实际调度与恢复

新成绩首次获得周缓存名次时，在同一投稿事务保存一个按接受 key 唯一的任务；同 UUID 重试不再安排，旧回执不补造历史任务。due 为 key 加七天加一分钟；首次 worker 扫描到期任务，失败最多尝试 23 次，每次在失败时钟后一小时再试。每次扫描最多处理十个任务，正常服务约每分钟扫描一次，故不承诺恰好到毫秒执行。

结算读取当时配置及尚未过期的原始缓存，而非投稿时冻结配置；原版 worker 不重跑公开查询隐私过滤，Typebar 保留这一私有交付行为，公开榜单仍使用当前隐私护栏。重叠档位取高，单名次取 maxReward，最后舍入，零奖励送未读邮件。启用空档明确失败；收件箱禁用不能掩盖此前的空档错误。空榜、禁用周榜、禁用收件箱或无匹配名次不产生邮件。自有空候选事务成功不证明真实 Mongo 空 bulk 的行为。

每个任务的全部邮件与 complete 状态共享一次原子文件提交。计算失败不留下部分邮件，记录 pending／failed 和不含账户内容的错误码；保存失败不消耗尝试次数，保留原待处理状态，重启后继续。complete 与 failed 记录不删除，这与原版成功／最终失败移除及 LRU 容量 100 的重复安排行为不同。

WeeklyExperienceRewardWorker 是单 writer actor 工作循环，实际 executable 使用 Vapor 4.122.1 的 asyncBoot／asyncShutdown 生命周期启停；重复 start 不生成第二循环，shutdown 取消并等待退出。测试显式注册并通过真实异步 boot／shutdown，不绑定网络端口，不启动 Typebar GUI。同步 boot 的默认协议钩子不运行本 worker，不支持多服务 writer、分布式锁或 BullMQ 兼容部署。

## 部署配置和文件升级

TYPEBAR_INBOX_CONFIGURATION 默认是 Typebar 自选 enabled=true、maxMail=100；原版 base 是 false／0，不宣称线上配置相同。TYPEBAR_WEEKLY_XP_CONFIGURATION 仍默认启用、15 天、空档位，因此实际任务会按规则报空档错误，不会自动猜奖励。部署者应明确配置档位，例如：

```json
{"enabled":true,"expirationTimeInDays":15,"xpRewardBrackets":[{"minRank":1,"maxRank":10,"minReward":50,"maxReward":200}]}
```

升级前备份完整服务 JSON，保持唯一 writer，禁止旧 writer 覆盖新文件。旧缺字段初始化空状态，仅在下一次成功写入时记录托管标记；纯加载不写字节。rewardInboxManaged 或 weeklyRewardJobsManaged 为 true 时对应状态字段缺失拒绝，显式 null／坏版本拒绝；新奖励已标记安排却缺任务也拒绝。标记是误删恢复护栏，不是抵抗任意文件篡改的密码学账本。恢复使用完整备份或向前修复，缺字段读取不证明无损降级。原生 SwiftData 列、归档 26 和设置 4 不变。

## 自动化证据和仍待验收部分

初始两个路由测试产生四处预期失败；禁用门禁和托管邮箱遗漏再产生三处失败。独立周任务标记反例在账户重置后复现一处失败，随后补护栏。初次 mailbox 排序表达式编译失败经具体类型和独立循环修复，不算行为测试红绿证据。

Scripts/check-source-inbox-claims.mjs 在只读固定检出动态执行完整 updateInbox 及其生成的 JavaScript function body，比较 108 组读删选择和 108 次重复操作；Mongo 更新管线为显式观测适配，不是真实 Mongo／BSON 事务。徽章数值 ID 仅在 QA 桥接成自有字符串和元数据，比较库存顺序，不声称原目录兼容。探针已接串行 readiness，前后核对固定 SHA 和干净状态。

聚焦原生九项通过，0.233 秒，含十二组实际依赖区域排序及反向规范等值拼写；服务二十三项通过，0.474 秒，均零失败／零跳过。首批服务十九项曾因缺环境跳过一项源码测试，保留历史但不替代后来补验。排序红阶段十二处差异、初次 Foundation 修正仍有一处差异均保留。HTTP 领取、账户隔离、严格形状、重试、磁盘提交失败、旧形状、任务重启、当时配置、零奖励／容量及异步生命周期均有自有自动化。

最终同一次串行门禁原生 2961 项通过，692.762 秒；服务 338 项通过，7.082 秒，均零失败、零跳过。新增十项原生及二十三项服务测试纳入全量，含领取回执的 XP／徽章联合解码。十万词耐久 148.850 秒，九项隔离磁盘迁移 3.972 秒；887 条人工场景只作结构校验，源码及原创边界审计、未开窗应用包构建和资源边界全部通过。没有削弱旧断言，CoreData XPC 环境诊断不替代最终 XCTest 汇总。构建／测试／打包运行时冻结全部项目文件，门禁后只补记文档。

本轮主日志 /tmp/typebar-inbox-final-readiness.log，完整原生及服务日志 /tmp/typebar-inbox-final-client-tests.log、/tmp/typebar-inbox-final-service-tests.log；唯一临时父目录 /tmp/typebar-inbox-gate.JcwZ5a。归档来自这次运行，不混用旧临时日志。初始红测、迁移反例与排序修正日志保留在 /tmp/typebar-inbox-routes-red.log、/tmp/typebar-inbox-recovery-red.log、/tmp/typebar-inbox-job-recovery-red.log、/tmp/typebar-inbox-order-red.log 及 /tmp/typebar-inbox-native-final-focused.log，后者是仍有一处差异的失败阶段，不作最终通过证据。

源码驱动和行为优先测试使配置、领取与区域排序基于实际源码而非页面猜测；会话内有界决策、风险和迁移复核促成两个独立托管标记及单 writer 边界，不是独立评审。界面设计复核保持原生列表，以等宽奖励条和明确待领取状态区分通知与信用；文档复核保留接口、目录和队列差异，不冒报整体兼容。

没有操作真实账户库、部署或修改系统时钟。单窗口布局、大字体、VoiceOver、原生异步网络实机交互、真实 Mongo／BullMQ、崩溃瞬间 fsync 及多 writer、长期规模、macOS 14／Intel、日榜奖励、premium、完整 PB 缓存和整体功能等价仍未验。不能用候选计算、HTTP 或源码探针通过替代这些验收。
