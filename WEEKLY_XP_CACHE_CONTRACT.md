# 周 XP 缓存与启用配置

Typebar 新奖励进入独立可过期周榜缓存，终身 XP 仍在不可变账本中。缓存过期、隐藏或清除不会删除奖励，重新启用不会补入禁用期间的奖励；已获准缓存条目不因后续提高时长门槛而重新失去资格。旧奖励缺缓存来源仍保留明确兼容路径，不冒充有完整 Redis 历史。本阶段不表示完整榜单或整体纯原生重写完成。

## 固定源码与可观察规则

[完整周榜服务](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/services/weekly-xp-leaderboard.ts) 在禁用时不添加奖励，工厂返回 null；[控制器](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/api/controllers/leaderboard.ts) 因此返回 404，而不是成功空榜。服务以已有条目累计 timeTypedSeconds，在每次获准添加时更新名称与最后活动毫秒。查询不重查当前账户时长资格。[用户改名控制器](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/api/controllers/user.ts) 更新账户和好友关系，不直接改周榜缓存。

[增量 Lua](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/redis-scripts/add-result-increment.lua) 先累加分数并保存 metadata，再在 ZCARD 等于一时对分数和结果 key 都设置 EXPIREAT。过期时点是 floor((周 key + 保留天数 × 86,400,000) / 1,000) 秒；保留天数允许零和小数。只有一个用户时每次写入重设 TTL，已有多个用户时新配置不改 TTL；purge 到只剩一个用户后，下次写入又能重设。清掉所有成员后，新条目重新建立 key 与 TTL。

立即过期时 Lua 删除 key，最后 ZREVRANK 返回 null；完整服务将 null + 1 公开为写入名次 1。列表／名次查询仍为空，奖励保留。这不是 Typebar 自行发明的排行榜条目。[purge Lua](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/redis-scripts/purge-results.lua) 删除用户的两类缓存成员，而非奖励；服务在禁用时不执行 purge。

## 独立实现与兼容边界

weeklyExperienceCache version=1 保存按周 key 分区的原始小数分数、名称、累计活动秒、最后活动毫秒与冻结 TTL。新奖励追加可选 weeklyCacheReceipt，保存当次启用／保留配置、活动秒和可选首次写入名次；其存在表示已被新缓存管理，包括禁用、未获准和零 XP 的投稿。失去条目的奖励不会再被账本扫描补回。旧 UUID 重试不再次更新缓存；Typebar 自有幂等回执沿用首次写入名次，并仍受当前启用、隐私和账户资格控制，不宣称原版提供相同 UUID 幂等保证。

奖励、缓存、结果、准入与累计练习作为同一 AuthStore 保存提交；缓存先在局部副本更新，保存失败回滚后安全重试。历史删除保留奖励和缓存；原生已有账户重置／删除会清理缓存和奖励。显式 opt-out 或封禁在启用时清除缓存，禁用时保留底层缓存；Typebar 的当前隐私／审核读取过滤仍生效。重开公开展示不回放已被清除的托管奖励。

缓存会在操作时惰性过期，纯查询只清理 actor 内存，不写文件；正常成功写入将清理后的状态持久化。已清理缓存不会因同一 actor 内的后退测试时钟或失败保存恢复；重载仍按保存的 TTL，而非新配置，判断有效性。没有证明进程重启结合系统时钟回拨与 Redis 的主动过期完全等价，也未实现真实 Redis／分布式 writer。此恢复边界仍开放，不承诺文件型惰性缓存具备 Redis 的全部运维语义。

载入拒绝显式 null、未知版本、重复周 key／用户、错误 TTL、无对应奖励的用户或超过已获准奖励上界的分数／秒数。该校验不是签名或完整事件重放证明。缺整个缓存且存在托管回执时拒绝重建，避免伪造已经过期／purge 的条目。真正旧文件缺缓存与托管回执时初始化空缓存，不回填旧条目；旧来源奖励仍在旧派生兼容路径上，保留既有周分区／ISO 回退及隐私规则，因此该部分不具备原版 TTL 等价性。

新托管读榜不再逐用户扫描终身奖励；旧兼容奖励在载入／提交后维护单独索引，每次查询只聚合一遍旧来源记录。排名和分页仍按先前公开投影与双名次合同。完整大规模基准、存储容量、metadata 消费与缓存恢复仍待验收，不将代码复杂度改进冒充性能基准通过。

