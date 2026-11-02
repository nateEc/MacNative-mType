# 单目标视口光标解析

2026-11-02，起点 80cc152f2cf759f4c6242dee99228b18ff8e2323。延续 VIEWPORT_INPUT_GEOMETRY_CONTRACT.md。该批保留几何后，每份新序列仍通过 promptCaretGlyphIndex 构造全文 acceptedPromptGlyphs。本批只消除已准入视口的此项全文目标扫描；普通入口默认值及不支持投影的完整规则保持不变。

## 先行成本反例

PromptViewportCaretResolutionTests.testRepeatedHundredThousandWordInputSnapshotsAvoidWholeTargetCaretWork：自有 oak 目标 100,001 词、400,003 字符，仅接受一个 o；在目录与字体准备及一次构造预热后，连续建立 16 份新序列。旧实现耗时 1.739575 秒，超过宽松的 1 秒回归上限，测试失败。caret-resolution-red.log/.json：一项失败，driver 27.959 秒，非 Markdown 输入保持不变。这个构造专项不包括初始词库生成、页面布局、真实窗口帧率或全部输入处理，不能混用指标。

## 语义与边界

引擎只暴露当前输入目标位置，该位置本身不是可见光标。目录核对尝试／目标，按源字段范围和字面空格／LF 的有序下标分别二分定位字段与词序号，然后交给现有 promptViewportTargetGlyphs 政策，仅解析一个真实目标字格。只有该格仍为 current 才产生锚点；隐藏或目标末端应得到已解析但无锚点的结果，不能把它误当成失败而重建全文。

该局部政策仍核对完整输入映射、当前规则、强制错误、盲模式、隐藏范围以及不支持状态；不以 nextTargetIndex 直接替代可见光标。目录拒绝时，序列保留原 promptCaretGlyphIndex 回退，包括额外输入、停止输入、完成、退休及未支持的投影。每份序列仍只求取一次自己的锚点，旧序列与新输入相互隔离。没有扫描完整源字段或缓存跨输入的光标索引。

## 验证与开放项

caret-resolution-focused.log/.json：首轮 15 项零失败，native 1.764 秒、driver 155.168 秒，非 Markdown 输入保持；16 次快照构造 0.000230 秒。随后补强跨字段内部 LF 的推进及隐藏当前目标的明确断言，最终五项新光标测试在扩大回归中全部通过。语义逐项对照原有完整光标，覆盖正确／误键／删除／提交、盲模式及切换、memory／Simon Says／readAhead／focus、提供者内部换行／空字段和不支持投影；隐藏时返回已解析但无锚点。

caret-resolution-regression.log/.json/.evidence.log：742 项零失败、零跳过，native 766.558 秒、driver 798.664 秒，非 Markdown 输入保持，146 项必需源码合同通过。两项耐力开关均开启，保留几何、阅读位置、辅助功能、选择及十万词双入口宿主一并通过。16 次快照构造复测 0.000213 秒；1 秒上限仅为此显式成本回归，不能据此推导页面帧率。

十万词完整页面双入口用例 80.955 秒通过。单次 Debug 宿主数据：完整入口就绪 25.124 秒、两键呈现检查 0.762／0.705 秒；分段入口就绪 53.449 秒、两键呈现检查 0.451／0.262 秒。父视图 TypebarApp.currentPromptGlyphIndex 仍调用完整 getter，其他投影也保留完整规则；总体输入响应并未全部转为局部计算。普通默认入口继续不变，未作统计性能或真实窗口延迟声明。

驱动和证据位于持久工作区 typebar-qa-20261102。人工验收结构审计通过，1,476 唯一场景。caret-resolution-package.log/.json：Debug 严格签名包、资源边界及固定参考原创性扫描通过，45.862 秒，非 Markdown 输入保持；脚本按约定清理临时包，没有启动可见主程序。推送前 main 为 8c52fb13028f82fd8e8718d55cb7ed65463b034e、开放 PR 为 0、Actions 826 次，最近 39118939684 成功；没有更改工作流或通知设置。

即使目标解析为常量规模，局部政策仍随已接受输入量扫描映射；后者、大量纠错／提交、未支持投影、实体键盘／IME／VoiceOver 及真实窗口帧延迟仍开放。默认入口不变，完整重写目标保持 active；不更改 CI 触发或邮件通知。
