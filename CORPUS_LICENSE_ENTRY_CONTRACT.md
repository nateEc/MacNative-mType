# About 首屏完整许可入口

`UI-CORPUS-LICENSE-ENTRY-59`，起点 7389b0d3。随着独立词库来源说明增加，原来位于整段说明底部的「查看完整许可…」在真实 About 620×760 首屏中被挤至裁切边缘。用户必须额外滚动才能看到完整入口；上一批 /tmp/typebar-greek-about-20261030.png 已保存此布局症状。

将既有许可按钮移到「词库与开源署名」标题旁，使用同一行的尾部位置。没有缩小字体、删去来源、缩短署名或改变窗口高度来掩盖增长。按钮沿用相同 showingNotices 状态及 CorpusLicensesView sheet，原 UK Advanced Cryptics Dictionary 显著署名与完整版权行保留，词库／许可资源及业务规则不改。

新增真实渲染回归：挂载 AboutTypebarView 的不可见原生窗口，隔离 UserDefaults 并禁用真实服务端点，实际缓存渲染像素；Vision 使用 zh-Hans／en-US，不设置期待文本提示，定位完整的「查看完整许可」识别结果并要求其位于首屏上部。只忽略 OCR 的空白及标点，不补字或修改图像。原英语署名检查仍使用原先 en-US 设置及首屏上半部断言。

先行 /tmp/typebar-license-entry-red-20261030.log 一项一处失败，原因是实际图像中无法找到完整入口；XCTest 2.271 秒、驱动 24.929 秒，输入保持。布局修正后 /tmp/typebar-license-entry-focused-20261030.log 的 10 项全部通过、零失败／跳过，XCTest 2.523 秒、驱动 39.631 秒，输入保持。包含全部五项来源／许可测试、About 版本与命令搜索，以及既有 No Quit 导航／配置锁与归档拒绝检查。

最终相关 /tmp/typebar-license-entry-regression-20261030.log 的 18 项通过、零失败／跳过，XCTest 2.580 秒、驱动 6.244 秒，输入保持；增加全部以 NoQuit 开头的引擎规则及偏好配置保存检查。此范围不代表当前所有客户端或 146 项来源检查重新运行；上一批希腊语 1,269 项／146 项结果保留原来的输入边界。

当前实际渲染截图 /tmp/typebar-license-entry-final-20261030.png，SHA `66a4a87f451c73809d1cc932f9db30a45ebb737a8ce9da9c69627e271d63f113`，已目视确认按钮完整位于来源标题右侧，署名仍显著可见。所有测试窗口始终不可见，没有启动 Typebar 主程序或打开真实系统 sheet。

当前 /tmp/typebar-license-entry-package-20261030.log 的 Debug 包、严格签名、37 份来源／许可资源逐字节核对及原创性边界检查通过，驱动 42.554 秒，输入保持。三个成功作业的输入指纹再次与当前文件逐项比较一致，当前原生及主程序进程均为零。推送前 main=8c52fb13028f82fd8e8718d55cb7ed65463b034e、开发分支=7389b0d31fe072b875195d25ac9726c31b5b6e6d、开放 PR=0；Actions 共 826 次、最新 39118939684 成功。仅合批推送开发分支一次，不改 main、CI 或通知偏好。

实体点击、键盘焦点／VoiceOver、真实 sheet 的打开／关闭、其他文字缩放及窗口尺寸仍待单个隔离实例人工验收，不用 OCR 坐标通过替代这些条件。整体重写 goal 保持 active。
