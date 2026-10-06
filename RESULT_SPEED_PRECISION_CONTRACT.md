# 远程小数速度保存与计分合同

后续 [账户 PB 账本](PERSONAL_BEST_LEDGER_CONTRACT.md) 和 [本机／标签账本](LOCAL_PERSONAL_BEST_LEDGER_CONTRACT.md) 已独立保存并接入消费者，服务清空范围已修正，原生归档 28 接通本机账本导出、云合并与导入。下述速度投稿阶段的数字与范围保留；原版标签 ID、官方协议、真实双机及整体等价仍开放。

2026-10-06，原生完成快照的两位小数 WPM 与 Raw 已接通自建服务投稿、私有历史和 CSV、公开资料、速度榜、日榜缓存及奖励文本。旧整数字段保留为兼容视图，旧记录缺失小数仍表示未知，不回算或补造。独立 PB 账本、原版清空行为和完整功能等价尚未实现。

## 固定源码与独立实现

参考固定于 `91bd24bb8513785c7364cbea29296ff7adafac41`。[完成结果](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/test-logic.ts) 对计分字符和 Raw 字符分别计算速度，并调用 roundTo2；[速度计算](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/utils/numbers.ts) 使用字符数除以五和分钟数。[数值工具](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/packages/util/src/numbers.ts) 定义含 EPSILON 的两位舍入，[schema](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/packages/schemas/src/util.ts) 限制 WPM 为 0–420。

生产是独立 Swift 实现和自有 JSON 协议，不复制源码、词库、主题或其他资产。QA 脚本 check-source-speed-precision.mjs 动态执行两个完整固定数值模块，对照八组舍入和六组速度；夹具均为自造数字。这不是原版浏览器完成控制器、原 HTTP 或生产部署验收。既有完整日榜模块及真实 Redis 6.2.6 Lua 对照继续验证打包分数，原生和服务测试验证新字段确实进入生产消费者。

## 能力与发布边界

仅 apiVersion=v1、service=typebar 且 resultSpeedPrecision=available 支持新报告。speedPrecision 的 v1 必须同时提供 version、wpm 和 rawWpm。两项速度为有限的 0–420 两位小数，Raw 不低于 WPM；请求的旧整数必须等于报告各值四舍五入后的整数。

发布读取已保存 preciseWpm／preciseRawWpm，只做源码式两位投影，不从回放、当前设置或旧计数重新生成历史成绩。两位投影可能再次跨整数边界，例如 60.495 投影为 60.50，兼容请求整数为 61；本机旧整数和保存快照不改写。

未支持能力时，仅投影结果与旧整数完全相等的成绩可沿用旧协议；任何会损失小数的成绩在昂贵统计和 POST 前明确报错，本机成绩及重试路径保留。存在输入计量时，必须同时满足实际 v1／v2 计量能力，不能丢掉计分单位后提交精确速度。取消及账户范围复核沿用既有发布流程。

## 日期与计数绑定

含报告的请求、保存记录及私有响应必须保留 startedAtReferenceTime 和 finishedAtReferenceTime，即使没有 elapsedTime。ISO 日期可能丢失亚秒；补充值与原日期的差值必须小于 1 秒，才能恢复 Date 精度。缺失、null、非有限或不一致的日期拒绝，不能用推算日期替代。

服务按已有 measured duration 校验速率：输入计量明确时使用 creditedUnits 和 retainedUnits，缺失计量则使用旧事件与错误计数规则。两位结果须一致，不允许旧整数相同但小数不同绕过绑定。韩文按明确的 koreanJamo 单位，不把输入尝试数冒充计分单位。已有 elapsedTime 和 terminalTiming 的分母选择、AFK 与计量规则不放宽。旧无报告成绩沿用原整数校验；新报告两项上限均为 420，旧协议的 400／500 上限不静默扩展。

## 持久化与消费

同次原子提交将报告保存在 StoredResult 与不可变 ExperienceAwardRecord。历史存在时两份报告必须一致；历史删除后，已知 XP 原始输入继续绑定 WPM 与计分分母，日榜回执继续绑定冻结 WPM。重复 UUID 不换报告、不复活已删除历史、不再次入账。保存失败回滚历史、奖励和缓存，再次提交仅接受一次。显式坏字段、报告冲突或计数绑定损坏在加载时报错且不改文件。这些检查不是签名或不可伪造的反作弊证据。

私有列表、详情和 29 列 CSV 的既有速度两列读取报告，无报告仍显示旧整数。公开速度榜和标准 PB 选择使用 effectiveWpm；公开 scalar preciseWpm／preciseBestWPM 只提供相应胜出记录已有的证据，旧整数胜出时保持缺失。公开响应不新增 Raw、计数、文本或回放。日榜分数、最小速度、冻结胜出快照、邮件和公告读取精确 WPM。自有徽章门槛与公开英语一分钟分布也使用精确值，79.99 不因兼容整数 80 而越过门槛或进入 80 桶。

原生远程历史、资料、搜索／联系与管理资料、排行榜文本使用两位小数；旧结果仍使用原整数字符串。此轮仅改文字绑定，不启动图形程序，窗口布局和辅助功能仍待单实例验收。

## 自动化验证

最初三项原生反例复现八个失败断言，两项服务反例复现六个失败断言；日志分别为 `/tmp/typebar-speed-precision-native-red.log` 和 `/tmp/typebar-speed-precision-server-red.log`。扩展后新增十项原生与十四项服务回归。实际 HTTP 验证能力、投稿、私有列表／详情、日期精度、缺字段拒绝及账户隔离；actor 和隔离文件验证小数胜出、日榜分数／榜尾、已知与未知、历史删除重试、真实保存失败回滚、损坏加载、计分单位、独立分母、Raw 计数绑定、徽章／分布及奖励文本。

第一轮完整原生 3014 项有两处旧能力夹具失败（698.355 秒），模拟升级服务却未声明小数与配套计量能力。只修正这两处支持路径，并增加速度和计量保留断言；旧服务负例及产品拒绝规则不改，相关 48 项通过。该失败轮的十三份日志已单独保存于 `/tmp/typebar-speed-precision-readiness-logs.6CfJPX`；后续 Raw 反例明确断言错误报告仍与同一兼容整数匹配。

最终完整串行门禁原生 3014 项／服务 405 项均零失败、零跳过，分别 697.633／9.257 秒；实际十万词耐久 150.007 秒，九项隔离磁盘迁移 3.690 秒。908 条人工场景仅结构检查通过，固定源码审计、原创性、未打开应用包与签名验证通过。主记录 `/tmp/typebar-speed-precision-readiness-final.log`，十五份详细日志位于 `/tmp/typebar-speed-precision-readiness-final-logs.Zn2cDt`。门禁结束后只补文档，不改生产或测试文件。

## 升级与剩余工作

本机实体、归档 27 和设置文档 4 不变。服务文件为可选扩展，旧记录不回填，加载和只读查询不写文件。升级前备份服务文件、停止旧 writer，先升级服务再升级客户端；不允许新旧 writer 混写。旧服务对有小数的新客户端投稿明确拒绝。需要回退时恢复升级前备份或向前修复，备份后的新增数据不能保证无损降级。本轮未部署服务或接触真实用户库。

服务公开 PB 与全部榜现已读取独立账户账本，完整选项和删历史保留见其合同；本机与标签账本仍开放。premium、Discord 原渠道、内容身份、原协议、旧发行／最低系统／Intel、真实网络、多 writer 和崩溃瞬间仍须单独验证。人工场景保持待验收，整个重写 goal active。
