# 许可切换与空内容错误

`UI-CORPUS-LICENSE-READER-60`，起点 4f487203。实际用户路径是读到长许可尾部，再选择另一份许可；新文档应从标题开始。损坏为零字节或纯空白的许可文件应显示既有安装包错误提示，不能显示一个看似加载成功的空白页。

先将既有阅读内容拆为共享 CorpusLicenseReader：外层 CorpusLicensesView 继续持有默认 English 450k 的选择状态，生产 Picker 与测试宿主使用同一个 Binding。此步骤没有增加滚动重置或文件过滤。测试改变真实共享组件的选择绑定，不声称完成了实体点击 Picker 或系统 sheet 验收。

先行 /tmp/typebar-license-reader-red-20261030.log 两项三处失败，XCTest 2.700 秒、驱动 83.945 秒。补充错误页像素检查与手动恢复顶部的独立证据后，/tmp/typebar-license-reader-confirm-red-20261030.log 三项四处失败，XCTest 3.237 秒、驱动 25.395 秒。滚到 English 尾部后切到 Ελληνικά，实际像素仍是尾部文献；手动滚回顶部后可找到 Greek 标题，证明是位置保留而非新文档未加载。空文件、空白文件被读取为有效字符串；零字节文件的实际页面没有错误提示。两次作业的非 Markdown 输入均保持。

只给文档 ScrollView 加入选中文档身份，使换文档时重建滚动区域，不重建外部 Picker、标题或完成按钮。文件读取只检查去掉空白后的内容是否为空，返回仍为原始完整字符串，不裁切或改写有效许可。阅读器继续使用原文件、错误提示与 dismiss 动作，没有引入网络、额外窗口或参考项目资产。

最终 /tmp/typebar-license-reader-focused-20261030.log 的 12 项通过，XCTest 4.392 秒、驱动 41.022 秒；/tmp/typebar-license-reader-regression-20261030.log 的 20 项通过，XCTest 4.453 秒、驱动 7.342 秒。均零失败／跳过、输入保持。包括全部七项署名／许可检查、About 入口、相关 No Quit 与偏好配置保存边界。22 个许可选项逐一读取并与原文件完整文本比较。此范围不代表当前完整客户端、服务端或 146 项来源方法重新运行。

实际不可见组件的 /tmp/typebar-license-switch-new-selection.png 已确认新 Greek 文档标题显示在顶部；/tmp/typebar-license-reader-empty.png 显示原安装包警告。先行失败图像另存 /tmp/typebar-license-reader-red-retained-tail-20261030.png 与 /tmp/typebar-license-reader-red-empty-20261030.png。这些像素只证明文档与警告内容，不替代原生 Picker 菜单、完成按钮、实体键盘、焦点、VoiceOver、不同缩放、系统 sheet 关闭／重开与安装后运行的人工验证。

最终 /tmp/typebar-license-reader-package-20261030.log 的 Debug 包、严格签名、37 份来源／许可资源逐字节核对与原创性边界检查通过，驱动 42.171 秒，作业终态为成功、非 Markdown 输入保持。没有启动 Typebar 主程序。手工矩阵结构检查通过，现有 1,466 个唯一场景。整体重写 goal 保持 active，其他内容质量、用户流程和性能缺口不因本批通过而关闭。
