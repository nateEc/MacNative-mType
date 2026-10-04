# Zen 结果重复入口

结果页的重复按钮与命令面板按固定 Monkeytype 源码分别处理。Zen 按钮显示提示、保持完成结果，不启动新会话；重复命令仍可执行。其他四种模式的两个入口保持重复行为。该增量不改变成绩、输入规则或归档格式，也不证明全部 Zen 功能等价。

## 固定来源和表述更正

只读参考提交为 91bd24bb8513785c7364cbea29296ff7adafac41。[结果按钮处理器](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/test-logic.ts#L1286-L1295) 在 Zen 模式提示并返回，不进入 restart。[结果重复命令](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/commandline/lists/result-screen.ts#L76-L89) 则只根据结果是否可见决定可用性，调用带 withSameWordset 的 restart，没有 Zen 条件。[重启入口](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/test-logic.ts#L176-L324) 也没有笼统禁用 Zen 重复的规则。

前轮 Zen 输入契约、功能盘点及人工清单把按钮限制概括为“禁用 Zen 重复命令／快捷键”，范围过大，现更正。不能为了统一按钮和命令而隐藏或封禁原版仍可用的命令，也不能把普通重启快捷键等同于重复结果按钮。

## 原生接线和状态边界

CompletedResultRepeatPolicy 按完成结果的模式及入口分派。CompletedResultView 的按钮传入 button，命令在原有退出面板及 Task.yield 之后传入 command；未增加任务、窗口或重复快捷键。Zen 按钮只更新本视图的提示文字，不调用父级 onRepeat，因此不清结果、不重置输入／声音／计时器、不吸收弱项或重新选标签／配速。提示采用原生可访问 Text；真实 VoiceOver 通知和焦点仍待验收。

策略适用于新、缺少准入标记和显式 false 的 Zen 结果；限制属于操作入口，而非历史数据迁移。TypingSession.repeatedAttempt 仍可调用，Zen 命令目录没有因空提示或无错词而隐藏重复。既有输入标记和配置原样保留；归档仍为 22，SwiftData 实体、偏好、服务协议及旧保存值不变，不补算、删除或写入用户成绩。

## 行为验证

先提取并接线现有无条件回调，保持旧行为，再运行六项测试。首次构建因测试配置漏填 difficulty／rules 而失败，未进入行为验证，不计有效先行失败。补齐后六项产生 17 处预期失败，0.430 秒：Zen 按钮清结果、调用重复且没有提示；普通模式和 Zen 命令作为通过对照。日志分别为 /tmp/typebar-result-repeat-red.log 和 /tmp/typebar-result-repeat-behavior-red.log。

加入按钮规则及两项扩展后，44 项中一项产生三处夹具失败，0.746 秒：result() 每次生成新 UUID，不能用两次投影的 UUID 验证会话不变。夹具仅排除这个生成字段，继续比较全部其他序列化字段；实际已保存结果的保留和完整字节不变仍独立断言。日志 /tmp/typebar-result-repeat-green.log。

最终新增八项零失败，0.013 秒；相关 44 项零失败，0.311 秒，日志 /tmp/typebar-result-repeat-final-focused.log。覆盖五模式／两入口、提示不清结果、连续按钮激活、提示后执行命令、nil／false／true 历史配置、结果字节保持、命令目录以及真实引擎底层重复。

Scripts/check-source-result-repeat.mjs 只读加载完整 test-logic 和 result-screen 两模块，53 组自有夹具通过，日志 /tmp/typebar-result-repeat-source.log。实际注册的按钮回调和实际命令均执行，包含五模式、重复配速开关、结果可见性、重启／计算守卫、下一轮及提示后命令。DOM 仅收集注册；通知、状态、事件清理等为显式适配。restart 在实际 fadeOutForRestart 调用处以未完成 Promise 截止，未运行 init、词生成、真实动画／定时器／浏览器／存储。潜在依赖越界调用报错，不把适配当作完整上游测试。

源码驱动技能促成入口差异更正，行为优先技能要求保留有效先行失败与夹具失败区别，小范围改动及会话内风险审查限制实现为操作策略和两处接线；文档技能分别记录模型、源码探针与设备证据，非独立评审。

冻结文件后完整串行门禁通过：客户端 2685 项零失败、零跳过，666.232 秒；服务端 145 项零失败，1.439 秒；808 条人工场景结构、固定参考／原创性／元数据等审计与未开窗 macOS 应用包通过。实际十万词耐久 145.825 秒，旧 12000 次组合簇删除双投影 0.025346 秒，不证明全部模式或设备性能。完整门禁及日志捕获进程均成功退出后才更新本段；运行期间没有改动输入文件。

日志为 /tmp/typebar-result-repeat-full-gate.log、/tmp/typebar-result-repeat-client-tests.log、/tmp/typebar-result-repeat-service-tests.log。包日志捕获尾部可能不完整，最终包结果以完整门禁成功退出及末尾结果为准。前后 Typebar 图形进程为零，真实背景成绩路径不存在；没有启动 GUI、删除用户数据或写真实成绩库。人工清单仍待验收，此前轮次的全量绿灯不代替本轮证据。

## 剩余验收

后续完整 finish 与 saveResult 前缀取证更正了此前“Bail Out 必然不保存”的假设：原版有效 Bail Out 可以进入保存，原生仍全部排除，见 [终止计时和保存缺口](TERMINAL_TIMING_GAPS.md)。这不改变本阶段对按钮／命令重复入口的独立证据，也不证明原生保存资格等价。

未启动 Typebar 图形实例，不做真实声音、用户库写入或服务部署。按钮鼠标／键盘／辅助功能激活、提示朗读与布局、命令面板退出时序、窗口恢复和真实旧库／降级仍未设备验证。上游完整初始化和 Zen 重复之后的结果保存资格不由本探针证明；无目标回放的设备与全组合、物理首尾／退出裁剪、全部组合、词库／主题及其他服务的差异继续追踪。整体 goal active，功能总账保持部分实现。

后续已补通 Zen 完成和历史回放入口、旧无字段呈现及零时刻／空事件动作，见 [Zen 结果和历史回放](ZEN_REPLAY_ACCESS_CONTRACT.md)；不将该补充视为前轮重复入口探针的证据，也不升级设备或整体完成状态。
