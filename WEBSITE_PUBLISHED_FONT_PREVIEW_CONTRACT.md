# 完整配置提示的字体悬停预览

起点 `c0abfdc8`，固定参考 `91bd24bb8513785c7364cbea29296ff7adafac41`。旧 Root 优先读取 publication.font，虽然菜单状态记录了悬停字体，完整提示仍显示已发布字体。现增加独立显示缓存和临时字体票据，贯穿完整视口与行内提示的实际共享输入。

## 行为与边界

- 预览不修改 publication、输入会话、原生偏好、保存文件或本地字体文件，也不产生配置 setter、重开或资源发布。文字、主／节奏光标和行宽使用同一份临时字体；列宽按该字体的实际 chAdvance 计算。
- 缓存按窗口、选项和字号保留一份资源，不随无关 publication 更新重复建字。字号变化会重建；其他窗口不能借用票据，旧字号票据不能造成分裂几何，未准备的 publication 不能靠临时字体通过准入。
- 预览的候选链按固定完整 previewFontFamily：选中名称、Roboto Mono、Vazirharf、monospace；不读取本地字体文件或加入语言首选字体。系统设计选项使用项目自有稳定别名，经 AppKit 设计 API 解析。
- 按固定 clearFontPreview，关闭／离开字体行恢复最新 Config 中的名称，仍是预览候选链；即使此前有本地文件，也不在此步骤重新应用文件。后续真实 applyFontFamily 事件恢复完整的本地文件／语言候选链。原先的预览标志语义保留，不用直觉修改这个来源行为。
- 字体／语言应用事件和独立本地文件更新清除临时覆盖；单独换字号保留所选预览字体并使用新字号。Root 的旧绘制失败回调须仍匹配当前字体，避免旧字体的失败把新预览切到回退视口。
- 来源预览 CSS 的最后一个 monospace 带引号。原生适配器用系统等宽字体兜底；候选意图／文本可对照，不宣称该字面字体名的浏览器解析或像素一致，也不复制原字体资产。

## 验证

`/tmp/typebar-published-font-preview-red.log` 一处先行反例确认悬停 Georgia 后共享输入仍为 Courier。首次接线的编译边界（`typebar-published-font-preview-green.log`）是嵌套票据需要显式 MainActor，以及 Root 单个 SwiftUI 表达式过长；现分开字体观察链，没有改变修饰符顺序。

`typebar-published-font-preview-core.log` 中的系统字体私有名称比较不适用于 CoreText 组合字体：系统 UI 名称在组合后规范化。夹具现分别检查主字形身份、字号和真实文本宽度，未改变生产字体以凑名称。`typebar-published-font-preview-mounted.log` 的私有 Observable 嵌套类型宏访问错误也属夹具编译边界，不算旧产品行为。

隐藏绘制夹具最初没有完整视口要求的滚动父级；添加后仍用同步 RunLoop 阻塞异步测试主线程，收不到就绪回调，见 `typebar-published-font-preview-mounted-verified.log` 与 `typebar-published-font-preview-scroll-host.log`。现保留真实滚动／高度准入，并异步等待实际布局，没有放宽生产就绪条件。`/tmp/typebar-published-font-preview-async-host.log` 及同名 JSON 的真实隐藏组件检查通过（0.391 秒，驱动 19.212 秒）：原本地文件字形 → Georgia → 关闭后 Courier，窗口始终不可见，配置文件与尝试不变。

必需来源清单增至 110 项，加入已有完整预览／活动行／关闭路径的 12 组轨迹方法，现同时比较原生预览候选链。完整函数执行仍使用明确 DOM／文件／语言适配器，不称浏览器端到端绘制。

最终定向 51 项零失败、零跳过（3.962 秒，驱动 7.491 秒；`/tmp/typebar-published-font-preview-focused-verified.log` 及同名 JSON），输入哈希不变。包括十项新检查及已有预览、字体资源和已发布提示检查；覆盖真实当前页面与活动 No Quit 不变、文件覆盖的预览／关闭／重新应用、跨窗口与旧字号拒绝、未准备资源拒绝、全部原生系统设计、缓存保持、共同光标／行宽，以及实际隐藏菜单和 TextKit 三阶段。

最终扩大回归 690 项零失败、零跳过（322.957 秒，驱动 333.078 秒；`/tmp/typebar-published-font-preview-regression.log` 及同名 JSON），同日志全部 110 项必需来源方法通过（`.evidence.log`），输入哈希不变。核对实际 XCTest suite，新预览、原发布提示和完整来源轨迹类均运行；覆盖三十九类相关测试和其余必需来源方法，未选择可见 StartupHost 类。只读 SQLite 日志属于归档故障注入的预期输出，不是跳过或失败。

13 项证据校验契约、参考元数据／行为审计和 1401 个唯一人工场景结构审计通过。结构审计不代表实机验收。同版 debug 包构建、签名、资源和原创性检查通过（32.747 秒；`/tmp/typebar-published-font-preview-package.log` 及同名 JSON），输入哈希不变，没有启动主程序。

提交前更新远端：开发分支仍为 `c0abfdc8`，主线仍为 `8c52fb13`，没有开放的开发分支 PR，Actions 总数保持 826、最新主线门禁成功。只合批推送开发分支，不合并主线或用推送试错；没有运行整套客户端、服务或完整 readiness。

## 尚未验收

隐藏测试挂载真实 CommandPaletteView 与已发布提示／TextKit 组件，Root 产品接线另经编译与读取核对；它不等于对完整产品窗口做了实体鼠标、键盘和辅助功能验收。仍未处理未消费回执期间的旧字体即时重绑定；主题／背景控制、真实多窗口和完整 readiness 保持开放，整体 goal active。
