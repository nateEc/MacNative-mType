# XP 生产奖励与不可变账户账本

2026-10-05：带完整终止计量的新投稿已在 AuthStore 生产入口使用独立 Swift XP 计算，首次奖励、配置和账户上下文保存在不可变账本。回执和周榜保留小数，账户使用单独的整数入账；历史成绩不按新公式回算。完整重写 goal 仍 active，不能把本阶段视为全服务、窗口或功能等价验收。

## 源码依据与部署配置

固定参考为 `91bd24bb8513785c7364cbea29296ff7adafac41`。[结果控制器](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/api/controllers/result.ts) 使用服务日期、上一条成绩时间、账户 XP、连续练习天数及服务配置计算奖励，将数值奖励交给回执和周榜；[用户持久化](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/dal/user.ts) 则用 `new Long(xp)` 入账。锁文件解析到 BSON 6.8.0，其 [数值构造器和 toNumber](https://github.com/mongodb/js-bson/blob/v6.8.0/src/long.ts) 只写低 32 位、高位为零，因此普通正小数截断，超过 2³² 的奖励还会回绕。这不是 `Long.fromNumber`。Typebar 独立实现这一数值边界，不引入 BSON 或参考代码。

原版 [基础配置](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/constants/base-configuration.ts) 默认关闭 XP、倍率与奖励均为零，不能据此推断官网当前配置。Typebar 的明确自建默认为 enabled=true、gainMultiplier=1，Funbox、每日和连续练习额外倍率均为零。服务启动可用 `TYPEBAR_XP_CONFIGURATION` 提供完整 JSON 配置，键为 enabled、gainMultiplier、funboxBonus、minimumDailyBonus、maximumDailyBonus、streakEnabled、maximumStreakDays、maximumStreakMultiplier。缺键、非法类型、负值、非有限值和倒置日奖励区间拒绝启动；没有新增包依赖或生产部署。

测试可显式注入 nil 配置保留切换前的传输合同；默认生产调用不是 nil。缺完整报告的旧客户端继续使用既有 Typebar 旧公式，不能从文本、可见错误、当前设置或回放补造计量。该兼容回退不是完整原版准入或反作弊，整体 experience 能力仍 partial。

## 首次奖励与三个消费路径

新完整报告须先通过现有认证、准入、计量绑定与匿名目录解析，才调用独立计算器。服务器以接收日期向下取整到秒生成 XP 时间；每日判断读取仍存在的上一条成绩接收时间，连续天数从已接受的账本活动及账户固定偏移计算。删除历史会使上一条成绩缺失，但不会删除账户 XP 或连续活动证据。这一删除边界对应原版结果删除与用户累计状态分离；没有改动本机系统时间或历史成绩日期。

账本每条保存 version=1、账户和成绩 UUID、周榜日期、接收日期、数值奖励及明细、整数入账值，以及独立计量输入、配置、账户上下文。计量仍不含提示、输入、回放或键身份。回执 experienceGained 与周榜 totalExperience 使用 Double，dailyXpBonus／xpBreakdown 对新奖励显式返回；Zen 或关闭奖励返回 0、false、空明细。账户／资料的 totalExperience 保持整数，读取不可变入账值，不从剩余成绩重算。

同一账户同一 UUID 重试只读取首次奖励，即使报告或服务配置变化也不重复发奖；回执的账户总额仍反映当前账户，不冻结首次总额。历史删除保留奖励墓碑，重试不能复活已删成绩；不同账户的同 UUID 相互独立。明确账户重置／删除才清除该账户账本，标签、资料、认证等操作不重算奖励。历史删除后周榜的资格仍受既有保留成绩练习门槛影响；原版完整 lifetime typing、榜单资格及外部周榜存储尚未迁移。

原生消费者可解码整数旧回执和小数新回执／周榜。小于 1000 的非整数按实际数值显示，不吞掉小日奖励；既有大值紧凑显示保留。新数值拒绝非有限、负或超出安全包络的响应。完整 XP 级别、明细交互、实际窗口和真实队列尚待验收；本轮没有启动 GUI。

## 持久化与旧数据保护

账本与成绩、练习计数和通知使用同一既有 actor／原子提交，写入失败恢复全部提交前状态。计算或安全累计失败发生在状态变动前。服务重载校验账本版本、唯一身份、账户归属、数值边界、配置／上下文完整性、冻结公式及仍保留成绩的计量绑定；坏显式账本或旧大整数拒绝重载，保留原文件，不把 null／空账本当旧格式。

旧服务文件仅在账本字段缺失时迁移：从仍保留成绩冻结当时旧公式，读取过程不写文件；下一次成功修改才原子保存新账本。此前已删除且没有账本的 XP 无法恢复，不能补造。旧 nil 计量保持 nil，新配置不改旧奖励。

升级前应停下唯一服务 writer，保留完整原始 JSON 副本，再升级服务和客户端。新文件不支持旧服务二进制回写或两代 writer 混写；旧 writer 可能丢账本并导致奖励损失。回退须停服务并恢复升级前完整副本，不能用旧程序覆盖唯一新数据。本阶段未验证真实旧发行二进制、混写、降级或生产库恢复。本机 SwiftData 列、归档 26／设置 4 均未改变；已有本机坏行 compactMap 导出缺口也未被本奖励账本修复。

## 验证与剩余范围

行为优先证据：新增服务测试先得到 18 而非 52 XP，删除后重试复活历史；客户端先因 52.5 的整数解码失败。测试夹具参数顺序、actor 初始化和并发测试捕获问题分别修正，编译失败没有算作行为通过。完整串行门禁原生 2930 项／服务 241 项零失败／零跳过（689.444／2.601 秒），十万词通过 147.757 秒，863 场景仅结构核对及未开窗应用包通过。门禁后迁移复核发现新增限制会拒绝合法无限 time 中止；新增反例实际失败，修正为独立校验安全配置限制与测量时长后，服务全量 242 项再通过（2.584 秒，零失败／零跳过），原生代码未变。源码差分与全部 48 个 Funbox 仍实际执行。日志为 `/tmp/typebar-xp-awards-server-red.log`、`/tmp/typebar-xp-awards-client-red.log`、`/tmp/typebar-xp-awards-readiness.log`、`/tmp/typebar-xp-awards-gate-client-tests.log`、`/tmp/typebar-xp-awards-gate-service-tests.log`、`/tmp/typebar-xp-awards-infinite-red.log` 和 `/tmp/typebar-xp-awards-postgate-server.log`；隔离门禁目录自动清理前已捕获完整客户端／服务日志及磁盘投影清单。

新增服务 19 项覆盖实际生产入口、Funbox／逐次未完成计量、日奖励小数、Long 低位回绕、权威时间／连续天数、配置变更、旧文件只读加载、墓碑重载、损坏字节、实际保存失败、跨账户／并发、账户重置／删除、真实 HTTP，以及新旧报告的无限／安全大限制中止重载；原生五项覆盖响应精度、旧形状、显示及非法数值。技能引导的行为、根因、迁移、决策和风险复核为本会话有界检查，不是独立外部评审。

尚未执行完整原版控制器／反作弊／提交间隔链，也未统一所有账户活动和榜单资格。固定函数探针不是全后端执行。主题精确身份、内容、挑战、macOS 14／Intel、真实 IME／设备、单窗口验收、旧 SDK／发行程序、实际队列和全应用恢复仍开放；不得提升这些覆盖或结束整体 goal。
