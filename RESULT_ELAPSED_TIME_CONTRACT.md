# 独立测量时长的本机保存合同

本阶段扩展本机成绩和归档，使真实日历日期与测量时长能够独立保存。这是主计时迁移的数据准备阶段，不是运行时切换：TypingSession、主测试倒计时、WPM、活动、按键和回放的生产计时仍依赖 Date，新会话尚不产生 elapsedTime。完整原生重写目标继续 active，不能据此关闭主计时缺口。

## 源码依据与保存语义

只读官方检出固定为 `91bd24bb8513785c7364cbea29296ff7adafac41`。[test-timer](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/test-timer.ts) 从 performance.now 测量并在起止事件保存真实日期；[live-cache](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/events/live-cache.ts) 用事件时间差算实时秒数。[stats](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/events/stats.ts) 分开 testMs 时长和日历日期差，Zen／BailOut 还按不足七秒的物理末键尾部剪裁。

不能把日期独立等同于成绩无条件有效：[finish](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/test-logic.ts) 会拒绝非 BailOut、时长不超过 120 秒、测量时长与日期差偏离超过 0.1 秒的 time 成绩。后续运行时及服务迁移必须单独实现和验收这个资格规则，不能删除它来获得绿灯。当前新增本机字段本身不重新判定保存分数。

原生可选 `elapsedTime` 只包含 version 1 与 seconds，代表完成时捕获的原始经过秒数，早于尾部剪裁。它不保存时钟起点、Instant、系统启动时间或持久化 uptime。真实 startedAt／finishedAt 不改，即使结束日期比开始日期早，也不伪造为开始日期加经过秒数。原有 wallClockDuration 仍将负日期差夹到零；实际日期保留在单独字段，不声称这个旧 getter 与源码的负日期差完全相同。

| 数据 | 有独立时长 | 无独立时长的旧记录 |
| --- | --- | --- |
| capturedDuration | elapsedTime.seconds | 原 wallClockDuration |
| elapsedDuration | terminalTiming 的模式分母，否则 capturedDuration | 原尾部剪裁或日期差 |
| chartDuration | terminalTiming 的精确边界，否则 capturedDuration | 原图表边界或日期差 |
| 复制已键入文字 | 使用原始 capturedDuration，尾部剪裁不截输入 tape | 原日期差 |
| 日期、回放、WPM、Raw、准确率 | 原样保存，不重算 | 原样保存，不回填 |

TerminalTiming v1 的结束毫秒必须匹配原始 capturedDuration；只有明确存在新字段时才改变校验基准。旧记录仍严格绑定日期差，不能全局解除校验。版本不符、负数、NaN、Infinity、缺少必填项或不可表示时长拒绝解码与编码。v1 本机上界为 `Int.max / 1000 - 1` 秒，给整型毫秒表示及浮点舍入留余量；这是原生格式的机器边界，不是 Monkeytype 模式上限。普通 3601 秒、十天及无限练习不受服务 3600 秒上限限制。源码 util 的 isSafeNumber 实际只检查有限，不宣称它有 MAX_SAFE_INTEGER 限制。

## 数据迁移与消费者

采用先扩展再切换，不做回填、双写或旧值重算。SwiftData 新增可选 elapsedTimeData，当前只用内存容器验证；没有打开真实库，也没有证明真实旧库的 schema 升级。字段缺失保持缺失。畸形显式 bytes 原样保留，不导出成没有字段的旧成绩；派生时间抑制为零，不从真实日期差猜测修复。这是失败保护，不是有效的零时长记录；损坏数据的 UI 提示和实机恢复仍待验收。

结果历史、有效时间、ResultMetric、图表分母及复制文本读取捕获时长；历史 WPM consistency 的任务身份包含新 blob，避免元数据改变后复用旧计算。CSV 保留原列和隐私边界，elapsed_seconds 读取测量分母，wall_clock_seconds 仍是原日期差，日期列仍是真实日期。CSV 不携带完整新字段，不能作为可恢复备份。

归档默认 25，明确含新时长的结果最低 25。即使请求格式 1，自动提升也先确定 payloadVersion，保留预设／保存文本 ID、墓碑及主题／键盘删除标记。解码在墓碑过滤前检查原始结果，不能在格式 24 中用删除标记藏住新字段；1 至 24 没有新字段的真实旧档仍沿用原行为。设置文档仍 4，依赖和最低 macOS 14 不变。

匿名成绩服务尚未迁移，新格式记录在 ResultConsistencyPublication.prepare 的计算／POST 前明确拒绝；即使未知服务声称 resultElapsedTime available，也不会提前启用未实现协议。实际上传路径已核对，旧成绩发布不变。当前 server、RemoteAccountResult、HTTP DTO 和物理 timingEvidence 的日期基准不改；生产也不写新字段，所以不发生部分切换。新归档可导入本机并保留，但不能发布其中的新时长成绩。以后必须先补服务持久化、校验、历史和明确能力协商，再启用生产写入。

