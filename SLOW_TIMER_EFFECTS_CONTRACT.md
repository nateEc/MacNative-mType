# 慢计时独立状态与效果抑制

短测试触发慢计时后，Slow Timer 标志独立于临时 30 FPS 覆盖保持锁存。改帧率或清除 FPS 覆盖不重新允许打字粒子与震动；正常计时交付也不解除标志。结果页采用结束时捕获的抑制值，避免练习健康状态重置后错误地播放庆祝。完整重写 goal active，CFG-02 与 MET-67 仍部分兼容。

## 固定源码规则与原生接线

参考 `91bd24bb8513785c7364cbea29296ff7adafac41` 的完整 `legacy-states/slow-timer.ts` 模块保持独立布尔状态。`test/test-timer.ts` 的完整 `clear` 只恢复 FPS，不清除 Slow Timer；`start`、计时到期、最低速度／准确率失败则明确清除。`elements/monkey-power.ts` 的完整 `addPower` 在标志开启时直接返回，不安排新粒子或震动；`test/result.ts` 的完整 `showConfetti` 同样直接返回。

原生 `TimerHealthState.usesSlowTimer` 在既有适用短测试的超过 125 毫秒延迟处锁存，不跟随设置代次失效。FPS 恢复、严重延迟计数和失败判定沿用原规则；非有限延迟仍保留既有保守失败行为，不将其称为 JavaScript 非有限输入等价。

打字效果入口将独立标志传给 `TypingPowerPolicy`，只阻止新发射，不清除此前已存在的粒子。完成回调在重置健康状态之前捕获庆祝抑制值；正常与无压力结果页都传给实际 `ResultCelebrationView`。计时到期及最低阈值失败按源函数解除抑制，普通字数完成、其他失败或中止保持原标志。固定正时长的原生完成／AFK 终态在此对应计时到期，完整原版结束调度仍独立追踪。

仅当前状态和私有结果呈现快照增加字段。归档 32、设置 5、偏好 v3、五实体／32 列、六个历史 writer 及服务协议不变；不将 Slow Timer 写进成绩、回放或偏好。没有新增产品依赖、参考源码或资产，既有布局、配色与粒子绘制保持不变。

## 回归与源码对照

先行三项产生七个有效失败断言，日志 `/tmp/typebar-slow-timer-effects-red.log`，覆盖独立锁存、FPS 恢复后保持，以及粒子／庆祝触发。扩展夹具初次遗漏必需 `rules` 参数而编译失败，日志 `/tmp/typebar-slow-timer-effects-focused.log`，不计为行为反例。修正后相关 87 项通过，4.273 秒，日志 `/tmp/typebar-slow-timer-effects-fixed-focused.log`。

收紧结束路径夹具后，最终相关 87 项零失败零跳过，4.239 秒，日志 `/tmp/typebar-slow-timer-effects-final-focused.log`。新增七项覆盖独立锁存、阈值／不适用模式、设置代次恢复、结束快照、效果策略、偏好／成绩归档隔离、完整源码对照及实际庆祝组件绘制。既有计时、帧率、整行滚动、输入反馈和结果优先级回归保持通过。

`Scripts/check-source-animation-frame-rate.mjs` 的 50 组／550 步改为执行真实完整 Slow Timer 模块，不再用自有布尔替身；原生逐步比较新增标志，实际 Anime.js 引擎 FPS 对照继续保留。新 `check-source-slow-timer-effects.mjs` 另执行完整状态模块及计时检查／清除／启动／阈值／到期／效果函数，覆盖十种配置、70 步生命周期、350 个 Power 调度入口、70 次完整 Confetti 函数调用及 47 个适用结束路径。

新探针的时钟、通知、调度和绘制边界是自有替身：Power 只验证是否安排回调，不执行回调内部粒子生成；Confetti 执行首次两侧调用，不运行之后的 RAF 循环。字数完成／中止的对照使用完整 `clear` 函数，不冒称执行完整上游完成控制器。初次探针补齐 `timerDebug` 和可构造时钟替身后才以退出码零通过，不把早先输出的通过文字当成功证据。

未显示的 NSWindow 中，实际生产庆祝组件在正常状态绘出彩色粒子，Slow Timer 快照下像素保持黑色背景；两图 `/tmp/typebar-slow-timer-effects-qa.pnavJc/normal-celebration.png`、`slow-suppressed.png` 已检查。离屏组件不等于整应用、真实 FPS 或系统效率模式验收，零 Typebar 图形启动。

## 仍开放的输入与时序范围

`input/handlers/before-insert-text.ts` 还有普通状态下阻止额外字母使整词或词内字母换行的布局检查，Slow Timer 时跳过；原生尚未接通该完整检查。`test-ui.ts` 的 `updateWordLetters` 在 Zen／Slow Timer 下处理同一活动词重排，含 `lineTransition` 与 `wordTopBeforeLineJump` 顺序，仍未全量对齐。此次独立标志与效果抑制不关闭这些词更新缺口，也不以光标可达性替代原规则。

原版 RAF 回调在排队后才遇到慢计时、已有粒子寿命、完整结束调度、重叠换行队列、混合字体、特殊渲染、实体键盘／IME／VoiceOver 和显示器仍待对照。会话内决策与风险复核检查独立状态、结果捕获早于健康重置、两种结果页接线、适用结束路径和持久数据边界，不是独立审计。两个人工场景保持待验收，不缩减完整目标。

## 最终完整验证

冻结版本完整串行门禁通过：原生 3,323 项零失败零跳过，716.661 秒；服务 465 项零失败零跳过，10.370 秒。十万词耐久实际执行 150.820 秒，15 项磁盘迁移冷读 6.032 秒；997 个人工场景仅结构审计通过，未开窗应用包、签名、资源及原创性边界通过。

36 份保留日志在 `/tmp/typebar-slow-timer-effects-final-logs.xlS5vn`，总日志 `/tmp/typebar-slow-timer-effects-final-readiness.log`。四个产品源文件、两个测试、两个源码探针及门禁脚本共九个 SHA-256 与冻结值一致，门禁后仅补验证文档。既有系统 Contacts XPC 提示、隔离坏库及故意只读保存错误不是 XCTest 失败。零 Typebar 图形启动、真实用户库写入与服务部署；词重排、输入布局保护及完整功能等价未完成，goal active。
