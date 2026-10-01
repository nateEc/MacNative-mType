# 官方主题身份与原生覆盖审计

参考固定为 Monkeytype 提交 `91bd24bb8513785c7364cbea29296ff7adafac41` 的 `packages/schemas/src/themes.ts` 中 `ThemeNameSchema`。本审计只保存主题 ID、数量与覆盖状态；不读取、复制或导入官方主题的色值、CSS、图片、字体或其他资产。

当前守恒：187 个官方主题身份、0 个已验证精确原生映射、187 个待映射；其中 5 个原创相关替代、182 个尚无相关替代。逐项身份见 `Compatibility/official-themes.json`；`relatedMappings` 只表示同题材的 Typebar 原创选择，绝不算入 `exactMappings`。

Typebar 当前有 6 个自行设计的内置主题：原有 `paper`、`midnight`、`grove`，以及极光、海岸、夜间餐厅三个原创同题材变体。新增三项各有独立的字色、弱提示、光标强调和明暗方案，仍使用既有主题选择、收藏、随机切换和归档入口。`paper` 与 `midnight` 恰好也是固定 schema 中的字符串，但其 Typebar 调色板独立定义，没有官方视觉等价证据，因此仍不算精确映射。用户也可自行创建、编辑和导入自己持有的网页自定义主题链接；这些能力不等于恢复官方全部命名预设。

`Scripts/check-theme-compatibility-audit.rb` 从固定 schema 重建 187 个身份，与机器清单及本机内置枚举逐项核对，并分别验证精确映射与相关替代，不允许后者冒充前者。门禁只证明盘点完整，不证明 187 个视觉主题已实现。后续若增加独立制作且获允许的精确主题，需要先有可核查的视觉、交互与授权证据，再更新逐项映射；不以程序生成的任意颜色冒充原主题。
