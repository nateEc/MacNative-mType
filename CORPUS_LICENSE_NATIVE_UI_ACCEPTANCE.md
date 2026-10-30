# 许可入口与阅读器：真实窗口补证

2026-10-30，验证提交 c1c0d78c6a598840d90eb603c6205ec8314701c2。对既有 UI-CORPUS-LICENSE-ENTRY-59／READER-60 补证，没有新建验收 ID、修改产品或把隐藏宿主当作真实窗口。

先检查原生／构建进程均为空，再按现有打包脚本创建唯一 QA 包：/tmp/typebar-license-ui-20261030/Typebar-License-QA.app。CFBundleIdentifier=app.typebar.qa.licenses-20261030，名称 Typebar-QA-Licenses-20261030，TypebarQAInMemoryStore=true；独立偏好域的 remoteAccount.endpoint.v1 为空。现有实现据此使用内存成绩与令牌存储，配置／字体资源走 QA 路径。严格签名验证通过。只通过 CUA 启动一次，唯一 Typebar PID=70814；没有启动 app.typebar.desktop。

原生二进制 SHA-256：54a757547d52e2fab0e9232bc5d0acdc74cdf839792da2d7987ae2cf0e81b1f1。实际 CUA 窗口截图与 AX 树保留在本次对话；操作摘要及观察记录 /tmp/typebar-license-ui-20261030/acceptance.json。该 JSON 是对返回 UI 状态的人工摘要，不冒充独立自动测试报告。

| 实际操作 | 直接观察 |
| --- | --- |
| 应用菜单 → 关于 Typebar | 默认 620×792 外窗首屏直接看到完整许可链接与 UKACD 版权行，未滚动 About。 |
| 点击完整许可链接 | 原生 sheet 展示 English 450k 标题与正文，许可选择器和完成按钮可见。 |
| 正文滚至尾部，再从真正的下拉菜单选择 Ελληνικά | English 尾部文献实际可见、滚动条为 1；选择后 Greek 标题实际可见、滚动条为 0。 |
| Esc 关闭，再次点击入口 | 返回 About；重开默认 English 450k，滚动条为 0。 |
| 展开菜单，Down＋Return | 实际选择 English · Five Letter 并从其标题开始显示；点击完成关闭 sheet，返回 About。 |
| 仅将这个 QA 包的 English 许可依次改为零字节、纯空白，再分别重开 sheet | 两次都在真实错误页看到「此安装包的许可文件无法读取，请重新安装。」；没有把空白页面当成功。 |
| 恢复原文件并重开 | English 正文正常恢复且滚动条为 0；原文件与仓库逐字节一致，严格签名再次通过。 |
| Esc，再 Command-Q | 正常退出同一进程；随后进程表确认 Typebar 为零，没有以重新绑定应用来验证退出。 |

原许可备份 /tmp/typebar-license-ui-20261030/EnglishLargeCorpusNotices.original.txt，SHA-256 7bbca2ef448dcad490837886e2f6748afe7e1315a887676299b2189d34abf048。损坏操作只作用于这个临时 QA 包，仓库资源未改。AX 增量没有重复正文时不据字符串缺失判定产品失败；最终错误页、恢复页及 About 读取完整树。退出快捷键后的即时应用清单曾仍标 running，后续实际进程表才证明终态，不据异步清单重复启动或强杀进程。

这些证据覆盖默认尺寸、可见窗口、原生菜单、实际鼠标／键盘事件、sheet 关闭重开与损坏资源恢复。没有开启 VoiceOver、修改系统键盘导航偏好或改变系统缩放；全 Tab 焦点遍历、物理键盘／IME、其他缩放及尺寸仍待验证。两项保留为部分验收，不升级整体重写完成状态。

本轮仅是既有实现的真实窗口补证，按仓库规则与下一批实质代码合并提交，不单独推送文档或触发 Actions。
