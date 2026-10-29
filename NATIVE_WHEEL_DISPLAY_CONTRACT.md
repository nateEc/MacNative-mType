# 原生滚轮集成测试的显示器前提

`WHEEL-DISPLAY-41`，起点 `b9b112d8938edc739702cde085c14d07016dd548`。本批只调整 XCTest 的环境准备，不修改生产滚动代码，不将一次成功重跑算作产品缺陷修复。

## 新证据与被排除的归因

历史完整客户端基线及独立重现中，原滚轮用例的 overlay／legacy 下、上四处等待失败，页面原点保持 153。临时探针曾补 CG 窗口字段、坐标、Cocoa windowNumber，并对照显示窗口，均仍失败，记录保留在 CLIENT_BASELINE_20261029.md。

这轮 `/tmp/typebar-wheel-trajectory-20261029.log` 在相同生产代码下观察到两种样式均为 153 → 233 → 153。随后只撤去公开 CG 窗口目标字段，`/tmp/typebar-wheel-trajectory-unowned-20261029.log` 仍通过，因此不能把成功归因于这两个字段。移除全部轨迹观察器及辅助构造、恢复整个测试文件至起点后，`/tmp/typebar-wheel-original-clean-20261029.log` 的原用例也通过，3.049 秒。窗口字段与诊断观察器都没有构成已经证实的修复。

系统电源事件显示，历史连续失败的测试窗口对应显示器关闭；显示器后来唤醒后，未修改的原用例通过。CoreGraphics 的公开 CGDisplayConfiguration.h 将 CGDisplayIsAsleep 返回 true 的显示器明确描述为不可绘制。最小 NSView 文档可以同步滚动，hosting 文档则出现派发后 RunLoop 中才滚动的观察，与显示管线前提一致。电源事件是相关性证据；历史失败时没有同步捕获 CG 状态，不能据此声称所有旧失败已经被受控实验证明。

## 显式准备，保留行为检查

原滚轮集成用例在创建隐藏 Fixture 前，通过公开 IOPMAssertionCreateWithName 建立 PreventUserIdleDisplaySleep 断言；只有 CGMainDisplayID 对应显示器已休眠时才调用 IOPMAssertionDeclareUserActivity。使用原有 15 秒有界等待确认显示器可绘制。API 返回错误或显示器不能就绪仍使测试失败，没有跳过、扩大超时或手动代替滚轮移动 clip。

IOPMLib.h 说明，PreventUserIdleDisplaySleep 本身不会点亮已关闭的显示器，所以不能只创建该断言就假定已经准备完毕。两个 assertion ID 均在 defer 中释放；不修改用户的全局电源设置或生产应用生命周期。该用例可能短暂唤醒显示器，但始终使用原来的隐藏窗口，不启动 Typebar 主程序。

原事件、下／上方向、两种 scroller 样式、内层 clip 不移动、输入 first responder 保留、NoQuit 锁定、仅一次题目生成、完整辅助文本和窗口不可见断言均保留。生产 NSScrollView 的转发没有重建事件、改写滚动幅度、绕过 AppKit 或引入运行时替换。原事件夹具依然只清除环境修饰键。

本机主源为 MacOSX26.2.sdk 的 CoreGraphics/CGDisplayConfiguration.h 与 IOKit/pwr_mgt/IOPMLib.h；测试部署目标仍为 macOS 14。

## 验证状态

`/tmp/typebar-wheel-display-prerequisite-20261029.log`：两项定向测试通过，XCTest 3.121 秒、驱动 27.684 秒，冻结输入不变。实际日志为 wasAsleep=false、drawable=true，因此本次尚不能宣称从休眠唤醒分支已实际覆盖。

`/tmp/typebar-client-drawable-baseline-20261029-driver.py` 已终态退出 1：6,751 项、一处失败、零运行时跳过，XCTest 3,404.024 秒、测试阶段 3,408.543 秒、驱动 3,415.130 秒，冻结输入保持不变。此前三个显式可见窗口排除、两个耐久开关、六个历史模型写入器及全部来源依赖均保留。原滚轮用例在该完整范围通过，1.776 秒，日志仍为 wasAsleep=false、drawable=true，不能声称休眠唤醒分支已经实际覆盖。

唯一失败为 WebsiteConfigStartupHostTests 的键帽整行 OCR 漏读可见 E；自有原始截图与裁片已保留，并在旧识别器上独立复现，见 KEYBOARD_LEGEND_OCR_CONTRACT.md。全部 145 项必需来源方法各有一次 passed 记录，但因全局失败，驱动没有运行完整日志的来源证据校验，不能称完整门禁通过。

修正 OCR 读取方式后，保存的真实裁片、擦除 E 的反例、实际 QWERTY／Dvorak 发布流程及原滚轮两项共四个测试通过，XCTest 9.757 秒、驱动 36.385 秒。随后扩大检查 250 项通过、零失败／零运行时跳过，XCTest 554.971 秒、驱动 567.252 秒，145 项必需来源证据通过、输入哈希不变。该结果不是再次运行完整范围，历史红基线保留，休眠唤醒分支与完整重写目标仍未完成。
