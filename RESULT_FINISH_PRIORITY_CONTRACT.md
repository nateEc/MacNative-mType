# 结束资格检查与结果提示顺序

2026-10-04：原生结束评估现在对已完成、失败、闲置无效和中止结果走同一个有序检查链。原引擎 outcome、失败详情和测量快照不改写；结果标题、说明、练习栏和发布提示按优先原因显示。失败／闲置仍绝不保存；重复的闲置结果按独立规则结转待保存练习时间。完整原生重写 goal 仍 active。

## 固定源码规则

依据只读固定 `91bd24bb8513785c7364cbea29296ff7adafac41` 的 [完整 finish 函数](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/test-logic.ts#L883-L984)。主要资格链依次为日期一致性、测试失败、过短、结束前闲置、重复、WPM、Raw、准确率。日期检查仅用于非 BailOut 的 time，且有效标量不超过 120 秒；非 custom 标量先舍入。测试失败不将结果标为 invalid，但前面的日期不一致可以标为 invalid；二者都禁止保存。过短优先于闲置，闲置优先于重复及速度／准确率。

引语会先清除重复标记，不免除过短、闲置或失败；BailOut 跳过日期一致性和闲置，不免除其他资格规则。独立的 incomplete 结转在主要资格链之后按“重复或测试失败”执行，不能因为更早的无效原因抢先命中就省略。关闭结果保存时不结转；成功保存后的现有清理仍保留。

## 原生调用与数据边界

`ResultEligibilityPolicy` 不再提前将失败／闲置结果返回为 eligible。新的暂态 `testFailed` 与 `inactivity` 原因与日期、过短等原因组成同一链；`invalidReason` 区分“不保存但仅失败”与“无效”。活动／放弃结果不进入链。`ResultSavingPolicy` 的原 outcome 白名单不放宽，重复闲置只进入 `PriorAttemptLedger`，不是新增一条历史成绩。

ContentView 仍捕获原来的 outcome、failureReason 和快照。在结果窗口及练习栏显示主资格原因，并在只有失败时保留具体计时／速度／准确率／生成失败解释。BailOut 仍明确显示中止状态及自身保存说明。结果卡／回放等不携带暂态资格原因，原数据不重写，不能据此声称所有导出消费者都新增了原因字段。

日期独立检查只用于具有明确 elapsedTime 的新结果；旧无字段成绩不补测量证据、不回算小数。没有 SwiftData 新列、归档版本变更、设置变更、服务协议变更或依赖变更；归档 25、设置 4、macOS 14 目标保持。没有触及真实数据库、系统时间或部署。

## 验证证据

新增 `ResultFinishPriorityTests` 16 项，包含实际独立时钟驱动的闲置及计时失败、各分支优先级、BailOut／引语例外、不可保存保证、重复闲置结转／关闭／清理、反馈语义与 120.004／120.005 边界。先行夹具参数顺序编译错误不计产品 RED；修正后的旧实现实际运行 11 项，产生 12 个有效失败断言：`/tmp/typebar-finish-priority-valid-red.log`。

首轮扩大 82 项仅一处旧夹具失败：单词末字符落在 16.125 秒被舍弃的尾段，原结果实际是 invalidAFK，却断言 eligible。修正夹具在保留的最后区间加入输入，并明确要求 completed；16.125 秒、真实日期倒退、存储／归档／匿名发布证据断言保留，不放宽 AFK。修正后 86 项通过；有界会话内复核补充 120 秒边界后最终 87 项零失败／零跳过（0.235 秒）：`/tmp/typebar-finish-priority-reviewed-focused.log`。这是会话内复核，不是独立评审。

`Scripts/check-source-terminal-timing.mjs` 现在 92 组自有夹具执行十个完整实际模块，其中新增 14 组执行完整 finish 的冲突顺序、invalid 标志、禁止投稿和独立 incomplete 结转；两侧 120 秒边界也执行真实标量生成。日志：`/tmp/typebar-finish-priority-reviewed-source.log`。身份、timer end、hash、UI 和 503 transport 为明确替身；没有成功服务保存、完整浏览器、IME、睡眠或原生窗口等价声明。原版源码只读／内存执行，不复制到生产或包内。

完整串行门禁已通过：客户端 2882 项零失败／零跳过（687.147 秒），服务端 175 项零失败／零跳过（1.639 秒）；同一门禁十万词实际通过 148.564 秒，新增 16 项通过 0.022 秒，历史磁盘七项再次通过 4.637 秒。849 场景仅结构检查，固定源码、原创性／元数据审计和未开窗应用包通过。

门禁与清理前捕获的完整客户端／服务日志：`/tmp/typebar-finish-priority-readiness.log`、`/tmp/typebar-finish-priority-gate-client.log`、`/tmp/typebar-finish-priority-gate-server.log`。应用包证据是门禁末尾通过行，没有单独完整包日志。门禁后相关 87 项再次零失败／零跳过（0.226 秒）及完整源 92 组再次通过：`/tmp/typebar-finish-priority-postgate-focused.log`、`...-postgate-source.log`。全量中的故意坏 SQLite 诊断及系统 XPC 日志不算 XCTest 失败；以实际通过数和门禁终态为准。没有启动 Typebar GUI，真实后台队列目录仍不存在。

推荐含耐久检查的正式命令：

```sh
TYPEBAR_ENDURANCE_TESTS=1 zsh Scripts/check-native-rewrite-readiness.sh /absolute/pinned/monkeytype-reference
```

新增三项人工场景仍待验收；真实窗口提示优先级、短 time 系统日期跳变、IME／后台、最低系统、旧发行库／恢复及整体功能等价未由无窗口测试证明。未知／NaN 对象构建诊断、完整成功联网结束链也不在本合同的新增覆盖中。
