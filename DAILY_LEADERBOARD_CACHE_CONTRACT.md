# 日榜接受日缓存与成绩快照

Typebar 的正式自建服务已独立接入 time／words 日榜缓存，冻结服务接受日、权威整秒时间、当时名称及资料，不依赖可删除历史。实际提交、今天／昨天、好友和个人名次读取同一状态；现已接入 [日榜任务与交付](DAILY_LEADERBOARD_SETTLEMENT_CONTRACT.md)，本合同下方汇总保留缓存阶段验证，不冒充最新交付全量结果。完整重写 goal 仍 active，生产不包含原版代码或资产，也不连接原版线上服务。

## 固定源码所建立的合同

参考固定在 91bd24bb8513785c7364cbea29296ff7adafac41。[日榜服务](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/utils/daily-leaderboards.ts)、[写入 Lua](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/redis-scripts/add-result.lua) 和 [分数函数](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/utils/misc.ts) 说明，桶按接受时钟的 UTC 日、语言、mode 和 mode2 分开。控制器先把 timestamp 改为服务接受整秒；分数依次打包百分位 WPM、准确率和日内时间，较早整秒胜出，同分按 Redis 成员 ID 逆字典序排序。成绩客户端历史日期与日榜权威时间是不同字段含义，不相互改写。

GT 仅严格更高时覆盖名称和资料快照。未改变写入不返回新名次；容量超标每次仅移除一个最低成员，包括未改变尝试，配置缩容可能暂时仍超容量。TTL 只在淘汰前成员数为一时重设，截止接受日加保留天数后向下取整到秒；多成员不刷新，立即过期及被淘汰尝试不返回名次。原版匹配奖励规则的有效尝试即使未变更或过期仍安排日结算，当前持久任务已保留此条件，不以是否获得新名次作为安排依据。

## 生产接入和配置

正式 configure 通过 TYPEBAR_DAILY_LEADERBOARD_CONFIGURATION 配置新的日榜。Typebar 自选默认启用、两天、每桶 1000 人、所有已有语言的 time／words 限制；原版 base 默认 false／零容量／零天／空规则，不能据此推断线上配置。自有配置键名和容量上限不是原 HTTP 配置协议兼容。

```json
{"enabled":true,"expirationTimeInDays":2,"maxResults":1000,"validModeRules":[{"language":"english","mode":"time","mode2":"60"},{"language":".*","mode":"words","mode2":".*"}]}
```

首次准入决定是否尝试入榜，禁用、无匹配规则和不合格提交仍保存托管回执，不会在启用或重试时补榜。更改部署时长门槛不重新判定已缓存成绩；当前 opt-out、封禁、限制与昵称整改仍隐藏公开条目，头像取消公开后立即隐藏旧快照。启用状态下 opt-out 和封禁清理缓存，账户重置与删除无条件清理；删成绩历史保留缓存及首次回执。当前部署禁用时日榜四个列表／名次端点返回明确 404，全部时间／本周历史与账户 XP 不停。

回执保留首次写入名次而非重试时当前名次，未变更／淘汰／过期映射为自有可选 nil。今天／昨天使用 UTC 桶，名单和个人查询使用获准快照；好友条目的 rank 保留全局名次，friendsRank 为独立好友位置。原生列表和个人提示同时显示两者，分页／百分位／排名记忆使用好友位置；旧缺字段保留旧局部 rank，不猜全局名次。无完整筛选的跨桶最佳查询是 Typebar 自有扩展，不是原版单桶 getter 的等价证明。好友同分明确采用全局逆 ID 顺序，原 Lua 好友 comparator 没有指定同分顺序，不能宣称所有同分情况等价。

## 文件迁移和兼容边界

新增 dailyLeaderboardCache、dailyLeaderboardCacheManaged 及可选 dailyCacheReceipt；缓存条目须对应仍保留的首次回执快照。升级前备份完整服务文件、保持唯一 writer。旧缺字段初始化空缓存，不把旧历史或奖励补造成日榜；纯加载和读榜不写字节。托管标记为真却丢失缓存、显式 null、重复桶、坏版本、快照被单独改写均拒绝，原字节不变。保存失败回滚缓存、成绩、累计与回执，恢复后一次重试才提交。

