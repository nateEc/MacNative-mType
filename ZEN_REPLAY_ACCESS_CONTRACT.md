# Zen 结果和历史回放

Zen 的完成页与历史详情不再因空生成提示而隐藏回放。完整字段记录进入既有的字段回放，支持播放、暂停、时间拖动、重置与字符定位；旧无字段记录回放已接受文本，不补造目标或坐标。该增量保留原始事件、输入准入和保存成绩，设备及全功能等价仍未证明。

## 固定源码和根因

只读参考为 91bd24bb8513785c7364cbea29296ff7adafac41。[replay-ui](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/replay-ui.ts#L42-L148) 对 Zen 从实际输入历史建立展示词，不依赖生成目标。目标节点来自最终历史，各事件改变标记和游标，因此删除前也会看到最终词文本，而非逐时重建的原文本。定位恢复按动作序号，不以同时间事件合并成一个动作；声音在恢复已消费动作时静默。

原生 FieldReplayPlan 已有 Zen 字段与目标历史逻辑，但 CompletedResultView 和 ResultDetailView 都要求 prompt 非空，导致真实空目标结果没有回放入口。旧无字段事件回退又用普通目标比较，自由文本会被标成多打。零时刻旧日志的播放按钮还因没有 fieldPlan 被禁用。源码有界探针另确认已记录的空 insertText 仍产生一个游标／点击动作；原生记录字段的回放先跳过空文本，遗漏该动作。

## 原生行为和数据边界

两个页面共用 ResultReplayAvailability：记录存在且提示非空，或已知配置为 Zen 时展示；无记录和未知模式的空提示保持隐藏。完整字段仍复用同一 FieldReplayPlan，不改生成器、准入或输入捕获。播放可用性在视图初始化时计算一次，旧零时刻日志也可播放；无动作的零时刻记录保持禁用，正常非零时间控制不改变。

TypingReplay.inputGlyphs 接收可选配置。明确 Zen 的旧无字段回退使用既有 accepted-text 重建，显示正确而非虚构目标错误；未确认／停止输入仍按原始记录排除，控制符和 Unicode 不重新归一化。不显示不存在的目标字符定位区，但保留时间滑杆；字段路径保留字符定位。已捕获空 Zen insertText 在字段导航之后增加一个空显示动作，游标／点击推进一次，不增加接受文字或计量，停止事件不生成该动作；普通模式的空事件政策不改。

新、nil 和 false 的历史准入标记均可展示，不升级配置。JSON 结果、未接入磁盘的 TestResultRecord 及原始事件字节有保留断言；没有实体、设置或服务协议变更，归档仍 22，不重新计算保存值、重复资格或中止保存规则。真实旧库、降级、混合版本尚未验证；未知或不完整字段仍按既有回退，不猜词界。

## 验证证据

先提取并接线旧显示条件和配置参数，不改变行为，再运行四项测试。四处有效先行失败，0.458 秒，分别暴露完成／恢复记录不可见和旧文本错误标记，普通模式作为通过对照。日志 /tmp/typebar-zen-replay-red.log。实现后相关 105 项零失败，0.547 秒，日志 /tmp/typebar-zen-replay-green.log。

零时刻播放的独立先行一项一处失败，0.416 秒（/tmp/typebar-zen-replay-zero-red.log）。扩展 114 项仅一处夹具断言失败，1.048 秒：既有 AppKit 空视图保留“等待播放”，测试误要求空字符串。保留产品提示并修正夹具，文字、样式状态和缓存断言不削弱。日志 /tmp/typebar-zen-replay-expanded.log。空插入源对照随后产生一项六处有效失败，0.418 秒，日志 /tmp/typebar-zen-replay-empty-red.log；修复游标／声音后追加跨字段反例。

最终新增 15 项零失败，0.090 秒；相关 154 项零失败，0.728 秒，日志 /tmp/typebar-zen-replay-final-regression.log。覆盖实际 Zen 会话、恢复结果与未接盘实体、legacy 标记／中止、不明模式与空事件集、停止事件、旧 Unicode／控制符／删除、同时间 seek 续播及不重复点击、最终输入目标删除标记、千字段完整文字和 3001 个一次性动作、无窗口 AppKit 文本更新，以及空事件和跨字段导航。不播放真实音频，不冒称 SwiftUI sheet、定时器或设备验收。

Scripts/check-source-zen-replay.mjs 在内存加载 replay-ui、stats、helpers、strings 和两种 numbers 共六个完整实际模块，13 组自有夹具通过（/tmp/typebar-zen-replay-source-final.log）。实际 getInputHistory、deriveReplayActions、initializeReplayPrompt、handleDisplayLogic 和 loadOldReplay 执行；测试桥只导出私有状态。目标目录适配一旦被 Zen 访问即报错；事件存储、DOM、声音、配置／类型及未使用的 Hangul 为显式适配。没有运行真实输入／IME、浏览器定时器、布局或音频；未据此证明原生逐单位 Unicode 的全组合等价。

源码驱动、行为优先及根因技能把问题定位到页面守卫、旧模式回退和空事件动作；小范围改动与会话内风险复核保护既有普通回放、零时刻、字段游标和旧结果，非独立评审。文档技能区分实际模块、原生模型、AppKit 无窗口和人工证据。

文件冻结后的完整串行门禁通过：客户端 2700 项零失败、零跳过，665.700 秒（含十万词耐久 144.668 秒）；服务端 145 项零失败、零跳过，1.561 秒；旧回放 12000 次组合字形删除双投影 0.025414 秒。原创性／固定元数据／页面与服务清单／布局／主题／挑战／行为证据、809 个唯一人工场景的清单结构及未打开的应用包检查通过。日志 /tmp/typebar-zen-replay-full-gate.log、/tmp/typebar-zen-replay-client-tests.log 和 /tmp/typebar-zen-replay-service-tests.log。日志抓取进程在门禁临时目录自动清理时错过最后一次 package-check.log 复制；打包结论来自完整门禁日志及其零退出，不以抓取日志代替。人工清单仍待验收，未启动 Typebar 图形进程，真实后台练习路径仍不存在。

## 剩余验收

后续完整结束链路已确认未剪裁的原生计时／AFK 网格，以及一律拒绝 Bail Out 保存均存在差异，见 [终止计时和保存缺口](TERMINAL_TIMING_GAPS.md)。本合同的“中止保存规则不变”仅描述回放增量没有更改原生行为，不证明那条旧规则符合原版。

本轮不启动 Typebar 图形实例、不写真实成绩库或部署服务。完成／历史入口的实际显示、点击／拖动／暂停／重置、焦点与 VoiceOver、真实声音、长时间内存和全部 IME／Unicode 组合仍需单实例设备验收。Zen 正常结束与 Bail Out 的物理首尾剪裁、图表／保存资格及其他消费者继续单独核对；完整词库／主题、服务与总体功能等价未完成，goal active。
