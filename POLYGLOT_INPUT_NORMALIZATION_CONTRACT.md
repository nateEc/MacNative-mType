# 多语主语言输入替换与历史拼写保护

新生成的多语会话用方向处理后的主语言选择已有荷兰语和俄语输入规则，不再因语言入口为 mixedLanguages 而漏掉替换，也不随当前候选的语言身份启用规则。荷兰语小写 ĳ 在非字面目标时展开为 i、j；俄语 ё、е、e 保留实际目标字符作为输入和回放。这是有界输入增量，不证明完整词库、Zen 或设备等价。

## 固定源码依据

只读参考固定为 91bd24bb8513785c7364cbea29296ff7adafac41。实际 [insert-text.ts](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/input/handlers/insert-text.ts#L145) 按 removeLanguageSize(Config.language) 选择荷兰语替换；目标本身是 ĳ 时保持字面字符，Ĳ 不在替换表中。实际 [input/helpers/util.ts](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/input/helpers/util.ts) 用输入字段当前位置和 Config.language 进行视觉等价归一化，返回实际目标字符。实际 [strings.ts](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/utils/strings.ts#L275) 的俄语集合为 ё、е、e；移除数字规模后仍为专业变体的语言不进入普通俄语集合。

源码主语言不必属于候选池；输入模块不读取每词候选身份。生成方向调整是另一个前置边界，原生测试使用真实准备流程确认切到 Arabic 后不继续应用原 Dutch 或 Russian。输入源探针显式提供已解析主语言与自有目标，不把它当作执行过真实生成或方向切换。

## 原生修复与兼容边界

根因是已有 Dutch 替换及 Russian 等价判断读取 configuration.language；在多语会话中这是混合入口，而不是实际主语言。新增可选 polyglotUsesPrimaryInputNormalization，仅由 PolyglotGenerationPreparation 在方向处理后为新生成配置写入 true。统一 inputNormalizationLanguage 只在标记为 true 且保存有效主语言时使用该主语言，其他情况返回原入口。接入 Dutch 展开、普通归一化和 ASCII e 快速路径，不改变代码缩进、目标生成、实体列或窗口路径。

新结果、正式归档、分享、活动选择及原始目标重复保留标记。缺标记（包括已有方向／代码输入标记的旧配置）或显式 false 的快照保留旧混合输入拼写；解码和导入不回填，原始目标重复不升级，只有真正新生成升级。移除有效主语言同时清除此标记，外语或无主语言的孤立标记在解码中舍弃。既有成绩、回放和固定指标不回算。

配置 JSON 为可选加法；归档仍 22，SwiftData 实体、全局偏好和服务协议不变。旧 JSON 字节往返和结果归档严格相等已测试。旧二进制可能忽略新字段，降级后新会话的重复不保证等价；真实旧库和双版本运行未验证，没有删除、迁移或写入用户成绩。

## 自动化证据

先行 8 项测试中 4 项失败，共 60 处有效断言失败，0.476 秒（/tmp/typebar-polyglot-input-normalization-red.log）；它们揭示普通俄语／规模俄语、Dutch 展开及 batch／已知 No Space 的输入、判定、回放和位置差异。字面／大写 Dutch、仅候选语言、方向切换及旧配置为通过的反例。生产实现后同组 8 项零失败，0.018 秒（/tmp/typebar-polyglot-input-normalization-green.log），未弱化断言。

扩大后新增 15 项零失败，0.026 秒；相关 97 项零失败，0.243 秒（/tmp/typebar-polyglot-input-normalization-expanded.log）。新增归档／分享／选择／重复、旧固定指标与 JSON、false／孤立标记、清主语言、全局标点与规范等价仍拒绝、删除后再输入及词数／计时新生成升级。既有候选测试仅将新标记加入严格完整配置期望，不改为字段子集比较。自有 streamPrompt 和隐藏词界只作输入模型夹具，不作为真实词库或 AppKit 证据。

输入源探针在内存加载十三个完整实际模块，新增 32 组主语言替换场景通过（/tmp/typebar-polyglot-input-normalization-source.log）：俄语九种配对、七种规模、三种专业负例、三种 Dutch、字面／大写、English 负例、批输入、已知 No Space、全局标点、规范不等及删除再输入。既有插入／删除／普通末 SPACE／多语代码／单语言 Dockerfile 场景保持通过。目标、Config／Polyglot 标签、DOM 哨兵与删除为明确自有适配，没有替换源码行为函数，也不把 FIFO／微任务适配称为浏览器事件循环。源码和资产未进入原生实现。

源码驱动、行为优先、根因调试与 Karpathy 技能限定为已有规则接线；会话内决策、风险和迁移复核以旧标记不升级、候选语言不泄漏、方向已切换、规范等价不宽松及孤立字段为反例，非独立评审。文档写作技能将自动化、源观察和待设备验收分开。

文件冻结后完整串行门禁通过：客户端 2660 项零失败、零跳过，664.283 秒；服务端 145 项零失败，1.612 秒；806 条人工场景结构、固定参考／原创性／元数据审计及未开窗 macOS 应用包检查通过。完整日志 /tmp/typebar-polyglot-input-normalization-full-gate.log；完整客户端及服务端捕获为 /tmp/typebar-polyglot-input-normalization-client-tests.log、/tmp/typebar-polyglot-input-normalization-service-tests.log。包捕获尾部不完整，包最终结果以完整门禁日志为准。

同轮十万词耐久实际通过 143.919 秒，旧 12000 次组合书写簇删除双投影 0.025470 秒；不证明多语、Zen、复杂 Unicode 或设备性能等价。门禁前后 Typebar 图形进程为零，真实背景成绩路径不存在，固定参考工作树干净，没有删除用户数据。门禁和日志捕获进程均成功退出后才补记文档结果，活跃编译／测试期间没有修改输入文件。

## 剩余验收

Zen 在现有独立输入分支中仍绕过普通 Russian 归一化，本增量不宣称已补齐；Dutch 对复杂原始 Unicode 字段的字面目标游标、全部词提供器／Funbox 组合、原版词值和分布、真实配置通知／加载失败恢复、实体键盘／IME／GUI／VoiceOver、真实旧库与降级、长期联合池内存、其他服务和主题仍开放。人工场景仅登记待验收，整体 goal active。门禁只用内存成绩库和未开窗包，不启动 Typebar、不播放音频、不部署。
