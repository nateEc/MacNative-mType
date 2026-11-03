# 退休输入接收器的焦点交接

起点 fd34cae4bd31919086adb1b88f653b32f5ba63a0，固定 Monkeytype 参考仍为 91bd24bb8513785c7364cbea29296ff7adafac41。此项完成原生平台接收器的销毁边界，不引入参考实现或资产，不修改输入评分、布局、配置或系统输入源。

## 行为反例

既有实现令 acceptsFirstResponder 在退休后返回 false，并拒绝文字、原始按键和编辑命令。但这不足以阻止 NSWindow.makeFirstResponder 直接交接：实际隐藏窗口仍能接纳退休接收器。迟到配置恢复闭包后，becomeFirstResponder、resignFirstResponder 及刷新窗口焦点也能再次通知旧页面。另一个反例是 onFocusChanged 同步销毁页面，旧方法仍返回获取成功。

四项测试中一项为既有回归，新增三项分别验证直接获取／释放、实际隐藏窗口的附着／刷新／通知与获取焦点期间同步销毁。窗口显式解除内容并关闭，释放焦点本身必须仍然成功。

初轮把 makeFirstResponder 的 true 返回误当成接收器已获取焦点。首次修正后 98 项中仍有该断言一处失败；[Apple 文档](https://developer.apple.com/documentation/appkit/nswindow/makefirstresponder(_:))说明目标拒绝时窗口可自行接管，方法仍返回 true。测试改为检查 window.firstResponder 的实际身份。重新还原到起点的原生输入源码并校验逐字节一致，再用修正后的夹具取最终红测；原先含错误返回值假设的轮次不作为最终反例证据。

最终有效 `input-retired-focus-red-final`：四项测试、六处预期断言失败、零意外异常，原生 1.159 秒、driver 40.540409 秒，非 Markdown 输入哈希不变。隐藏窗口中真实 firstResponder 身份仍为旧接收器，故直接获取问题不是由错误的返回值假设推断。

## 修正

becomeFirstResponder 在退休时直接拒绝，并在页面回调后重新检查退休状态，覆盖同步销毁。resignFirstResponder 仍允许 AppKit 释放焦点并清理本地 Shift／待判错状态，退休时不再向旧页面发布修饰键或焦点。窗口焦点报告统一拒绝退休接收器，保持活动接收器原有的去重和同步刷新防重入。

这些是 AppKit 生命周期边界，不改变浏览器端功能判断，也不是死键现象的根因证明。实际候选窗口、物理键盘、VoiceOver 和完整配置呈现验收继续开放。

## 验证范围

测试只创建并关闭隐藏窗口；本批没有启动 Typebar 可见应用。

- `input-retired-focus-focused-final`：98 项相关回归零失败／跳过，原生 5.699 秒、driver 45.108070 秒，非 Markdown 输入哈希不变。包含窗口焦点交付／迁移、视觉焦点与隐藏宿主、原生接收器退休、组合快捷键、页面生命周期、诊断和 Opposite Shift；正常去重、同步刷新与活动窗口行为保持通过。
- 人工验收表审计通过，1502 个唯一场景；新增场景仍待验收。

- `input-retired-focus-debug-package-final`：显式 Debug 包检查 driver 43.903169 秒退出零，严格签名、资源边界及固定参考原创性扫描通过。没有启动包；非 Markdown 输入与最终 98 项回归完全一致且全程不变。首轮失败夹具版本虽也完成包检查，但不作为最终版本验证证据。

此局部修正采用 Debug 原生回归与包验证，不重用上一版 Release 结果来证明新版本已运行 Release 或完整 CI；未执行完整 152 项必需源码组。冻结 NativeTypingInput.swift SHA-256 为 `3d7b61a4a736b0141d2123b4eebcfbe1f2ff52fe3767abdda330bc48e786b83e`。完整重写目标及既有四项部分配置保持开放。