AuthStore 的省略配置构造入口明确保留旧按客户端完成日期查询路径，以支持已有消费者和旧契约测试；正式 configure 始终提供日榜配置。旧路径只读取没有 dailyCacheReceipt 的历史，新托管成绩不能回退成推测日榜；全部时间／本周历史仍可读新旧成绩。新缓存模式下历史日榜会从切换点开始，升级前未知接受日无法无损重建，界面历史完整性说明仍待验收。禁止旧二进制 writer 或两个进程混写；完整备份恢复是回退边界，不承诺降级重写安全。原生 SwiftData、归档 26 和设置 4 不变。

规则目前由 Foundation 正则执行，36 组常见 ASCII 模式对照包括原版未加括号的锚点／alternation 优先级；这不证明所有 JavaScript 正则、Unicode 或新语法等价。仅 time／words 缓存已接线，quote／custom／zen 的 mode2 尚未对应。原生和服务 WPM 仍为已有整数，原版小数 WPM、minWpm、premium、完整 PB 缓存及 HTTP 格式仍开放，不能升级整个榜单覆盖状态。

## 证据和未完成验收

配置入口是新增静态结构，先用解析和运行探针验证；生产行为实施前两条旧链路反例产生五处失败，覆盖接受日、较早快照和删历史。复核昵称整改又产生两处预期失败后修正。编译期错误源于返回 DTO 与存储用户混用；另外两条初次夹具 WPM／时长不一致被已有校验正确拒绝，修正测试数据而未放宽生产校验。

Scripts/check-source-daily-cache.mjs 在只读参考动态执行完整日榜服务、完整 date 模块、所选完整 misc 函数及真实 Redis 6.2.6 Lua。120 组数值、36 组规则、16 步生命周期覆盖 GT 快照、singleton TTL、缩容、禁用 purge、立即过期、零容量及同秒 ID 淘汰。schema 解码和 later 队列为显式 QA 适配，不是真实 Zod／BullMQ／Mongo 或公告部署。探针集成串行门禁，前后核对固定 SHA 和干净检出。

原生双重名次回执反例产生一处预期失败，随后贯通 codec、列表、个人提示、分页、百分位和排名记忆；界面复核沿用已有 XP 榜的好友／全局文案和原生布局，不新增主题或装饰。聚焦及全量最终结果见下方验证记录。会话内有界决策和风险复核促成独立缓存、托管回执、显式历史入口与昵称整改护栏，不是独立评审。源码驱动和行为优先测试纠正了客户端时间假设；迁移安全保留未知来源而不补造历史。文档复核区分生产链路、QA 适配和未完成奖励。

自动结算、日榜奖励及原生榜首公告的当前证据见交付合同；原版 Discord 渠道、全部模式、小数 WPM、真实旧服务迁移、双重名次实机布局、单窗口／VoiceOver／最低系统／Intel、生产部署、多 writer、崩溃瞬间与长期规模均未验。没有启动 GUI、操作真实库或修改系统时钟。完整 goal 保持 active。

## 缓存阶段验证记录

本次串行 readiness 完成源码与清单审计、原生 2965 项及服务 354 项，均零失败、零跳过，分别 689.549 和 8.177 秒。十万词耐久 148.313 秒，九项隔离磁盘迁移 4.691 秒；890 条人工场景仅结构校验通过，不算窗口验收。新增四项原生、十六项服务测试纳入全量。CoreData XPC 环境诊断不是 XCTest 失败，也不替代最终汇总。

会话在包生成后中断，原流水线没有完整通过总标记。续跑先核对旧 handle 已不存在且无构建／测试／Typebar 进程，再只补剩余包校验；未改生产或测试文件、未重复启动全量，签名、包资源与原创边界检查通过。不能把这次分段恢复伪写为单次完整 readiness 终止成功。门禁运行期间冻结全部项目文件，恢复后仅补本文等文档记录。

完整日志保留在 /tmp/typebar-daily-cache-final-readiness.log、/tmp/typebar-daily-cache-final-client-tests.log、/tmp/typebar-daily-cache-final-service-tests.log 及 /tmp/typebar-daily-cache-final-daily-cache-source-check.log，初次临时父目录为 /tmp/typebar-daily-cache-gate.Q9F5jP；包续验为 /tmp/typebar-daily-cache-package-resumed.log。初始反例分别在 /tmp/typebar-daily-cache-red.log、/tmp/typebar-daily-cache-privacy-red.log、/tmp/typebar-daily-rank-red.log，聚焦原生四项在 /tmp/typebar-daily-rank-focused-final.log。服务十六项最终修改前聚焦通过为 /tmp/typebar-daily-cache-focused-final.log，新增 friendsRank 断言与消费者通过上述服务全量补验，不混用早期结果。
