# 原生输入接收器的销毁边界

起点 17f188442aecf4b265970bb1e1701b5d46f34640。固定 Monkeytype 参考仍为 91bd24bb8513785c7364cbea29296ff7adafac41；本项修正 AppKit 平台适配层的资源生命周期，不导入参考代码或资产，不改输入评分、出词、组合自动结束或配置分类。

固定参考的 `input/listeners/composition.ts` 在重启／结果计算期间拒绝组合开始、更新和结束；`test/test-logic.ts` 重置组合标记与内容。这里只核对该状态边界，原生接收器销毁是独立的平台责任，不能由这些浏览器源码推断全部系统 IME 行为。

## 反例与修正

SwiftUI 的 `NativeTypingInput.dismantleNSView` 已调用 `retirePageCallbacks`，但旧实现只解除页面闭包与窗口监听。AppKit 若继续持有接收器，其公开 `NSTextInputClient` 查询仍返回旧候选、UTF-16 选区和候选子串；迟到配置还能重新开启接纳。三个先行回归共出现十处失败，产品原因是销毁没有完成输入状态的收尾。

现在销毁保持幂等：先标记退休并解除页面闭包，再关闭文本接纳。沿用现有关闭接纳路径，先清除本地 marked range 与选区，再要求该接收器的输入上下文丢弃转换会话。清理不会把空候选回写已经离开的 SwiftUI 页面；转换会话丢弃期间的同步文本回调也不能提交或重新建立候选。`insertText` 和 `setMarkedText` 均拒绝已退休接收器，即使后来的配置再次打开布尔开关。

Apple 的 [discardMarkedText 文档](https://developer.apple.com/documentation/appkit/nstextinputcontext/discardmarkedtext())要求客户端在发送消息时清除 marked range；本项保留这个顺序。不直接调用系统管理的 [activate](https://developer.apple.com/documentation/appkit/nstextinputcontext/activate())，不改变系统输入源或全局键盘设置。

`TypingInputRetirementTests` 覆盖含 emoji 的候选查询清理、丢弃转换时同步确认／重组的拒绝、重复销毁和迟到配置不能重新开启。丢弃重入使用可控 `NSTextInputContext` 子类模拟不稳定系统边界，其余查询和接纳使用实际 `TypingInputView`。这不是物理输入法验收。

## 可见窗口调查的边界

本次修复前，一个隔离内存库应用内，CUA 的 Option+E 首次产生 marked acute，接着 E 提交 `é`，完成自有 `é a` 提示时正确率 100%、错误零；观察停顿很长，速度没有性能含义。结果页／命令切换后，同样操作未显示候选，普通 E 被计错。普通文本编辑框也未显示 Option+E／Option+U 组合态，但 Option+A 能输入 `å`；确认进程退出后重开同一隔离包，首次 Option+E 同样未建立候选。

因此不能把现象归因于 below 模式，也不能把本项销毁修复宣称为该死键现象的根因或解决方案。系统死键状态、事件工具、焦点及输入映射的实际边界仍需区分。没有修改系统键盘设置、没有复制粘贴伪装物理按键、没有把直接客户端调用冒充系统 IME。测试期间最多一个可见隔离实例，结束后已确认 Typebar 进程为零。

## 验证

- `input-retirement-red`：三个测试、十处断言失败；driver 28.838532 秒，非 Markdown 输入哈希不变。
- `input-retirement-focused`：47 项定向回归零失败／跳过，原生 9.154 秒、driver 50.064425 秒；运行期间非 Markdown 输入哈希不变。
- 固定参考原创性扫描通过；人工验收表审计通过，1484 个唯一场景。本次未把新增人工场景标为已验收。
- `input-retirement-regression`：645 项扩大回归零失败／跳过，原生 1456.588 秒、driver 1471.180596 秒；包括普通／Tape／ASL／Choo 组合、42 项生产组合宿主、页面生命周期与输入边界。152 项必需固定源码测试的证据检查通过，运行期间非 Markdown 输入哈希不变。
- `input-retirement-package`：47.659742 秒退出零，未启动应用的 macOS 包、签名、资源边界及固定参考原创性检查通过；运行期间非 Markdown 输入哈希不变，且与扩大回归的输入一致。

冻结的 `NativeTypingInput.swift` SHA-256 为 c9edbb5dbe2f70f8447cb0ed5d313a810a06a82cf6f24b93c6e427fafec8f882。以上是本批局部／扩大验证与打包证据，不是新一次完整 CI 门禁，也不升级 `compositionDisplay` 的部分状态。

四项配置部分分类、全部物理 IME／VoiceOver／呈现组合验收及完整原生重写 goal 均保持开放。

后续事件层排查见 [死键调查](NATIVE_INPUT_EVENT_INVESTIGATION.md)：有效死键事件到达时应用、窗口、第一响应者及当前输入上下文归属均正确，标准编辑框也出现同样的普通 `e` 结果。该证据排除焦点缺失这一假设，尚不归因于某个系统／工具内部机制，更不把本项销毁修复当作死键问题的解决方案。
