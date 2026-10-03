# 删除源位置与格式 20 合同

固定只读参考：91bd24bb8513785c7364cbea29296ff7adafac41。依据完整 input/handlers/delete.ts、before-delete.ts、input/helpers/word-navigation.ts、input/input-element.ts 与 events/data 的当前快照读取。原生代码与夹具独立编写，没有参考代码／资产进入实现。

## 一个动作，两个位置时点

词内删除的 source charIndex 是删除前 getCurrentInput 的 UTF-16 长度，inputValue 是删除后快照；普通／整词退回上一词则使用导航后目标字段长度。有限末词清空后的原快照不能冒充空元素，退回时仍记录目标长度。代码 unindent 的清 Tab 动作为 deleteWordBackward，位置取清空前长度；目标字段动作是独立 deleteContentBackward，位置取导航后的长度，首字段无前词时也记录零长度 no-op。

新可选 TypingReplayEvent.deletionCharIndex 独立于插入 inputPosition，不伪造删除的 lastWord。一个逻辑手动删除只在其最后原语保存位置；已有 wordDeletionCount／characterDeletionCount 仍标首原语。普通 Backspace、Option-Delete、代码 unindent 两组接入，markDeletion 复制时保留元数据。计算取真实当前／目标字段，不从拼接字形数推导。没有字段的未知 no-space 路径缺省；自动恢复、replaceInput 与其他未取证路径仍缺省，不把上次插入位置带过去。

此字段只记录观察，不改变删除数量、raw UTF-16 标记、接受文本、回放字段动作、声音／seek、计分或历史。ASCII 旧原语仍是字形删除，代理删除仍由既有原始单位合同解释。解码要求非负整数、删除 kind、空 payload 与非负索引的已记录字段；插入、无字段、负数、类型错误拒绝。允许大非负诊断数值但从不以它分配数组、切片或决定删除数；生产者值来自字段长度。本验证是单事件形状验证，不冒充对任意导入日志跨动作组来源的证明。

## 持久化与回退边界

默认正式归档 20；含删除位置最低 20，构造低版本提升、正式导入伪装 1–19 拒绝。真正旧 1–19 缺字段仍 nil，不补造位置或重新计分。独立自有旧 14 BMP 原语、旧 19 分类／删除夹具保留最低版本、单位和固定成绩；16 插入位置、17 收缩、18 清空及 19 分类的独立最低版本保护仍在。

沿用 TestResultRecord.replayEventsData JSON，不增实体列、不改设置文档或服务协议。正式／便携往返、内存 SwiftData 保存取回检查完整结果，未打开真实成绩／设置库。真实旧库、旧二进制直接读新实体 JSON、降级／混合同步仍未验证；旧版本可能无法保留新字段，必须保存升级前备份，不能由旧程序覆盖唯一副本。本轮不部署／跨设备操作。

## 先行与扩展证据

先行夹具的不存在语言枚举编译错误单列，未进入断言；核对邻近测试改用 codeSwift。四项随后七处有效失败（0.408 秒）；接入后四项一处失败（0.463 秒）是首字段夹具默认补入第三枚 Tab，与明确两枚的源码夹具不同。改为 defersAutomaticInput 的两枚夹具并断言删除前文本，不改变补缩进实现；扩展 70 项零失败（0.258 秒）。

更大扩展 302 项一处失败（2.089 秒）：旧 BMP 测试借用当前新位置会话却要求最低 14。保持原始单位／字段断言，新会话要求 20，另增加独立真正旧 14 夹具，最终 303 项零失败（1.709 秒），旧 12,000 次双投影 0.026116 秒。新增 DeletionPositionCaptureTests 十项、DeletionPositionArchiveTests 六项及旧 BMP 一项，共十七项。

现有 Scripts/check-source-input-position.mjs 增加实际 delete／before-delete 完整模块。旧八个插入场景仍通过；新十个删除场景覆盖词内／代理、普通与整词退回、整词清空、有限末槽、两个代码动作、首槽 no-op、模拟 Firefox 清空 sentinel、confidence 阻止。13 个实际完整模块在内存执行；新删除场景显式 seed 目标／事件快照，浏览器编辑以 sentinel 和 UTF-16 slice／整词清空适配，Config／TestWords／UI／生成／生命周期是绑定。实际日志器、当前快照、导航及两个 handler 执行，不修改行为函数；没有真实浏览器、系统词删除、DOM／RAF／IME、Korean、Firefox 或音频验证。

最终完整串行门禁客户端 2,336 项零失败（443.297 秒）、服务端 131 项零失败（1.433 秒），781 条唯一人工清单结构检查、固定参考、原创性／元数据、布局、页面／服务、主题／挑战身份与行为证据审计，以及未打开原生包构建／签名和资源边界检查通过。当前 pD4om4 客户端日志的实际十万词 passed 行在清理前读取，88.690 秒；旧 12,000 次双投影 0.025716 秒。不升级尚未映射或未验身份。门禁成功退出，固定参考干净，Typebar 图形进程为零，真实背景成绩路径不存在；没有真实库／音频／部署操作。人工 INPUT-DELETE-SOURCE-POSITION-01 保持待设备验收，无窗口测试不代替实际键盘／VoiceOver／布局或真实库迁移，普通十万词不证明混合删除性能。

## 会话内复核与开放工作

源码驱动、行为优先、根因调试、Karpathy 与有界决策／风险／迁移复核影响实现，非独立评审。重点反例为前后长度不同、代理／融合字形、跨字段整词多原语、代码两动作及首槽 no-op、最低版本假旧和复制字段丢失；目前自动化边界已检查。字段快照获取仍有已有长度成本，本轮普通十万词不证明删除混合／大单词性能。

自动恢复／replaceInput 等位置捕获、完整 commitsWord／lastWord 导出、缺目录／混合日志、其他消费者、Korean／Firefox、真实 IME／UI／旧库／降级、官方主题／词库、部署与混合性能继续开放。94 配置与部分 Funbox 不升级，完整 goal active，不缩减为日志里程碑完成。
