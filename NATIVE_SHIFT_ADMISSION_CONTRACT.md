# 原生 Shift 状态与输入接纳边界

起点 794a2501f51efcf9563579eb6d82306cdc344013。本项独立修正 AppKit 事件适配，不导入 Monkeytype 代码或资产，不改变 Opposite Shift 左右手判断规则或历史成绩。

## 可复现的反例

原接收器把每个左右 Shift flagsChanged 事件直接翻转。首个事件若是释放、设备重复报告按下、焦点切换丢失部分事件，内部状态会与事件中的设备状态相反。普通字符即使携带明确的左右 Shift 位，也无法纠正它。回归用实际 TypingInputView 和 TypingSession 验证错误手被拒绝、正确手与无 Shift 输入能完成自有单字目标。

另两个边界独立存在：关闭 acceptsTextInput 仅阻止 insertText／setMarkedText，内置布局模拟、字面换行和编辑命令仍能调用页面；销毁接收器后，迟到配置可恢复原始按键、修饰键、编辑命令和 unmark 回调。后者补充 [既有销毁合同](INPUT_CLIENT_RETIREMENT_CONTRACT.md)，不把迟到配置视作有效的新页面。

13 项有效先行回归出现 32 处断言失败、零意外异常；driver 25.456207 秒，非 Markdown 输入哈希不变。更早一次红测的两处意外异常来自对未完成结果强制解包，夹具已改为可选结果断言；该轮不作为最终红测证据。

## 实现边界

采用已安装 macOS SDK IOKit/hidsystem/IOLLEvent.h 的 NX_DEVICELSHIFTKEYMASK 与 NX_DEVICERSHIFTKEYMASK。存在设备位时同步两侧；聚合 Shift 已释放时清除两侧。只有不含设备位的合成 flagsChanged 保留逐侧翻转回退；普通字符不会猜测未知的按键侧。每次字符事件也同步快照，修复漏掉释放的状态。

保留重开、命令面板及既有显式快捷键。普通文本、Tab、换行、箭头输入和删除共用文本接纳限制。已退休接收器直接拒绝原始按下／释放、修饰键及编辑命令；unmark 仍清理本地候选，但不回写离场页面。未加入系统输入源切换或主动激活输入上下文。

## 设备与调查限制

本轮只启动并退出一个独立内存库 Typebar-QA-InputAudit 应用。修复前以自有目标 é a 观察 Option+E／E：有效 Option 事件到达当前接收器，但未建立候选，随后 e 计错；普通编辑框的自动输入也未得到 é。目标通过粘贴建立，这不是物理输入证据。诊断仅记录事件计数、按键码和状态，不记录文本。

没有收到物理键盘对照结果。以上 Shift／接纳修正不解释或解决该死键现象，也不升级中文、日文、韩文输入法、实体左右 Shift 或 VoiceOver 的人工验收状态。可见应用已退出；后续自动测试和打包不启动可见应用。

## 验证

- `native-shift-admission-focused`：68 项定向回归零失败／跳过，原生 3.946 秒、driver 151.126209 秒；编译及测试期间非 Markdown 输入哈希不变。包含新反例、组合 Return／Escape、候选选区／子串、诊断边界、布局模拟、箭头与固定源码 Opposite Shift 对照。
- 人工验收表审计通过，1501 个唯一场景。新增两项仍待实体操作，固定参考工作树保持干净。
- `native-shift-admission-regression`：630 项扩大回归零失败／跳过，原生 463.880 秒、driver 478.522435 秒；152 项必需固定源码测试的证据检查通过，非 Markdown 输入哈希与定向回归一致且全程不变。包含输入生命周期、活动规则、组合查询／完成、导航、普通／Tape／ASL／Choo 的代表性生产宿主。没有重跑此前的全部 42 项多语言生产宿主排版组合；本项没有修改排版、词库或绘制。

- `native-shift-admission-release-package`：显式 Release 编译 590.17 秒，含检查 driver 633.190839 秒退出零；未启动应用。签名、包资源边界及固定参考原创性扫描通过，非 Markdown 输入与定向／扩大回归一致且不变。
- 当前 Debug／Release 实际二进制对照：诊断 subsystem 和启用开关均在 Debug 存在、Release 缺席。Debug 是本轮原生测试编译的当前二进制，不借用修复前的可见 QA 包作当前源码证明。Release SHA-256 为 `6a42c9dcb0f0d0cbc1e7bba7d497aaf0353f33855fd266f5fb73236bef19cb67`，Debug 为 `dbcc9b3cb01e751aaab92a8de5415985b81d58f8a4ccbaf0e6eafecdba41276f`。

冻结的 NativeTypingInput.swift SHA-256 为 `0bf51610254399c6e79e4c399a4ce3e800d8765f4d7bad81445fddc199ffb54a`。本批是局部与扩大回归及显式 Release 验证，不是新的完整 CI 门禁。四项配置部分分类及完整重写目标保持开放。
