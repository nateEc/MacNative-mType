# 原创性边界与验证

Typebar 以固定版本的 Monkeytype 作为功能盘点参考，而不是实现、内容或运行时依赖。本规则落实 `GOV-01`：功能兼容不等于复制；所有交付都必须能够说明“观察到什么行为”与“Typebar 如何独立实现”之间的边界。

## 可使用的参考信息

- 可从固定参考提交 `91bd24bb8513785c7364cbea29296ff7adafac41` 提取功能、模式、配置、语言或键盘布局的**名称、枚举身份、数量和可观察行为**，用于 `OFFICIAL_*_AUDIT.md` 与 `Compatibility/` 的兼容性对照。
- 用于生成兼容性快照的脚本只读取 schema 的标识与本地映射。每个脚本会写明实际读取的参考文件，且生成物不得含有参考词表、引语、主题、字体、图片或源码片段。
- 行为取证应落到 Typebar 自己的 Swift / SwiftUI / SwiftData 设计、测试和人工验收中；服务端仅使用 Typebar 的 API 契约与数据模型。

## 不可使用的内容

- 不复制、翻译、移植或打包参考项目的源码、测试、构建配置、CI、网页模板、样式、图像、字体、声音、主题、词库、引语、文本、布局 JSON 或线上数据。
- 不请求、代理、镜像或以任何生产代码路径连接 Monkeytype 的网站、API、账户、排行榜或内容服务。
- 任何新增的提示内容、视觉资产、字体、声音或第三方数据，都必须是自制或具有明确、适合再分发的授权，并在提交中说明来源和许可边界。

## 机械护栏

运行以下命令：

```zsh
zsh Scripts/check-originality-boundaries.sh --self-test
```

它检查已追踪文件，拒绝参考 Web 工程的 `backend/`、`frontend/`、`packages/` 树，拒绝其前端包清单及 TypeScript／网页组件文件，并扫描客户端和自建服务的 Swift 源码，阻止其直接指向 `monkeytype.com`。`--self-test` 还会验证护栏确实能拒绝一组模拟的违规路径及一条刻意复制的长源码行。

在本机已有固定参考检出时，再运行：

```zsh
zsh Scripts/check-originality-boundaries.sh --reference /absolute/path/to/monkeytype-reference
```

该模式会先将参考检出严格固定到兼容性快照记录的提交，再将 Typebar 的生产 `Sources/**/*.swift` 与 `server/Sources/**/*.swift` 同参考项目的 `frontend`、`backend`、`packages` 中 JS／TS 源码逐行做空白归一化。任一边界两侧出现相同、至少 120 字节的行即失败；输出只报告数量，不回显参考源码。它有意不扫描文档、兼容性 ID 快照或测试夹具，以免把允许的名称和枚举对照误作实现复制。

同一模式还会对生产资源目录中的 PNG/JPEG/GIF/WebP/SVG/PDF/图标、WOFF/TTF/OTF 字体、常见音频，以及 JSON/TXT/CSV/XML/YAML/HTML/CSS 文件，与固定参考检出中的同类文件比较 SHA-256。只要存在完全相同的字节就失败，且仅报告重复哈希数量。`Compatibility/`、测试和文档不在此范围，避免把允许的标识级快照误作资源；当前 Typebar 的生产资源目录没有此类打包文件。该检查确保后续新增的自制或已授权资源不会悄悄变成参考副本。

这不是“原创性的数学证明”：它不能比较两段不同语言的语义、跨行或改写后的复制，也不能判断第三方内容授权，哈希也不能识别变形后的资产。因此合并前仍须进行人工审查：确认实现为原生重写、内容来源独立、兼容性快照只含允许的元数据，并为受影响的功能 ID 补充自动化和人工验收证据。

## 证据链

- [REWRITE_SPEC.md](REWRITE_SPEC.md) 规定独立实现和完整重写的交付门槛。
- [FUNCTIONAL_INVENTORY.md](FUNCTIONAL_INVENTORY.md) 以功能 ID、实现位置和验收状态追踪兼容范围。
- [ARCHITECTURE.md](ARCHITECTURE.md) 禁止客户端与自建服务依赖或代理 Monkeytype 生产服务。
- `OFFICIAL_*_AUDIT.md` 与 `Compatibility/` 保存固定版本的盘点证据，而非参考项目资产。
