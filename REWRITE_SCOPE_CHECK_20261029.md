# 重写范围与尚未满足的条件

核对起点 `2b33c52d2c2d6ca43d071e532cf8085f81c7c320`，固定参考 `91bd24bb8513785c7364cbea29296ff7adafac41`。后续 cecd0777 的挪威语基础池及本轮五字母英语增量分别见其专项合同；下文保留各次完整／扩大运行的历史边界。目标仍是完整原生重写、独立实现／资产及原用户功能覆盖。本记录不是完成验收，也不替代 FUNCTIONAL_INVENTORY.md、MANUAL_ACCEPTANCE.md 与各专项合同的全部开放项。

## 当前证据的范围

| 目标条件 | 当前权威入口与观察 | 仍需证明的条件 |
| --- | --- | --- |
| 原生实现与独立代码／资产 | Package.swift、Sources/Typebar、签名包及 originality 检查；当前产品目录搜索未发现 WKWebView／WebView 或参考 QA 环境入口，应用使用 SwiftUI／AppKit／SwiftData。固定参考只用于 QA。 | 原创性检查针对受保护资源和长字面内容，不能单独证明所有代码／资产独立或全部运行路径。仍需保留逐项来源与产品边界。 |
| 配置行为完整 | Compatibility/official-configs.json：94 项，89 mapped、4 partial、1 ads 不适用，无遗漏 ID。 | compositionDisplay、tapeMode、showAllLines、fontFamily 仍明确 partial。Mapped 是原生入口关联，不能代替全部选择、交互、实时应用、错误及持久化行为证明。 |
| 页面及弹层完整 | official-page-modal-surfaces.json：53 项，47 mapped、6 明确不适用；mapped 描述本身仍列部分覆盖。 | 各真实入口的展示、提交、取消、失败、异步时序和跨窗口行为；不能由文件／符号存在直接升级为完整验收。 |
| 语言内容与输入完整 | official-languages.json：446 个身份均映射独立原生 ID。繁体中文五档原形选编接入后，直接具名 ScaleLexicon 扫描仍有 104 路／795,393 个声明位置，源哈希及只读报告见 TRADITIONAL_CHINESE_CORPUS_PREPARATION.md。 | 声明位置不是实际词数，结构扫描不覆盖所有构造器或基本池。独立真实语料、最长字段、特殊标点／文字、实际观察与质量仍有已知差距，例如 Russian 375k 46／49、撇号／prime；Ukrainian 50k 的双撇号＋连字符组合已以真实文本补齐。各基础池的独立扩充单列追踪；词值、频率、难度及语义质量仍需证明。 |
| 键盘与实体输入 | official-layouts.json：239 个 nativeExact 身份，完整四层审计开关在本轮全范围运行中启用。 | 映射数不等于所有实体按键、IME、显示器、布局切换和辅助功能验收。最终结果及具体比较点应从本次实际测试日志读取。 |
| 主题与显示 | official-themes.json：187 个参考名称、188 个原生内置主题；0 exactMappings、187 relatedMappings。 | 名称／相关配色不能证明完整颜色、预览、保存、随机、系统切换和所有显示行为；独立设计与参考差异仍需明确验收。 |
| 挑战规则及受限入口 | official-challenges.json：58 项，57 nativeEquivalent、1 pending。 | mobileWarrior 原条件为移动设备一小时测试，macOS 不能满足该设备条件；当前导入解释限制，不颁发冒充等价的原生成就。该限制仍须在整体兼容结论中保留。 |
| 远端／自托管服务 | official-service-surfaces.json：14 模块，12 mapped，dev／webhooks 两项不适用。 | 模块关联不足以证明所有请求、响应、权限、账户、缓存、故障和恢复行为。当前客户端结果不外推为当前服务端全部通过。 |
| 用户流程与性能 | MANUAL_ACCEPTANCE.md 现有 1,469 个唯一场景，结构检查通过。各专项有隐藏宿主、源对照及局部性能证据。 | 实体窗口、键盘／IME、VoiceOver、全部组合、完整 Release／最低设备性能仍开放。结构检查和 getter 探针不是这些条件的证明。 |

行为关联索引为 47 direct、119 个原生测试符号、17 support；它证明关联与方法存在，实际执行由源证据日志验证。最近希腊语最终数据相关 1,269 项扩大回归／其中 146 项必需源对照通过，见 GREEK_CORPUS_CONTRACT.md；不是全部客户端或完整重写验收。

## 本轮客户端范围的失败与复验

本轮独立记录 `/tmp/typebar-client-2b33c52d-baseline-20261029.json`，驱动同前缀 `-driver.py`，原生输出 `.log`。六个历史磁盘写入器串行准备完成，再运行客户端；启用输入／渲染耐久、四层布局审计及全部现有源 QA 环境。全部 1,361 个受跟踪及非忽略、非 Markdown 输入冻结，运行中只追加 Markdown 证据。

保留此前三个明确显示窗口的独立待验收项：两项 WebsiteConfigStartupHostTests 的配置导出 sheet 展示，以及 ResultSheetTerminationTests 的真实 sheet 退出。其余方法不按定向正则挑选。这三个排除仍属于未验证范围，不能从“零运行时跳过”推导为零排除或完整实体客户端通过。

