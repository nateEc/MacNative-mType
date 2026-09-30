# 官方主题身份与原生覆盖审计

参考固定为 Monkeytype 提交 `91bd24bb8513785c7364cbea29296ff7adafac41` 的 `packages/schemas/src/themes.ts` 中 `ThemeNameSchema`。本审计只保存主题 ID、数量与覆盖状态；不读取、复制或导入官方主题的色值、CSS、图片、字体或其他资产。

当前守恒：187 个官方主题身份、0 个已验证精确原生映射、187 个待映射。逐项身份见 `Compatibility/official-themes.json`；没有列入 `exactMappings` 的每个身份均为待映射，而不是自动套用同名 Typebar 主题。

Typebar 当前有 3 个自行设计的内置主题：`paper`、`midnight`、`grove`。`paper` 与 `midnight` 恰好也是固定 schema 中的字符串，但其 Typebar 调色板独立定义，没有官方视觉等价证据，因此仍不算精确映射。用户可自行创建、编辑、收藏、随机切换和归档本机主题，也可主动导入自己持有的网页自定义主题链接；这提供主题功能入口，不等于恢复官方全部命名预设。

`Scripts/check-theme-compatibility-audit.rb` 从固定 schema 重建 187 个身份，与机器清单及本机内置枚举逐项核对，并拒绝未经登记的计数或身份漂移。门禁只证明盘点完整，不证明 187 个视觉主题已实现。后续若增加独立制作且获允许的精确主题，需要先有可核查的视觉、交互与授权证据，再更新逐项映射；不以程序生成的任意颜色冒充原主题。