回退应保留升级前真实库／归档副本；旧二进制可能忽略新字段、错误派生时长或覆盖新数据，不能把加可选列说成可安全降级。没有删除旧字段、清理库、真实同步、部署或账号操作。真实旧库、混合 writer、旧二进制回退和恢复均未验；不得在这些前置条件未知时自动切换生产计时。

## 自动化证据与剩余工作

先行八项测试编译执行：首轮 37 个失败含两处归档日期编码设置错误；修正时误访问文件私有编码器的一次编译失败不算 RED。测试内明确 ISO 日期后，八项实际执行 39 个失败，只有一项终止于预期的 terminal clock 拒绝异常，暴露独立字段被忽略、0／3600 秒分母、复制截断、格式与墓碑和发布丢字段。实现后八项通过（0.055 秒）；扩大十四项及相关回归共 93 项通过（2.281 秒）。风险复核的极大有限值另有单项一处真实失败，再补本机可表示边界。最终验证结果另记，不用先行绿灯冒充全量完成。

已有探针在内存执行十个完整实际源码模块，本轮增加八组日期差正／负一小时而事件时间不变的夹具，共 72 组通过。实际 live-cache、事件存储、stats、finish 显示测量时长独立和普通短 time 的无效资格；timer-end 的日期由明确自有绑定提供，不是完整 test-timer／animejs 的执行证明。浏览器、DOM、RAF、真实账号、HTTP、IME、音频和设备未运行，参考实现或资产不进入原生代码。

日志为 `/tmp/typebar-elapsed-time-red.log`、`/tmp/typebar-elapsed-time-red-valid.log`（编译失败）、`/tmp/typebar-elapsed-time-red-corrected.log`、`/tmp/typebar-elapsed-time-green.log`、`/tmp/typebar-elapsed-time-expanded.log`、`/tmp/typebar-elapsed-time-bounds-red.log` 和 `/tmp/typebar-elapsed-time-source.log`。新增人工场景保持待验收。

加入表示边界后，新增 ResultElapsedTimeTests 共十五项，最终定向 94 项零失败（2.239 秒）；日志 `/tmp/typebar-elapsed-time-final-focused.log`。837 条人工场景结构通过，不等于设备验收。

完整串行门禁成功结束：客户端 2829 项零失败（525.178 秒，可选耐久默认跳过一项），服务端 164 项零失败（1.756 秒），固定参考、原创性、元数据和未开窗应用包检查通过。随后只显式启用 TYPEBAR_ENDURANCE_TESTS=1 单独补跑该十万词用例，零失败、零跳过，实际 145.402 秒；不把独立补测改写为原全量零跳过。旧 12000 次组合书写簇退格双投影 0.025094 秒，不证明新时间域的实机性能。

完整门禁日志 `/tmp/typebar-elapsed-time-readiness.log`，客户端完整捕获 `/tmp/typebar-elapsed-time-gate-client.log`，耐久补测 `/tmp/typebar-elapsed-time-endurance.log`。服务／package 临时日志在门禁成功结束后已清理，复制尝试未成功；服务总数与 package passed 以完整门禁日志为证，不宣称保存了不存在的完整分项文件。AddressBook／CoreData XPC 诊断不是 XCTest 断言失败或系统服务验收。期间不编辑项目文件；结束后只补文档，不改生产、服务和依赖。参考仍固定且干净，Typebar GUI 进程为零，真实背景成绩目录仍不存在；未修改真实系统日期、库或部署。

门禁后提交前定向 94 项再次零失败（2.252 秒），十模块 72 组源码夹具和 837 条场景结构检查再次通过；日志 `/tmp/typebar-elapsed-time-postgate-focused.log` 与 `/tmp/typebar-elapsed-time-postgate-source.log`。生产代码在完整门禁后没有改变。真实旧库、服务新协议、运行时单调来源及功能整体等价仍未验／未完成，不以本阶段自动化替代这些工作。

后续必须完成主计时单调来源、实时／最终速度、timer health／警告、AFK／物理键／weakspot／burst／回放的同一时间域、所有结束路径冻结时长、自动输入与重开，以及服务与运行时切换。日期不一致的资格检查、实体睡眠／系统时间修改、旧库升级／回退、窗口／IME／VoiceOver 和长期性能仍开放；主题、挑战、原始内容身份、账号等整体兼容缺口不因本机格式扩展关闭。

源码驱动以固定源码为依据；行为优先先复现可观察结果；迁移安全分离格式扩展与生产切换；会话内有界决策和风险复核处理墓碑隐藏、数据损坏、假能力和数值表示反例，非独立评审。文档技能明确保留来源限制和未验边界，保存 Markdown 不代表窗口渲染已验。
