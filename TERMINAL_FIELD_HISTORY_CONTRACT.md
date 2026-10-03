# 末词回退：导航、保存历史与计分

本增量继续完整原生重写，三种读者不得合并。固定源码为 91bd24bb8513785c7364cbea29296ff7adafac41；没有参考代码或资产进入实现。

## 源码合同

[实际删除处理器](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/input/handlers/delete.ts) 在删除 sentinel 后回退，并在原当前快照非空时把 clearedNextWord 放到目的词事件。有限末词导航清空元素但保留快照，因此普通退格也可能触发，不仅是 Firefox 特殊删除。[getInputForWord](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/events/data.ts) 仍读取未来词桶原快照；这不等于保存历史。

[完整统计模块](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/events/stats.ts) 的 getInputHistory 在前词存在严格更晚的标记时将后词历史置空，等时不置空，后词后续新事件可以恢复。getChars／速度曲线不套用此清空：按原始词桶、首次出现顺序读取末快照，活动词为最高非空字段；只有最后一个输入 SPACE 才再加一。原输入／目标的比较遵循 UTF‑16；timed／bailout 可以给推导活动词的正确前缀信用，其他词需完整匹配。

自有目标 ab／cd，单批 abcd 加被预拒绝的 SPACE 后，末词元素为空、原快照 cd。freedom 允许回退，一秒后普通退格：接受缓冲／文本回放为 a，保存历史为 a／空，原计分桶为 a／cd，活动计分词仍为 1。bailed-out 信用 2 单位、raw 3 单位；前词 a 不能因光标退回就获得前缀信用。等时退格的保存历史仍是 a／cd。整词退格可让接受文本与保存历史全空，但原 cd 桶仍给 2 单位信用。代理字段使用两单位，不把一个安全显示 glyph 当一个速度单位。

本轮原生采用独立 RecordedInputFieldStats：源时间较旧的延迟事件不覆盖较新快照，等时取后到快照；首次词桶时间变化才稳定重排，正常输入不在每键排序。no-space live WPM／raw WPM 与新结果 inputMetrics 读取原计分桶；原生字符数依旧为解码后 glyph 数，速度为单位数。词审查与 SavedTextInputHistoryPolicy 读取带明确清空的保存历史。既有目录曲线本已读取原桶，未使其改用清空后的历史，新增测试证明两者速度一致。characterStats 仍为接受映射描述，不冒充 source getChars 全分类。

## 格式 18 与迁移

TypingReplayEvent.clearedNextWord 可选，只接受 true、有效原始删除与非负且小于 Int.max 的目的字段；避免后词加一溢出，不按未可信索引分配占位数组。当前只在新有效 no-space 末词清空后手动回退捕获，不猜 ordinary／未知词界／自动恢复／真实 Firefox 的缺失标记。整词动作的原始首条删除保留标记与原动作范围，既有收缩仍负责接受文本。

默认正式归档为 18；含标记的显式构造最低 18，正式导入拒绝伪装 1–17。真正 1–17 不反推此标记、不补造数据、不重算成绩；自有真正 17 收缩夹具保持旧固定 19／29／77 指标、旧保存历史与单位回放。标记在既有 replayEventsData 内，实体列、设置与服务协议不变。内存实体、便携与正式往返通过，不证明真实旧库、旧二进制直接读新 JSON、降级或混合版本同步；保留备份，不交给旧程序覆盖唯一数据。本轮没有操作真实库或部署。

## 证据与边界

TerminalFieldHistoryTests 十三项覆盖真实普通／整词回退、等时、代理、重入、停止、曲线一致性、源时间缓存、格式拒绝、旧 17 夹具、内存 SwiftData。先行四项 17 处失败（0.416 秒）后转绿（0.006 秒）；扩大最终 241 项零失败（8.703 秒），末次十三项零失败（0.050 秒）。最终完整门禁客户端 2,293 项零失败（444.621 秒），服务端 131 项零失败（1.388 秒）；当前 maHgl4 实际 100,000 词耐久 passed 行在清理前读取，87.820 秒，旧 12,000 次双投影 0.025365 秒。778 条人工清单仅结构检查通过，不是设备验收；原生包构建／签名、资源边界与各审计通过，未打开应用。门禁后参考检出干净且固定，Typebar 进程为零，真实背景成绩路径不存在。不把普通耐久测试扩展为 no-space／混合性能证明，也不把审计绿色扩展为全功能兼容。

Scripts/check-source-terminal-history.mjs 从只读干净检出动态加载四个完整实际行为模块，六组自有事件夹具验证 stats 合同。单文件类型擦除无法知道跨模块 CharCounts，适配仅移除该类型 import 成员；其余行为函数完整执行。类型导出／Config 是适配；Hangul 适配若被调用立即报错，所有夹具 Korean=false。缺类型导出和跨模块类型 import 的首次绑定失败已纠正，非行为红测。未执行实际删除处理器、完整 TestLogic、浏览器／RAF／真实 IME／Firefox／Korean；旧八场景输入探针保留独立合同。使用 bundled Node 24.19.0 与 --experimental-vm-modules。

会话内有界复核而非独立评审。新标记捕获范围、全事件 flags、普通／混合／延迟恢复边界、源字符分类、FieldReplayPlan／seek／声音／挑战／复制与渲染、实机及大规模混合性能仍需证明。人工行待验收，完整 goal active，不把这个合同等同全部 Monkeytype 功能已重写。
