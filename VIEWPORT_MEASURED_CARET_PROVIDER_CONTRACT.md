# 页面与已测光标几何的查询边界

2026-11-02，起点 93cba40a123806db6c4395d8a92d74c75159b4c3。前批让视口序列按单目标解析光标，但父视图配置和原生光标 provider 仍可能构造全文索引。本批处理这些重复查询，普通入口默认值及完整回退保留。

## 校准后的反例

measured-caret-provider-contract-red.log/.json：3 项共 4 处失败，native 4.287 秒、driver 27.861 秒，非 Markdown 输入保持。普通视口在自有 201 词页面准备与首键后仍查询完整索引 4 次；完整配置视口也调用该查询。拥有准确主字格矩形和方向的原生光标，在呈现、几何修订及插入点查询中仍分别读取全文 rendering 和 glyph provider 5 次。

先前 measured-caret-provider-red 驱动因新增测试漏传 onInsert 参数而编译失败，不是产品反例。第二轮 behavior-red 的 7 处失败还包括夹具错误：97 词未触发长题准备，以及把协调器保留上次位置误判为当前无锚点时应该清空。已使用 201 词并检查实际插入点无矩形，保留协调器原有契约；只把校准后第三轮的 4 处失败作为本批行为证据。计数注入仍返回原 canonical getter，只统计内容与自有题目完全相同的会话，不把启动占位计入失败。

## 实现边界

普通及完整配置视口在配置光标时声明由已测几何提供锚点，不预求 mainGlyphID，也不装配全文 latestGlyphID 回调。完整渲染、组合输入回退及其他呈现继续装配原 resolver。新增 promptCaretIndex 默认依赖等于原 getter，沿用页面已有渲染依赖注入方式，测试能观察实际产品调用而不替换排版或输入。

原生主光标的 rendering provider 仍先调用：完整字段宿主用它刷新候选排版，不能因为有 fieldMainRect 就跳过。随后若方向也由字段解析器提供，或不需要按 glyph 判断方向，则直接采用该矩形和方向；只有 glyphIsRightToLeft 确实需要 glyph ID 时才继续查询。视口本身不装配全文 rendering provider，因此不产生该项刷新。插入点屏幕坐标遵循同一顺序；marked text 查询仍保留所需完整映射，不删组合输入语义。光标可见性、输入身份、geometryRevision、配速、动画与旧请求所有者校验保持。

这不是用空索引冒充有效光标。新目标与输入的实际锚点仍来自前批的局部状态政策和精确布局；无矩形时插入点查询返回 nil，不借用旧坐标。方向依赖 glyph 的路径保留其 provider，并有单独反例防止过度短路。

## 验证与未完成项

首轮 focused：19 项通过，native 3.393 秒、driver 85.608 秒；但随后的扩大回归发现统一跳过 rendering 刷新会使同一配速序列在新候选重排后保留旧位置（PromptFieldLayoutTests.testFreshCandidateReflowMovesAnUnchangedPaceTargetInTheSamePresentation）。这是实际退化，已恢复刷新顺序，不能把首轮 19 项当作正确实现的充分证明。第三轮红阶段的 renderingReads=0 目标也被此证据否定，不再作为优化要求；其中 glyph／父页完整查询的反例仍成立。最终原生 provider 测试改为必须刷新 6 次且不额外求 glyph，并核对 RTL／默认 LTR 插入点坐标。

另一个扩大失败为 TapePromptDirectionTests 的默认函数签名文本断言；生产 Tape 的显式 RTL 传参未变，但新增参数改变了旧签名。保留原默认方向签名的适配函数，视口用独立的双参数重载声明已测几何，不放宽原断言。修改在首轮原生任务终止后进行。首轮扩大 measured-caret-provider-regression.log/.json：849 项中 2 项失败，native 775.741 秒、driver 808.290 秒，非 Markdown 输入保持；因为 native_exit=1，没有把该轮声明为完整源码合同通过。

measured-caret-provider-corrected-focused.log/.json：32 项零失败，native 4.337 秒、driver 88.621 秒，非 Markdown 输入保持。包含普通及完整配置的实际 ContentView、原生方向、插入点坐标、字体换代、组合输入回退和同一输入控件／尝试身份，并重验两项扩大失败。

measured-caret-provider-final-regression.log/.json/.evidence.log：与首轮相同 849 项范围完整重跑，零失败、零跳过，native 786.929 秒、driver 799.469 秒，非 Markdown 输入保持，146 项必需源码合同全部通过。完整字段、Tape、ASL、插入点、配速及全部完整配置页面宿主纳入此次扩大范围。两项耐力开关保持开启；十万词页面双入口 80.039 秒通过。

单次隐藏 Debug 宿主观察：完整入口就绪 24.959 秒，两键呈现检查 0.744／0.692 秒；分段入口就绪 53.058 秒，两键呈现检查 0.239／0.149 秒。不是实际可见帧或统计性能结论，不改默认入口。驱动与日志保存在持久工作区 typebar-qa-20261102，人工验收结构审计通过（1,477 唯一场景）。

measured-caret-provider-package.log/.json：Debug 严格签名包、资源边界及固定参考原创性扫描通过，44.455 秒，非 Markdown 输入保持。临时包由脚本清理，没有启动可见主程序。推送前 main 仍为 8c52fb13028f82fd8e8718d55cb7ed65463b034e，开放 PR 为 0，Actions 826 次、最近 39118939684 成功；不更改工作流或通知设置。

长输入映射成本、受支持投影以外的全文查询、完整初始页面准备、实体键盘／IME／VoiceOver、可见帧性能和完整功能兼容性继续开放；默认入口不变。没有参考实现或资产复用，没有关闭门禁或邮件通知。
