# Choo 接入共享属性文本

固定只读参考 `91bd24bb8513785c7364cbea29296ff7adafac41`；独立 Swift／AppKit 实现，不复制网页代码、CSS、字体或资源。Swift 6.2.4／macOS SDK 26.2，最低 macOS 14。本增量推进完整原生重写，不替代 [字段桥接](COMPOSITION_FIELD_CONTRACT.md) 或 [全局组合投影](COMPOSITION_PROJECTION_CONTRACT.md) 的剩余工作。

## 实际生产路径与边界

此前 Choo 从原始 glyph 自行绘制，绕过普通 Text／Tape／ASL 使用的最终 PromptRendering。现在 ContentView → ChooPracticePrompt → ChooLayerPrompt 的尺寸及配置都传递同一 rendering 和 canonical IDs；原生文字层保留候选、颜色／透明度、背景、下划线、错误提示和控制字符，不再用旧 palette 覆盖最终属性。旧 nil-rendering API 仅保留既有组件调用，生产桥接要求非可选 rendering。

共用 `glyphTexts()` 一次构造属性切片；无 ID 的退休结构换行是边界，不粘到前一字形上。Choo 只物化保留 ID，并单独布局匿名结构行；不将缺失 ID 恢复为可见框。目标 Return 占正宽框并拥有换行，额外 Return 不创建结构行；Zen 隐藏控制和空占位保留几何。尺寸、实际绘制和 canonical caret 使用同一候选宽度，字号更改重新布局；主／pace 控制器及输入引擎不改。

完整参考 `test-ui.ts` 的 updateWordLetters／createHintsHtml、`styles/test.scss` hints 及 `static/funbox/choo_choo.css` 已直接核对：提示是独立框且有自己的动画，不是正文旋转框的后代。原生提示为同级文字层，绕自身中心旋转，共用既有两秒时基；取消／重建清除旧提示，减少动效同时停止两层。小字号提示按基线差定位，不占正文横向 advance，末行高度包含提示。

本机 SDK 的 CATextLayer.h 明确属性字符串使用自身字体／颜色，不能靠 layer.foregroundColor 替代。因此将共享 SwiftUI 颜色／下划线显式转成 AppKit 属性，复用现有字体准备路径；真实 CATextLayer 测试验证输出，不依靠 API 记忆。

**未将新组合模型接入全局生产投影。** Choo 现在消费既有 shared rendering，仍继承该层将整段候选塞入一个当前字形、后续目标未消耗的缺口；候选溢出新身份、跨字段部分字形拆片、marked 下划线／正确色、末尾 after 光标和全局词归属仍待实现。源混合 UTF-16／scalar 与原生 grapheme 差异、复杂 RTL、提示合并／精确网页样式、逐状态动画等价、任意队列及设备 IME 仍开放。不把本轮自有 rendering 的组件测试称为真实 IME 或完整 ContentView 截图。94 配置仍 89 映射／4 部分／1 不适用，goal active。

## 可复核证据

十一项新 ChooPromptRenderingTests 包含生产接线结构检查和真实 layer／caret 行为：重排 extras 与 Unicode 候选／提示、最终颜色／隐藏／下划线／背景、目标及额外 Return、Zen 控制／占位、匿名退休行／缺失 ID、候选宽度／字号／caret、取消／旧提示、20,000 退休前缀、3,000 字长提示末尾及有界可见层。后者不是大规模 Choo UI 性能验收。

红测均保留 `/tmp/typebar-choo-shared-` 前缀：

- `wiring-red.log` 一项两处预期失败，仅结构证据，不冒称运行时回归。
- `structural-red.log` 两项三处预期失败（0.600 秒），其中共享切片实际返回 `A\n` 而非 `A`，另两处仍为接线检查。
- `first.log` 因新桥接误写字体 helper 名称而编译失败；改用现有 PromptCaretLayout，不算行为红测或通过。
- `focused.log` 58 项零失败、两项缺 reference 环境跳过；`regression.log` 97 项零失败、五项同因跳过，均不计完整验收。
- `hint-baseline-red.log` 一项两处预期失败（0.761 秒）：基线差实际 -2.07656 而非 12，末行高度也未包含提示。修正后 `verified-regression.log` 97 项零失败零跳过（3.889 秒）。
- `hint-ownership-red.log` 一项一处预期失败（0.718 秒）：提示仍是正文子层。改成同级、自身动画后 `final-regression.log` 97 项零失败零跳过（3.996 秒），十一新项共 0.970 秒。提供 TYPEBAR_REFERENCE_ROOT、内存 QA 与独立截图目录，没有关闭或削弱测试。

三次有界决策复核均在本会话，非独立审计；反例为结构行粘连、基线／裁切及提示旋转归属，已用红测和实际原生输出确认修正。四张新组件图保留于 `/tmp/typebar-choo-shared-final-focused-images.3QKZQq` 并逐张查看：候选／基线提示、隐藏属性、控制归属、匿名退休行。初次退休图因自有夹具未设置前景色呈黑色，给夹具明确橙色后重验；未据此修改生产默认色。截图不采样运行中的动画，不能替代实机动画／VoiceOver 验收。本轮零 Typebar 主程序启动。

## 冻结完整门禁

十文件冻结清单 `/tmp/typebar-choo-shared-final-frozen.sha256` 在启动前、中途及终态逐项一致。唯一门禁 session 50596 终态退出 0，主日志 `/tmp/typebar-choo-shared-final-readiness.log`。原生 3,996 项零失败零跳过（871.638 秒，All tests 墙钟 872.064 秒）；服务 501 项零失败零跳过（11.177 秒，墙钟 11.231 秒）。十一新项 0.931 秒，十万词耐久 152.337 秒，十六项磁盘迁移 5.041 秒通过；这些耗时不作为优化或完整 Choo UI 性能结论。

固定源码探针、元数据再生成无漂移、53 表面、1,134 唯一人工场景结构、94 配置 89／4／1 分区、未启动应用包的构建／签名／资源与原创性检查通过。结构检查不是 1,134 场景人工执行。74 日志保留于 `/tmp/typebar-choo-shared-final-logs.YH2bla`，214 组件图于 `/tmp/typebar-choo-shared-final-images.I8JvSF`（原 210 加本轮四张）；首次聚焦四图与最终门禁四图均逐张查看。原 CoreData 故障夹具及系统诊断保留，XCTest 后独立 Swift Testing 零项摘要不替代上述数量。

终态参考 pin 未变且干净，无主程序／测试／编译器残留，本轮零 Typebar 主程序启动。门禁结束后只本合同及 README／规范／盘点补充验证结果，五个代码／测试文件及人工表六个冻结输入保持不变。提交前同会话风险检查核对生产桥接、属性转换、提示移除、动画时基及缺失 ID，没有发现需再改代码的问题；非独立审计。全局候选投影与实际 IME 继续开放，完整 goal active。