## 配置与升级

TYPEBAR_WEEKLY_XP_CONFIGURATION 是启用与保留天数 JSON，例如 {"enabled":true,"expirationTimeInDays":15}。Typebar 自有默认值为启用、15 天，并非 Monkeytype 的线上配置；固定源码 base configuration 是禁用、零天。缺配置用 Typebar 默认值，错误类型、负数、非有限数或无法安全计算截止时间的值明确失败。有限安全算术范围是 Typebar 的部署限制，不声称与原版对所有不安全数值的运行时错误一致。周时区仍由 TYPEBAR_WEEKLY_XP_TIME_ZONE 控制，不改宿主机时钟或时区。

新旧原生协议、SwiftData 列、归档 26 与设置 4 不变。只允许一个新服务 writer，升级前保留完整 JSON 副本；旧 writer 会忽略并可能丢弃缓存和回执，不能混写或在新文件上直接无损降级。旧备份读取不要求回填；恢复需使用升级前副本或向前修复。真实旧发行程序、最低系统、Intel 和实际部署没有验证。

## 已执行验证与未完成部分

先执行门槛变化的真实反例，三条预期断言失败；首次仅测试可选 eligibility 使用错误，编译失败不计作行为反例，修正类型使用后再执行红阶段。缓存接入后反例通过。先行服务全量 292 项通过，5.206 秒，零失败／零跳过；日志 `/tmp/typebar-week-cache-service-preflight.log`。

完整固定周榜服务与四个完整 Lua 文件动态只读执行于隔离 Unix socket Redis 6.2.6；新增 12 步包含 singleton、多用户、改配置、禁用写入／purge、清除／重建、metadata 累积及立即过期。用 Redis TIME 与 PTTL 观测绝对截止时间，并按 EXPIREAT 的整秒粒度读取，与独立 Swift 缓存逐步比较。即时过期样例使用稳定 UTC 日内时钟，避免测试自身跨周。原有 19 数值、12 默认时钟、20,724 日期／控制器样例不删除。队列、schema 和连接仍有 QA 适配，不是原版整站或真实运维服务。无 TCP、无 Redis 持久化、无系统时钟变更。

源码差分接入后服务全量 293 项通过，7.426 秒，零失败／零跳过，日志 `/tmp/typebar-week-cache-service-oracle.log`；其后风险复核增加禁用旧回执及禁用 purge 的配置切换回归，后续结果另记录。两个旧形状测试移除新缓存字段／回执，以真实升级前形状验证；没有把仅删除账本而保留新缓存的损坏混合文件当作旧版本。

配置切换复核后服务全量 295 项通过，7.317 秒，零失败／零跳过，日志 `/tmp/typebar-week-cache-service-reviewed.log`。禁用隐藏旧投稿名次但不清掉已有分数；禁用期间 opt-out 不执行底层 purge，但当前隐私读取过滤仍生效。完整串行门禁结果另记录。

最终完整串行门禁通过：原生 2945 项，691.108 秒；服务 295 项，6.874 秒，均零失败／零跳过。十万词逐词耐久 149.522 秒，九项隔离磁盘迁移 3.883 秒；原有源码差分、12 步缓存差分、878 条人工清单结构与未开窗应用包／原创边界检查全部通过。原生 CoreData XPC 警告未被当作测试结论，以上以最终 XCTest 断言汇总为准。主日志 `/tmp/typebar-week-cache-final-readiness.log`；本次独立保存的完整测试日志为 `/tmp/typebar-week-cache-verified-client-tests.log` 与 `/tmp/typebar-week-cache-verified-service-tests.log`，不是旧临时目录日志。门禁冻结代码，结束后仅补记文档。无 Typebar GUI、真实用户库、系统时钟修改或部署。

完整 premium、badge／avatar 快照、timeTypedSeconds／lastActivityTimestamp 的公开协议与原生表格、好友同分、每周奖励队列／brackets、PB 缓存、公开统计、真实迁移、旧客户端和整体功能等价仍开放。Typebar 当前审核／隐私过滤和账户数据清理比原版禁用期间的陈旧缓存读取更严格，此差异保留并明确未对齐；不能据此宣称整个周榜等价。人工单窗口场景仍待验收，goal 保持 active。
