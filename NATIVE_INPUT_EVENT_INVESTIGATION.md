# 死键事件与原生组合回调调查

基于 00d9831523c407bab14e98fdd3167811e9a67019；原版固定参考仍为 91bd24bb8513785c7364cbea29296ff7adafac41。此为隔离 QA 调查，不改变练习输入或评分语义，也不升级 `compositionDisplay` 的部分分类。

## 可重复观测

在单个独立标识、内存库调试包内，以 CUA 操作自有 `é a` 文本。包不注册 `typebar:` URL，未更改系统键盘设置或原应用数据。两轮包串行构建与运行，各轮结束后确认 Typebar 进程为零；没有同时打开多个实例。

第二轮接收器日志显示 Option+E：物理编号 14，`characters` UTF-16 长度 0，忽略修饰键后的长度 1，Option 为真。该事件时 `applicationActive=true`、`windowKey=true`、`firstResponder=true`、`contextOwner=1`：事件到达活动应用的 key window，接收器是第一响应者，当前文本输入上下文的客户端就是该接收器。没有出现 `setMarkedText` 回调；之后普通 E 的长度为 1，触发 `insertText`，练习计为错误。

同一窗口标准自定义文本编辑框中，全选自有文本，再输入 Option+E、E，辅助功能值及截图均显示普通 `e`。两次 `pressKey` 在同一个工具调用中连续执行，中间没有读取辅助功能树，不能只归因于人工检查停顿。因此失败现象并不限于练习接收器；不能把它归因为 below、页面销毁修复或焦点缺失，也不能据此断言平台或事件工具的具体内部原因。以前首次成功完成 `é a` 的记录仍保留，不因当前反例抹掉。

[Apple 的 characters 文档](https://developer.apple.com/documentation/appkit/nsevent/characters)说明死键 Option+E 的字符字符串为空；[文本编辑说明](https://developer.apple.com/library/archive/documentation/TextFonts/Conceptual/CocoaTextArchitecture/TextEditing/TextEditing.html)说明 key window 的第一响应者会激活其文本输入上下文。本次事件形状及上下文符合这些公开条件，仍不足以证明合成事件路径等价于物理输入。下一步需要另一条可验证的系统输入证据，而非直接调用 `setMarkedText` 或注入已经组合好的 `é` 冒充验收。

## 最小诊断边界

`NativeTextInputDiagnostics` 只在 DEBUG 调用点启用；必须同时有隔离内存库包标记和显式环境开关 `TYPEBAR_QA_NATIVE_INPUT_DIAGNOSTICS=1`。每个进程最多 96 条记录，字段仅有固定阶段、按键编号、字符长度、修饰键、接纳／退休／候选状态和焦点／上下文归属。没有文本、账户、词库值或结果内容；不调用 `inputContext.activate`，也不为了观测创建新上下文。通过独立 subsystem 的统一日志读取属于该 QA 进程的记录。

QA 包的 [LSEnvironment](https://developer.apple.com/documentation/bundleresources/information-property-list/lsenvironment)只在该隔离包内设置开关，签名在修改后重新验证；未改变仓库发布包的 Info.plist。加入诊断而未先写产品红测的原因是本轮只增加用于区分假设的观察，不修改产品行为；测试验证显式启用、有限预算及不包含文本的记录格式。

## 证据

- `native-input-diagnostics-focused`：31 项零失败／跳过，driver 104.611345 秒。
- 增补焦点元数据后的 `native-input-diagnostics-context-focused`：31 项零失败／跳过，driver 41.591175 秒。
- 两个隔离包的构建／签名均成功，构建期间源码与测试输入哈希不变。原始限定进程日志在工作区外的 `typebar-qa-20261102/composition-native-ui-02` 与 `composition-native-ui-03` 保存。
- `native-input-diagnostics-package`：53.109358 秒退出零，签名、资源边界和固定参考原创性扫描通过。该运行继承 QA 环境的 `TYPEBAR_BUILD_CONFIGURATION=debug`，日志明确为 debugging；不能把它当作 Release 验证。查询 Release 路径后未找到二进制的初次探针失败记录不算发布版排除证据。
- `native-input-diagnostics-release-package` 显式设置 `TYPEBAR_BUILD_CONFIGURATION=release`，日志为 production，构建 791.46 秒、含包检查 driver 840.300596 秒退出零。签名、资源边界与固定参考原创性检查通过，非 Markdown 输入哈希保持不变。
- 实际 Release 与隔离调试二进制对照通过：新增诊断 subsystem 和环境开关字符串均在调试二进制存在、Release 缺席。Release SHA-256 为 47455340c3362ac4efafe68db4752872c1f1c39353bdae6d514714cfc55bfbfe，调试包为 3c1bff4e3a331bbc72d99348f6e8f97846122ae1a47d44d17ee2ff5210c9eb73；该诊断版本（新增后续越南语测试之前）的非 Markdown 输入与 31 项定向、隔离包及 Release 检查完全一致。该字节探针配合 DEBUG 调用点排除证明本次诊断不在发布路径，并非全部发布功能验收。
- 本轮没有用先前 645 项回归宣称新诊断版本跑过相同套件。

诊断及本文与越南语字面词库合并为一批交付，避免为诊断单独推送。该批新 Release 包与诊断排除检查也通过，详见 [越南语合同](VIETNAMESE_CORPUS_CONTRACT.md)；上述较早二进制哈希保留其对应历史版本。物理键盘、CJK IME、VoiceOver 和完整功能等价仍未证明，goal 保持 active。

2026-11-03 以 794a2501 构建单个 Typebar-QA-InputAudit 隔离实例再次对照，仍未在自动 Option+E／E 路径看到候选，后续 e 计错；普通编辑器自动输入 é 也未成功。没有收到物理键盘验证结果，实例已退出。调查期间另发现并修正的 Shift 快照与接纳边界见 [独立合同](NATIVE_SHIFT_ADMISSION_CONTRACT.md)，它们有单独红测，不解释本节死键现象，也没有用新产品版本重复启动可见应用。