本轮已发现 BritishWordGenerationTests.testLazyNormalizationRunsBeforeBritishReplacement 失败：英式英文、quote、Lazy 请求、输入 `cólór`，旧断言要求 `colour`，实际 `cólór`。固定参考 test-logic.ts 在初始化使用 `!language.noLazyMode || mode === custom`；words-generator.ts 的逐词 Lazy 也使用同一资格条件，随后才运行英式替换。隔离读取元数据仅得到 English 的 noLazyMode=true、English Legal 未声明该禁用项，没有输出参考词值。

当前原生 PolyglotGenerationPreparation／ArabicLazyInputPolicy 已按这些资格条件处理 fresh 配置。因此该失败指向旧 quote 夹具将不支持 Lazy 的 English 当作支持者；这不构成恢复无条件去重音的依据。需用支持 Lazy 的英语目录保留原来的转换次序断言，并补上基本 English 的拒绝条件及 custom 例外，进行来源／原生复验。

完整驱动已经终止：退出码 1、516.286 秒，1,361 个输入保持；记录 1,592 个方法通过、上述一项断言失败，随后在 IncompletePracticeEvidenceTests 的独立内存容器保存处 SIGTRAP，没有完整套件摘要，也未做必需源证据汇总。German 宿主加该方法单独复现。等待实际 onDisappear／延长容器生命与自动释放池两种对照均不足，已撤回，不把它们称为修复；当前继续读调试器证据，保存方法及断言未修改。十万词耐久及历史迁移的局部通过另见 CLIENT_BASELINE_20261029.md。

后续 German 加原保存方法的严格对照已通过：须保留容器直到实际根视图回调所有者释放，并通过异步轮询允许 MainActor 任务退休；仅 onDisappear、自动释放池或单次 yield 均已证伪。共同约束现用于十类隐藏练习宿主，保留原断言和保存模型；正常／异常退出的生命周期及 Lazy 资格双方共 82 项定向检查通过。十类宿主和完整客户端仍需分别等实际终态，不从两方法对照外推全部存储正确。详见 CLIENT_BASELINE_20261029.md。

随后十类宿主及视口等 60 项通过；完整范围 `/tmp/typebar-client-lifetime-fixed-20261029.log` 已实际结束，6,867 项中 6,866 通过、一项失败，零运行时跳过、同样三个显式窗口排除，1,362 个冻结输入保持，未再 SIGTRAP。唯一失败为 English 450k 弱项报告仍要求所有推荐词有共同前缀；原生既有策略评分词中任意位置的错字符并保留同分词库顺序。单独红复现后，夹具保留八词断言，增加唯一错字符、错误次数及实际索引词库选择验证；评分算法未改。修正后的弱项、英式拼写及生命周期 65 项通过。完整红基线保留，正式源汇总拒绝该红日志，不声称修正后已重新完整通过；扩大源回归另取结果。

最后扩大回归 `/tmp/typebar-lifetime-regression-20261029.log` 已实际终止：1,205 项通过、零失败／运行时跳过，非 Markdown 输入保持，146 项必需源证据正式汇总通过。最后一次弱项夹具改动后未再次完整运行，不能把完整红基线替换成全绿；整体 goal 保持 active。

本轮将诊断与实质夹具／生命周期修正合并为一个开发分支批次，不推送独立文档诊断，不调度／重跑 GitHub Actions，不启动 Typebar 主程序。生产策略、资源、CI 触发条件和通知设置保持。

## 2026-10-30 复验补充

起点 95e0c9a0 的完整范围仍为 6,867 项中一失败，但此前弱项方法及存储均通过；唯一失败是实际许可证截图完整可见、OCR 分块导致连续句子断言失败。同图像无提示词对照后，仅规范化测试比较的空白，四项许可证检查通过。此前排除的三个窗口方法各以单独 XCTest 作业串行通过，启动下一项前确认前项已退出；其中结果 sheet 方法仅验证阻止终止标志，不执行真实应用退出。

详细原始记录、图像哈希和证据边界见 CLIENT_BASELINE_20261030.md。三项自动化执行缺口已取得独立证据，但最后 OCR 夹具修改后未再次完整运行，不把分开执行相加称作全套通过，也不升级原有配置部分兼容、人工／实体设备与语料质量结论。

## 当前客户端完整基线（3781c7b9）

此后提交 3781c7b9 已完成一次无筛选、无排除的完整客户端运行：6,870 项通过、零失败／运行时跳过，146 项必需源证据正式汇总通过；三项此前单列的窗口方法也在同一个完整顺序中各通过。1,362 个非 Markdown 输入保持，无 swift-test／xctest／主程序残留。详细驱动、时长及方法记录见 CLIENT_BASELINE_20261030.md 首节，旧红基线不删除。

这更新的是当前客户端自动化基线，不是完整目标的验收。上述四项配置部分覆盖、语料质量与缺口、实体键盘／IME／VoiceOver、主题差异、平台条件、服务端当前状态、完整 Release／最低设备性能和全部用户流程仍须各自证明；不得由一次客户端全绿升级为整个重写完成。

客户端结束后，同提交服务端 501 项完整测试独立通过，零失败／运行时跳过；隔离依赖为 LRU 11.5.1、Redis 服务端 6.2.6，未使用系统 8.6.1 服务端。再串行完成 Debug 包、资源及原创性边界检查，均退出 0、输入保持，无主程序启动。详细记录见 CLIENT_BASELINE_20261030.md。服务端当前自动化状态由此取得证据，但真实服务部署、外部服务、故障恢复及全部服务行为覆盖仍不由这些测试证明；四项配置、语料／实体输入、主题和 Release 等开放项保持。
