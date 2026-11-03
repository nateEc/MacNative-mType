# 代码脚手架缩进输入缺口

2026-11-03 在本地扩大回放测试时发现，起点为 3ab415998c2dc7fc318433d2cef8fdbe0f1125fc。本轮未修改代码内容工厂、TypingEngine 或这两项测试，尚未完成根因定位；不能把失败归为无效夹具，也不能宣布产品已修复。

Tests/TypebarTests/TypingEngineTests.swift 的 testTypedCodePracticeChoicesGrowWithoutReplayingTopLevelFragments 与 testScriptCodePracticeChoicesGrowWithoutReplayingDeclarations 逐字符向自定义代码会话输入原创完整脚手架。Rust、Kotlin、TypeScript、R、R 2k、Lua、Luau、PHP 共八个分支各有三处失败：没有完成、typed 不等于完整 prompt、result 为空。观察到输入保留正文而丢失行首两个空格。React 等其他分支通过不表示这些失败已解决。

证据为相邻 typebar-qa-20261102/replay-text-identity-regression.log 和同名 JSON。该轮 379 项中有 24 处失败，输入哈希保持不变。原测试仍原样保留，没有跳过、删掉完成断言或裁掉期望空格。

后续应以这两项方法单独复现，并定位工厂生成、字段拆分及行首空格接纳的边界；同时与固定参考的自定义代码行为对照，再判断原生修正。修正后须覆盖真实多行输入、完成、结果、存档与重复练习。本轮最终 201 项回放回归不覆盖或关闭此缺口。
