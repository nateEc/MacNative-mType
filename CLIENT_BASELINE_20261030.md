# 客户端范围复验与许可证像素证据

起点 `95e0c9a077eff5a7ff5eec16667c525cd93e86a2`，固定参考 `91bd24bb8513785c7364cbea29296ff7adafac41`。本记录不声明完整重写完成；此前诊断见 CLIENT_BASELINE_20261029.md，整体缺口见 REWRITE_SCOPE_CHECK_20261029.md。

## 完整运行的实际终态

`/tmp/typebar-client-95e0c9a0-baseline-20261029.json` 及同前缀 `.log`：六个历史磁盘写入器串行准备成功，启用输入／渲染耐久、四层布局及全部既有源 QA 环境；排除同样三项明确显示窗口的方法。驱动退出 1、3,539.917 秒，测试阶段 3,532.213 秒；6,867 项中 6,866 通过、一项失败，零运行时跳过。冻结的 1,362 个非 Markdown 输入全部保持。没有中途修改代码、重启或并行启动原生作业。

原内存存储保存崩溃未再发生，English 450k 弱项原失败方法在完整顺序中通过（0.789 秒）。唯一失败为 CorpusAttributionTests.testNativeLicenseReaderDisplaysTheBundledDocumentWithoutShowingAWindow 第 97 行的许可句子连续匹配。完整红基线保留，未据局部通过声称完整运行全绿；该驱动因原生退出 1 没有执行正式源证据汇总。

## 同一图像的红绿对照

保留失败时实际缓存的图像 `/tmp/typebar-client-95e0c9a0-license-reader-failure-20261030.png`，SHA-256 为 `fdc36cb4a7fd0efb54f6cd1f5dead8e393de02c1e0a202a661f3b079c511e611`。目视可见所需来源句子完整存在，OCR 却将 Includes 与后续文字分到不同 observation。旧断言以换行拼接后比较连续空格句子，因此失败。

在完整作业实际结束后，单独运行 `/tmp/typebar-license-reader-captured-ocr-20261030.swift` 读取同一图像，使用与测试相同的 Vision accurate、en-US、禁用语言修正；customWords 数量为零，不将预期来源文字输入识别器。日志同前缀 `.log`：38 个识别块，原拼接匹配 false，仅合并空白后 true，将来源名称改为其他名称仍 false。原失败日志的只读移除句子对照也仍失败，见 `/tmp/typebar-license-reader-ocr-diagnosis-20261030.json`。临时探针首次因 customWords 的非可选类型编译失败，单独留档；它不是运行结果，修正该临时类型访问后探针退出 0。

本轮仅将两个像素文字断言的比较文本按空白切分后重新连接。大小写、名称、标点、真实 OCR、原始失败输出、读取失败检测、末尾 DOI 滚动检查及隐藏窗口断言均保留。没有修改产品显示、许可文件、OCR 提示词或识别配置。`/tmp/typebar-license-reader-fixed-20261030.log` 四项通过，XCTest 1.554 秒、驱动 25.947 秒，输入保持。

## 三项窗口方法的独立证据

此前完整作业排除的方法，现各自用一个独立 XCTest 作业串行执行。每次启动前确认前一个 swift-test／xctest 已退出，没有启动 Typebar 主程序；各方法原有 defer 关闭窗口，进程退出后再启动下一项。没有把三个单独作业合称一次完整客户端运行。

| 原方法 | 实际日志（均在 /tmp） | XCTest / 驱动秒数 | 终态及范围 |
| --- | --- | --- | --- |
| WebsiteConfigStartupHostTests.testActualCommandPaletteHandsOffToCurrentConfigurationExportSheet | typebar-visible-command-export-20261030.log | 8.128 / 12.382 | 一项通过，包含 noQuit 两种条件；实际命令面板交接导出 sheet，原输入、尝试及存储断言保留。 |
| WebsiteConfigStartupHostTests.testSettingsExportActionPresentsLatestStoreInProductionManualCopySheet | typebar-visible-settings-export-20261030.log | 3.237 / 8.384 | 一项通过；实际手动复制 sheet 使用最新发布的设置，既有输入及存储断言保留。 |
| ResultSheetTerminationTests.testActualSwiftUISheetDoesNotPreventTermination | typebar-visible-result-sheet-20261030.log | 0.718 / 6.221 | 一项通过；实际 SwiftUI sheet 的阻止终止标志为 false，没有在此方法中执行真实应用退出。 |

三项均退出 0、冻结输入保持。它们补齐三个自动化方法的独立执行证据，不等于人工操作、VoiceOver、实体 IME、正式结果页真实退出或全部窗口组合验收。

## 后续验证与边界

`/tmp/typebar-license-reader-source-regression-20261030.log` 实际终止，146 项全部通过、零失败／运行时跳过，XCTest 370.681 秒、驱动 382.889 秒，输入保持；同前缀 `.evidence.log` 正式确认全部 146 项必需源证据通过，汇总退出 0。结束后确认没有 swift-test、xctest 或 Typebar 主程序残留。

最后一次 OCR 断言改动后尚未再次执行完整 6,867 项，不把三个窗口方法与局部回归相加冒充单次全绿。配置部分兼容、语料语义／输入、实体设备和完整性能等整体缺口仍开放，goal 保持 active。生产代码、资源、CI 触发条件及通知设置未改；提交前远端 main 仍为 8c52fb13、开发分支 95e0c9a0，无开放 PR，Actions 总数 826、最新主分支运行成功。
