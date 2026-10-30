# 首键与重开的练习阶段提示

UI-PRACTICE-PHASE-62，起点 c1c0d78c。真实 QA 窗口中，输入 cx 后错误计数为 1、已经显示放弃本轮按钮，页脚却仍显示「按任意键开始」。原因是 restartInstruction 只区分快捷键与长测试保护，未读取会话 hasStarted。

先将原文案原样提取到 PracticeRestartInstruction，外层以当前 session.hasStarted 调用。先行 /tmp/typebar-restart-instruction-red-20261030.log 三项 17 处断言失败，XCTest 1.196 秒、驱动 129.287 秒，输入保持。未开始的八种快捷键／保护组合保持原样，失败只在已开始的阶段提示及真实会话首键后的状态断言。

修正仅用 hasStarted 将前缀区分为「按任意键开始」与「正在练习」。Esc、Tab、Enter、关闭快速重开，以及长测试 Shift 保护、⌘R 后备和双击 Shift+Enter 的文字不变。完成、失败、Bail Out 的结果提示继续由原终态路径处理；没有改动键盘处理器、计时、计分、存储或保护策略。

最终 /tmp/typebar-restart-instruction-focused-20261030.log 10 项通过，XCTest 0.018 秒、驱动 37.239 秒；相关 /tmp/typebar-restart-instruction-regression-20261030.log 94 项通过，XCTest 9.524 秒、驱动 13.869 秒，均零失败／跳过、输入保持。覆盖真实会话首键与新会话、全部八种原文案、重开／长测试保护、Bail Out 保存／发布、No Quit、配置重开及一个实际不可见生产宿主。这是与文案接线相称的检查，不代表全部客户端或 146 项来源方法本轮重新运行。

最终 /tmp/typebar-restart-instruction-package-20261030.log 的 Debug 包、严格签名、37 份来源／许可资源及原创性边界检查通过，驱动 43.071 秒、输入保持。检查器会清理临时包，实际 UI 使用单独生成的隔离 QA 包。

真实窗口验证分两阶段，先正常退出旧 QA，再启动修正版，没有并行实例。两者均用独立偏好域、空服务地址、内存 SwiftData 与令牌存储。旧包的完整打字过程 /tmp/typebar-restart-instruction-ui-20261030/before-fix.json：自定义文本录入、cx 误键、退格纠正、完成、同轮重复及结果返回可用。观察间隔过长的一次结果被正确判为 AFK，快速输入的一次因不足一秒被正确判为过短；另逐键输入新目标 quiet river，10 秒、11 UTF-16 单位、100% 准确率、14 WPM，结果与历史显示对应的唯一记录，前两次无效结果未写入历史。只证明同一内存会话保存，不冒充磁盘持久化或重启恢复验收。

修正版 /tmp/typebar-restart-instruction-ui-20261030/Typebar-Restart-QA.app，独立标识 app.typebar.qa.restart-instruction-20261030。CUA 在真正可见的默认计时窗口置前后输入 w：开始提示存在 → 首键后「正在练习」且不含开始提示 → 实际 ⌘R 重开后恢复开始提示、输入控件仍可用。实际截图与完整 AX 在本次对话；after-fix.json 为对返回状态的人工摘要，不作为独立自动测试报告。最后正常 Command-Q，进程表确认原生构建／测试及 Typebar 均为零。

VoiceOver、全部模式／组合的实际焦点与物理键盘、磁盘持久化、跨进程历史恢复及 Release 性能仍开放。上轮许可窗口补证一并合批提交；整体重写目标保持 active。
