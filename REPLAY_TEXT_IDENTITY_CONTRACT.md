# 回放呈现保留原始字符编码

起点 3ab415998c2dc7fc318433d2cef8fdbe0f1125fc，固定参考 91bd24bb8513785c7364cbea29296ff7adafac41。参考 frontend/src/ts/test/replay-ui.ts 使用严格字符串比较判断 typed 与 target，并将原始字符写入回放元素。本项只据此界定原始字符串边界，不复制其代码、词值或资产，也不宣称浏览器与 AppKit 的字形布局完全一致。

## 可复现问题与修正

Swift 的规范等价会把 é 与 e + U+0301、预组韩文与分解 Jamo、不同顺序的规范等价组合标记判为相等。原来的整数组去重和增量前缀判断因此可能跳过真实文本变化，令 NSTextStorage 保留旧 UTF-16 拼写，后续样式／索引仍使用旧偏移。

ReplayGlyphIdentity 在原有 glyph 相等条件上，只额外核对可见 character 的原始标量；整数组去重和增量前缀均使用它。目标选择器同时按 UTF-16 比较正文与本地 glyph 身份，重建实际文本及索引。所有规则局限于回放呈现，不改变全局 TypingPromptGlyph.Equatable、输入评分、事件、存档或持久模型。

未渲染 typedCharacter 的规范等价别名继续遵循既有相等规则，不能仅因此重绘或滚动；完全相同的输入仍是 no-op。新测试对这个边界也先证实失败，再缩小修正范围。

## 验证证据

QA 记录位于相邻 typebar-qa-20261102 目录。replay-text-identity-red 的六项测试产生 41 处预期失败，零意外异常；原生 1.564 秒，driver 27.745333 秒。初版修正的 59 项相关回归通过。随后 replay-text-metadata-red 单项先行回归发现未渲染元数据造成多余刷新，最终实现保留其原有 no-op 行为。

最终 replay-text-identity-regression-verified：201 项零失败、零跳过，原生 7.406 秒，driver 48.110379 秒。覆盖原始 UTF-16 两个方向的替换、变化前缀后的错误样式位置、追加 emoji、回拨及清空；隐藏 NSHostingView／NSWindow 还验证 SwiftUI 更新到同一个原生接收器。窗口从未显示，结束时释放。已有回放统计、生命周期、声音、显示间隙、生成段及禅模式回归同时通过。

replay-text-identity-debug-package：Debug 包构建、严格签名、资源边界和固定参考原创性检查通过，driver 44.595158 秒；未启动包。其非 Markdown 输入与最终 201 项回归相同且全程不变。本轮没有新 Release、完整 CI 门禁或完整 152 项源码组结果，不借用旧结果证明本版。

## 保留的失败与验收边界

早先 replay-text-identity-regression 使用 Replay|InputTextIdentity，选到方法名含 WithoutReplaying 的代码脚手架测试：379 项中有 24 处失败、零意外异常，原生 73.984 秒，driver 78.374250 秒。两项失败方法及八个语言分支详见 CODE_SCAFFOLD_INPUT_GAP.md。最终回放类过滤只界定本次修正的验证范围，不能使此前失败消失，也不能据此声称全套测试通过。

物理键盘、死键、输入法、VoiceOver、实际可见窗口与长时滚动仍待验收。用户暂不方便物理键盘检查，本轮零可见应用启动。完整重写目标继续保留未实现与未验收项。
