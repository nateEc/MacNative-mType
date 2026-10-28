# 完整导入初始化期间的主题

固定参考 `91bd24bb8513785c7364cbea29296ff7adafac41`。承接 `WEBSITE_THEME_IMPORT_RESTART_CONTRACT.md`，本批处理完整配置已保存、练习资源尚未交付时的主题显示；整体功能和实体交互验收仍未完成。

## 来源与行为

参考主题控制器在 `fullConfigChangeFinished` 清除随机覆盖和预览，然后应用系统、自定义或手动主题。该事件不等待 TestLogic 的初始化完成。媒体监听器另有 `!autoSwitchTheme || customTheme` 早退条件：整份导入可以先选系统浅色主题，而开启自定义主题时，后来的系统深色事件不再改色。初始化完成或恢复不能重放完整主题事件。

沿用真实总线来源探针的 96 条轨迹、192 个检查点。现有必需来源方法另比较其中 16 条练习页失败轨迹的最终主题名称；原生以真实引用提供方失败代替来源探针的自有初始化失败适配器，保持所有主题字段，未将两者的文本生成或运行时配置称为等价。来源颜色仍为自有适配数据，不代表复制或验收原版配色。

## 原生边界

完整配置保存前预计算 PendingTheme，仅成功 CAS 后安装在当前窗口的 savedApplication 中。对象只携带配色和主题事件状态，不伪造资源发布，也不更换旧输入、字体、媒体和历史账本。初始化失败或取消后继续显示已接受主题；恢复和初始化校正保留该对象。最终交付仅在待应用标识和八个主题字段全部相等时沿用这份状态，避免重放完整主题事件。主题字段不匹配时重新预计算，不把旧快照套到新主题上。

根视图的底色、色彩方案和页脚采用待应用主题，并抑制旧发布的悬停预览。已有背景媒体仍使用已准入的旧资源，只换底色；没有旧发布时只绘制原生底色，不借此读取未准入的原生后备媒体。新的背景 URL、过滤器、字体和其他初始化显示效果仍需独立处理，不能把本批主题修复当作整份失败阶段展示已对齐。

## 证据

`testFailedImportDisplaysItsThemeBeforeResourcesAndRetainsItOnRecovery` 在旧实现稳定产生两项颜色断言失败；输入、旧资源发布、原生后备和账本断言均通过。日志 `/tmp/typebar-pending-theme-red.log`，1 项测试、2 项预期失败。

`testPendingThemeObservesMediaWhileInitializationIsSuspendedWithoutReplayingOnDelivery` 使用真实工作流和挂起的引用提供方，分别验证 customTheme 为 false/true 时的浅色导入、深色媒体事件和最终交付，并检查页脚主题。窗口不会显示，也不启动可见 Typebar 应用。

`testColdFailedImportUsesTheActualSchemeAndReplacementRetiresTheOldPendingColors` 覆盖没有旧发布的深色启动失败，以及新导入替换旧待应用对象后，旧对象的媒体事件不再改变当前配色。

`testBackgroundColorsRenderBeforeTheNewPracticeIsReady` 对生产背景的 SwiftUI 底色层实际离屏渲染并比较像素，覆盖旧色、挂起时新色和取消后新色。后台窗口的 cacheDisplay 曾返回全透明图；ImageRenderer 也不能绘制 AppKit 媒体层，因此没有把这两种失败的捕获作为通过证据。媒体容器现在直接使用可独立渲染的同一个 backdrop，原生媒体层另由既有像素测试检查。本项不声称验收完整可见窗口或新媒体的提前交付。

像素期望值也用同一个渲染器绘制标准主题 Color，避免将未经 TIFF 色彩配置转换的 NSColor 通道直接与渲染图比较；旧主题与新主题仍分别断言，不放宽成只检查“有像素”。

本会话作了有界反例检查：主题预计算发生在 CAS 前，安装发生在 CAS 后；旧 PendingTheme 的迟到媒体更新只修改旧对象；最终提交仍先检查窗口／请求／磁盘和待应用捕获。没有新增跨窗口注册、保存回调或应用启动入口。这是会话内审查，不能代替独立审查或实体交互验收。

最终 `/tmp/typebar-pending-theme-regression.log` 854 项相关回归零失败、零跳过，独立检查确认 117 项必需来源方法全部执行（驱动 395.422 秒）。`/tmp/typebar-pending-theme-package.log` debug 应用包构建、签名、包资源和固定参考原创性检查通过（37.705 秒）。两个原生作业串行，代码输入哈希均保持不变；离屏像素定向测试也单独通过（19.255 秒，含编译）。证据检查自身 13 项、固定参考元数据和行为审计、1,404 项人工账本结构检查通过。未启动可见 Typebar，参考克隆干净。

推送目标仍为无开放 PR 的开发分支 `native-parity-next`。本批不触发 main 门禁；这些通过证据不改变上文保留的新媒体、字体、完整可见窗口与全项目验收范围。
