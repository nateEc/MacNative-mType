# 周 XP 公开分数和双重名次

2026-10-05：Typebar 独立实现原版周 XP 的公开分数投影及全局／好友双重名次。内部累计仍保留完整奖励小数，排序发生在公开投影之前；这不是奖励重算或文件迁移。缓存生命周期、周界与整体原生重写仍未完成。

## 固定源码依据

[完整周 XP 服务](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/services/weekly-xp-leaderboard.ts) 的 getResults 与 getRank 都用 parseInt 返回 totalXp。公开整数不是账户 BSON Long 信用，也不是逐笔奖励先取整再求和。实际参考环境由 [compose 文件](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/docker/compose.yml) 固定为 Redis 6.2.6。

原版 [列表 Lua](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/redis-scripts/get-results.lua) 的好友分支先用 tostring 格式化分数；[名次 Lua](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/redis-scripts/get-rank.lua) 则始终读取 ZSCORE。对应 [Redis 6.2.6 RESP2 实现](https://github.com/redis/redis/blob/6.2.6/src/networking.c) 的 C 格式为 17 位有效数字，[Lua 数字格式](https://github.com/redis/redis/blob/6.2.6/deps/lua/src/luaconf.h) 为 14 位，再解析开头十进制整数。因此通常的 52.75 公开为 52，但 0.000001 在全局／名次查询公开为 9，好友列表公开为 1；接近整数、科学计数和安全大数也不能统一用 floor 替代。这些可观察边界保持源码行为，不改用户原始奖励。Redis 8.6.1 的数值序列化不同，不能代替固定版本验证。

全局榜按原始小数降序，相等时按用户身份逆字典序，符合 [Redis 的逆序排序规则](https://redis.io/docs/latest/commands/zrevrange/)。Typebar 使用其自有 UUID 身份，不复制原版 UID。好友榜先确定全局名次，再筛出已接受好友和本人；rank 保留全局名次，新增 friendsRank 是好友内一基名次，分页不重新从一计算。原版 Lua 对好友同分只比较分数，并没有全局身份次序的保证；Typebar 目前使用稳定全局次序处理好友同分，此差异仍开放，不能声称完整好友同分顺序等价。

## 原生显示与兼容

原生保留两种名次，好友榜标签同时显示好友和全局位置。好友百分位、跳转我的页及 Typebar 自有 XP 名次记忆使用 friendsRank；全局榜使用 rank。旧 Typebar 响应缺 friendsRank 时仍按旧本地 rank 显示，不冒造全局身份；显式 null 也视为缺失。非正、非整数或字符串好友名次拒绝解码。旧服务返回的小数仍可解码，客户端不擅自截断旧响应。

新服务保留 totalExperience 的既有 JSON 数字与 Double DTO 以兼容旧数字读者，但值已是公开整数投影。奖励回执、小数分解、累计信用、保存文件、SwiftData 列、归档 26 和设置 4 不变，纯查询／重载不写文件。新增字段不要求数据库回填；已有奖励也只在读取时投影。服务源码与原版的完整缓存查询不是一回事。

升级顺序是先原生客户端、后服务，只有一个服务 writer。旧原生客户端不能识别 friendsRank，新服务的全局 rank 会影响它的好友百分位和跳页；不能声称旧客户端先连新服务完全兼容。回退服务无需修改奖励字节，但 UI 数值／名次语义会恢复旧合同。旧发行二进制和真实升级／降级尚未验证。之前不可变奖励快照的旧 writer 限制继续有效。

## 自动化和人工验收边界

行为反例：服务三项共 11 个真实断言失败，原生好友名次回传失败，分别见 `/tmp/typebar-weekly-read-red-valid.log`、`/tmp/typebar-weekly-native-red.log`。首次 tie 样例碰撞名称已改为两个独立初始名字，未放宽名字唯一性。初次差分显示指定 POSIX locale 的 Foundation formatter 改变 %g 行为，九个断言失败；改用无 locale 的 C 格式路径，保持数值断言不变。服务第一次全量 271 项只余三项 HTTP 名次断言，定位到样例字符数变了、活动时长没变导致 XP 相同；修正实际时长，不改产品奖励或排序断言。

实际源码探针动态读取完整服务及三个完整 Lua 文件，执行隔离 Unix socket Redis 6.2.6（无 TCP、无持久化），验证 19 组数值、全局同分、好友双名次、分页、空筛选、禁用与错误页。队列和 schema 解析是 QA 适配边界，固定周 key 用于隔离；没有验证日期分区、真实 Redis 服务、完整控制器、身份认证或运维配置。独立服务测试另验保存／重载字节、累计小数、删除墓碑、actor 与真实 HTTP。先行服务 272 项零失败／零跳过，4.126 秒；原生定向 9 项零失败／零跳过，0.003 秒，日志 `/tmp/typebar-weekly-native-focused.log`。

最终完整串行门禁通过：原生 2945 项零失败／零跳过，695.259 秒；服务 272 项零失败／零跳过，4.570 秒。十万词耐力实际通过，149.088 秒；九项隔离磁盘迁移通过，4.665 秒。19 组周 XP 完整服务／Lua 数值、12,240 组资格源码与 48 个标志、507 组账户源码、872 条人工清单结构、未开窗应用包及原创性边界均通过。872 条只是清单结构，不是人工验收。日志 `/tmp/typebar-weekly-final-readiness.log`、`/tmp/typebar-weekly-final-client-tests.log`、`/tmp/typebar-weekly-final-service-tests.log` 为本机会话证据，不是运行依赖；零 Typebar 图形实例、真实库操作或部署。

门禁后仅完善 QA 子进程 signalCode 判定，防止把已经信号退出的隔离 Redis 当作仍运行。未修改生产／原生代码；服务全量 272 项再通过，4.326 秒，零失败／零跳过，日志 `/tmp/typebar-weekly-service-cleanup-final.log`。对已核实属于自有探针的 Redis 子进程做一次信号中断，探针拒绝该次结果并正常退出、不挂起，日志 `/tmp/typebar-weekly-signal-cleanup-final.log`；没有针对其他进程发信号。首次中断观察未匹配到 Redis 改写的进程名，不计作通过，改用自有父 PID 加完整命令核实目标后验证。

QA 使用 Node 24.19.0、对应服务器与支持 --json 的独立 redis-cli 传输工具。门禁前设置 TYPEBAR_SOURCE_REDIS_SERVER 指向临时构建的 6.2.6；本次路径 `/tmp/typebar-redis-626.GUUCo3/reference/src/redis-server`。只读 Redis 参考 tag 的提交为 `4930d19e70c391750479951022e207e19111eb55`；现代 Apple SDK 构建显式定义历史可用宏 MAC_OS_X_VERSION_10_6=1060，未改查询、格式化或原版源文件。临时 QA 可执行文件不复制进生产项目或应用包。缺工具／版本不符在启动探针或 Swift 前失败，不默默跳过。

首轮完整门禁在矩阵路径白名单校验处退出，未启动 Swift；nativeEvidenceFiles 改为允许的客户端源码和服务测试路径，原生测试／QA 探针仍由合同及实际调用追踪。不放宽白名单，不将该次门禁记为通过。

额外只读探针证实错误 Redis 版本和旧 CLI 在创建隔离数据库前失败，日志 `/tmp/typebar-weekly-wrong-redis-version.log`、`/tmp/typebar-weekly-old-cli-rejection.log`。另执行原版完整日期工具的 12 组时区取样，以及同形 ISO Calendar 表达式的显式时区取样：2026-10-05T00:00Z 在上海的原版 key 为当天 00:00Z，Calendar 周起点为前一天 16:00Z；洛杉矶同一输入的原版 key 为 2026-09-29T00:00Z，Calendar 为 2026-09-28T07:00Z。这是可复现的剩余差异，不是完成日期对齐的证据。没有改变系统时区／时钟，也没有修改生产周界；Calendar 取样不是实际 AuthStore 调用。日志 `/tmp/typebar-weekly-source-week-boundary-observation.log`、`/tmp/typebar-weekly-native-calendar-observation.log` 用于后续周界与首次接受 key 的设计验证。

新增三个人工场景仍待真实单窗口验收。没有启动 Typebar GUI、操作真实库或部署。完整原版周界／接受时间、Redis 保留／过期／启用配置、好友同分、完整 premium／timeTypedSeconds／lastActivityTimestamp 列、PB 生命周期、公开统计、真实旧客户端、最低系统／Intel 与整体功能等价仍开放。好友全局名次查询目前需要全局累计，尚未完成大规模查询性能／缓存验收；会话内风险与决策复核不是外部独立评审，goal 保持 active。
