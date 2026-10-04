# 周 XP 接受时间与固定分区

Typebar 服务独立实现固定 Monkeytype 源码的后端周 key。新奖励按首次服务端接受时间冻结分区，而不是按客户端结束日期筛选；旧奖励缺分区时仍走原 Typebar 的本地 ISO 周结束时间路径，不回填、不重算。前端 UTC 周结束倒计时不改。本合同不表示缓存过期、完整榜单或整体原生重写完成。

## 固定源码规则

[完整日期工具](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/packages/util/src/date-and-time.ts) 先用 UTC 毫秒日界及有符号余数取得 anchor，再按服务器本地星期把日期设到周一，最后再取 UTC 日界。此规则不是纯 UTC 周，也不是服务器本地 ISO 周。2026-10-05T00:00Z 的上海 key 为当天 00:00Z，洛杉矶 key 为 2026-09-29T00:00Z；负 epoch 的有符号余数也必须保留。

[周榜控制器](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/api/controllers/leaderboard.ts) 查询上周时使用当前 key 减精确 604,800,000 毫秒，不调用 getLastWeekTimestamp 重新计算七天前日期。[完整周榜服务](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/services/weekly-xp-leaderboard.ts) 的默认实例按服务端 Date.now 分区；[结果控制器](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/api/controllers/result.ts) 接受正 XP 时向该实例添加奖励，而非使用客户端结束时间作为周 key。

原版前端 NextUpdate 使用 UTCDateMini 加 endOfWeek。其 UTC 倒计时与后端分区有可观察差异，Typebar 的 LeaderboardRefreshSchedule 仍保留已有前端 UTC 行为，不能用后端 key 改写倒计时来掩盖差异。

## 新奖励与旧记录

唯一 AuthStore writer 在接受结果、准入、奖励和累计练习的同一保存中追加可选 weeklyPartition。完整 XP 报告和旧形状的新投稿都冻结接受分区；拒绝保存不新增分区，重复 UUID 和历史删除后的重试沿用首次奖励，不把旧奖励搬入新周。删除历史保留墓碑，显式重置或删除账户仍按既有规则清理。XP 小数、累计信用、公开投影、准入和隐私规则不改变。

version=1 记录包含 clipped 接受毫秒、时区标识、原日界与目标时间的 GMT 秒偏移、缺失本地时间的前移秒数，以及最终 key。载入以冻结偏移校验算术，不查询新时区数据库来重新计算历史 key。时区标识是来源标签，不是签名；本地文件并不因此成为防篡改证明。既有 ISO-8601 接受日期只保存整秒，绑定校验因此使用同一秒；分区保留毫秒，不更改全局日期编码或假称旧日期含毫秒。

缺字段保留未知来源，继续使用升级前 Calendar ISO 结束时间路径。显式 null、错误版本、非整数、越界偏移、负 gap、错误 key 或不匹配的接受秒拒绝重载，不覆盖损坏文件；纯载入／查询不写文件。历史来源缺失意味着该部分仍非原版分区等价。当前查询时钟无法计算 key 时明确失败，不返回伪空榜。

## 部署与回退

TYPEBAR_WEEKLY_XP_TIME_ZONE 可指定服务器 IANA 时区；缺失时在 AuthStore 构造时固定 TimeZone.current，非法、空白或未知值拒绝启动。不使用客户端时区，不改宿主机时钟／设置。换配置只改变后续投稿与当前查询的 key，不移动已保存奖励，因此旧分区可能不再出现在新配置的本周／上周列表。

升级前保留完整 JSON 副本，只允许一个新 writer。新增内部可选字段不要求原生协议、SwiftData 列、归档 26 或设置 4 升级。旧 writer 可能忽略并在下一次写入时丢失分区，禁止在新文件上混写或直接回退旧 writer；需恢复升级前副本或向前修复，不能承诺保留新奖励的无损降级。真实旧发行服务／原生二进制与部署切换仍未验证。

## 已执行证据与剩余工作

行为反例先执行一项真实服务测试，出现两条预期失败：接受本周的回填结束时间奖励进入了上周榜。修正后该反例通过。日期探针动态读取完整固定日期工具与实际控制器周选择函数，生成 20,724 组、12 个时区样例，覆盖全年 2026、历史年份、负 epoch、UTC 周界和 Apia 日期跳跃；54 组区分上周减法与重新计算。独立 Swift 实现逐组一致。控制器周选择探针不表示完整 HTTP 控制器执行。

完整周榜服务与真实隔离 Redis 6.2.6／Lua 的探针另执行 19 组数值及 12 组默认时钟写入／读取／分区 key 场景。队列、schema 与连接仍有 QA 适配，不是原版整站、真实运维服务或反作弊验证。只改变该 Node 进程的 TZ 与 VM 时钟，无 TCP、无 Redis 持久化。参考 checkout 保持干净且固定提交，生产代码及应用包不复制原版代码／素材。

首次六项分区测试中仅旧记录样例失败：周一减八天属于前两周，修正为上周二后保留隔离和字节断言。随后服务全量 280 项零失败／零跳过，4.875 秒；日志 `/tmp/typebar-week-partition-service-preflight.log`。风险复核增加非法查询时钟明确失败路径与回归后，全量 281 项再通过，4.939 秒、零失败／零跳过，日志 `/tmp/typebar-week-partition-service-reviewed.log`。

最终完整串行门禁通过：原生 2945 项零失败／零跳过，690.532 秒；服务 281 项零失败／零跳过，5.041 秒。十万词耐力实际通过，148.612 秒；九项隔离磁盘迁移通过，3.978 秒。20,724 组日期／控制器选择、19 组完整周榜数值、12 组默认时钟 Redis 写读、12,240 组准入与 48 个标志、507 组账户源码、875 条人工清单结构、未开窗应用包及原创性边界均通过。日志 `/tmp/typebar-week-partition-final-readiness.log`、`/tmp/typebar-week-partition-final-client-tests.log`、`/tmp/typebar-week-partition-final-service-tests.log` 是本机会话证据，不是运行依赖。原生日志包含 Core Data XPC 诊断，XCTest 及隔离磁盘断言通过不意味着宿主系统服务或真实账户已验收。零 Typebar 图形实例、真实 Typebar 库操作或部署。

人工单窗口场景仍待验收。缓存保留与过期／启用配置、完整 metadata、好友同分、PB 持久生命周期、查询规模与性能、公开统计、真实旧客户端、macOS 14／Intel 及整体功能等价仍开放。新旧奖励混合读取是明确兼容取舍；本会话风险复核不是独立外部评审。goal 保持 active。
