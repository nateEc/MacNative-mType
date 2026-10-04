# Zen 空格准入和字段位置

新生成的 Zen 会话在判断 opposite Shift 前按固定源码做输入准入：允许的平台空格归一化为 ASCII 空格，首空格按 strictSpace 和难度决定，三十 UTF-16 单位上限仍允许真实提交，并记录空目标的字段位置。工厂不再允许注入目标文本。旧结果、回放和原生底层重测保留捕获规则；本增量不证明完整 Zen 命令或设备等价。

## 固定源码与前轮假设更正

只读参考固定为 91bd24bb8513785c7364cbea29296ff7adafac41。实际 [words-generator](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/words-generator.ts#L429) 的 Zen 词限为零、词库为空；实际 [addWord](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/test-logic.ts#L572) 只添加空显示节点，不添加目标词。因此 Russian ё／е／e 和普通视觉标点没有实际目标可归一化，应保持输入原样。前轮仅从原生分支绕过普通归一化推测 Zen 遗漏，证据不足；现按真实空目标更正，不为通过测试添加不存在的目标。

实际 [before-insert-text](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/input/handlers/before-insert-text.ts) 先处理 No Space 空格拒绝，再做空格归一化、首分隔符和字段长度门控。Zen 中 hard delete 不让首空格通过；strictSpace 或非 normal 难度可以。上限是输入字段长度三十单位，真实 SPACE／LF 可以导航后继续输入。实际 [insert-text](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/input/handlers/insert-text.ts#L145) 在该门控之后处理替换及 opposite Shift：允许却因 Shift 被拒绝的键仍开始测试并记正确尝试，已被门控拒绝的键则不开始、不计尝试。空目标的 charIndex 取实际字段 UTF-16 长度，lastWord 为 false。

无目标的 Dutch ĳ 和省略号仍按原有展开表处理，展开后的各单位受上限约束；ĳ 并非所有语言都展开。参考明确空间集合之外的空白、Tab、CR 保持字面输入，只有 LF 导航。CRLF 在 Swift 是一个字形，但其 LF 单位仍是源提交。

正常配置 [funbox-validation](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/config/funbox-validation.ts) 拒绝 Zen 与 nospace 等目标约束属性组合。原生继续保留该互斥；本轮 No Space 输入对照仅是显式底层绕过配置门控的边界，不声称正常 UI 可以进入。源初始化、完整生成器和 UI 生命周期仅只读核对，未执行。

## 原生改动与数据边界

根因是原生 Zen 先进入独立分支，绕过普通平台空格规则；opposite Shift 也在其字段准入之前处理。新增可选 zenUsesSourceInputAdmission，只由实际 TestSessionFactory 对新 Zen 配置写入 true。新分支先拒绝不允许的空间，映射实际 UTF-16 单位为 32，再用同一 acceptsZenCharacter 检查首空格与上限，之后才判断 Shift 并记录字段位置。没有新增窗口或输入设备路径，也不引入虚构目标字符。

工厂对 Zen 忽略 streamPrompt 和相伴目标边界注入，继续使用空提示；其他模式的 streamPrompt 行为不改变。缺标记或 false 的旧配置继续保留字面平台空格、历史首空格／拒绝键和位置捕获。解码、导入及原始目标重复不补标记；只有新生成升级。新结果、归档、分享、活动选择和底层重复保留标记。非 Zen 孤立标记解码为 nil；Memory 将模式切为字数时同样清除，不让旧 Zen 策略泄漏。

配置 JSON 为可选加法，归档仍 22，SwiftData 实体、全局偏好和服务协议不变。旧 JSON 字节往返和结果严格相等，不回算旧指标。底层 native repeatedAttempt 仍可调用，不等于已经复刻原版禁用 Zen UI 重复的命令规则；该差异明确保留。真实旧库、双版本运行及降级未验证，旧二进制可能忽略标记，不能保证新快照降级后的重复等价。没有迁移、删除或写入用户成绩。

## 行为证据和夹具修正

先行八项中七项失败，共 85 处有效断言失败，0.526 秒（/tmp/typebar-zen-input-admission-red.log）。它们区分平台空间、首空间、Shift 前拒绝、单位上限／提交、底层 No Space 和字段位置；无目标 Russian／标点原样作为通过的对照。实现后同组八项零失败，0.034 秒（/tmp/typebar-zen-input-admission-green.log）。

首轮扩大相关 116 项中一项失败，0.687 秒：测试用 String.contains 判断 CRLF 中的 LF，误用了 Swift 字形语义。源码扩展同时误把 getInputFromDom 的末字段值当成整场输入。读取实际实现后，测试改为 UTF-16 LF 单位判断，源探针以实际 getInputForWord 逐字段结果拼接，并额外断言实际当前字段；原有文本、字段及尝试数断言未削弱。复跑 116 项零失败，0.244 秒。第一轮失败日志保留为 /tmp/typebar-zen-input-admission-expanded.log、/tmp/typebar-zen-input-admission-source-expanded.log。

有界决策复核再确认工厂 target 注入反例：追加一项先行三处有效失败，0.426 秒（/tmp/typebar-zen-input-admission-target-red.log），注入字面省略号目标会抑制自由展开。修复新 Zen 空目标边界后最终新增 17 项零失败，0.051 秒；相关 117 项零失败，0.239 秒（/tmp/typebar-zen-input-admission-target-green.log）。覆盖新旧保存与重复、false／外模式／Memory、空字段、删除再入、未知空白和 CRLF、原有展开及 cap、允许但被 Shift 停止的事件和工厂目标隔离。

源码输入探针在内存加载十四个完整实际模块，包括真实 Words，并保持其目录为空。新增 58 组 Zen 场景通过，之前普通／No Space／删除／多语／Dockerfile 组保持通过（/tmp/typebar-zen-input-admission-source-final.log）。Config、生命周期、空 UI、DOM 哨兵及浏览器删除是明确自有适配；完整目标生成、配置门控和浏览器事件循环未运行，不用虚构词池代替自由输入。既有生成／装饰／方向探针仍通过（/tmp/typebar-zen-input-admission-generation-source.log），不证明 Zen 真实初始化、原版词值或设备等价。

源码驱动、行为优先、根因调试和 Karpathy 技能要求先验证假设再接线；会话内决策、风险和迁移复核以空目标、门控顺序、CRLF 单位、旧快照、跨模式和注入目标为反例，非独立评审。文档写作技能区分源观察、原生模型及待人工验收。

文件冻结后完整串行门禁通过：客户端 2677 项零失败、零跳过，667.531 秒；服务端 145 项零失败，1.566 秒；807 条人工场景结构、固定参考／原创性／元数据审计及未开窗 macOS 应用包检查通过。完整日志 /tmp/typebar-zen-input-admission-full-gate.log；完整客户端及服务端捕获为 /tmp/typebar-zen-input-admission-client-tests.log、/tmp/typebar-zen-input-admission-service-tests.log。包捕获尾部可能不完整，最终包结果以完整门禁日志为准。

同轮十万词耐久实际通过 145.522 秒，旧 12000 次组合书写簇删除双投影 0.025583 秒；这些不是 Zen、混合 Unicode 或设备性能等价证明。门禁前后 Typebar 图形进程为零，真实背景成绩路径不存在，固定参考工作树干净，没有删除用户数据。门禁与日志捕获进程均成功退出后才补记文档，活跃编译／测试期间未修改输入文件。

## 剩余验收

Zen 原版禁用重复的 UI／快捷键、剪裁退出／结果消费者、真实 marked text／IME／键盘／VoiceOver、浏览器生命周期、真实旧库与降级、全部输入组合和长期性能仍未完成；复杂原始目标游标、词库与主题、其他服务也不因本轮补齐。人工场景仅待验收，整体 goal active。只运行内存成绩库和未开窗包，不启动 Typebar、不播放音频或部署。
