# 五字母英语独立语料合同

`LANG-ENGLISH-FIVE-55`，起点 cecd0777837341b729ba0a1c70e2e825ce2bf164。默认五字母池从 40 扩到 201 项，1k 档移除 europeanScaleLexicon 编号拼接，改为 1,000 个字典字面词形。原 40 个自写词全部保留，基本池包含于本项目的 1k 选集。固定参考只读 wordle／wordle_1k 的聚合：201／1,000 项、全部长度 5、小写 ASCII 字母、无标点；不读取参考词值。

## 来源与编辑边界

独立 SCOWL 固定提交 `7e99edab8e32f9f9ea2b15f249ca8d4d67237410`（https://github.com/en-wl/wordlist），95 级、A／B／Z／C 拼写、variant level 1、普通类别、允许点及连字符的提取字节 SHA-256 `c8f999c724e322801d94348a90f940e28f8bbbd19e53a4ffed18346d83ae52ad`。提取后才筛出原样的五个小写 ASCII 字母。保留完整 SCOWL Copyright，SHA `090575a131b4260926c7a6b30a90aca0f5db5fbb5c46778e0c5855227bf6ebc3`。

wordfreq 3.1.1 wheel SHA `4b1c6ecffc6198be3396d5cf871c4423ca71c907c231348d352dd54d62b97473`；English member wordfreq/data/large_en.msgpack.gz SHA `dffae8066b78dce0a6667cf5f58e567054f902674667090a7ac8a8a44628b05c`。仅选有完整原词观察的词典形式，容量 8,241；按频率 band、SCOWL 最小级别及字面拼写排序，保留旧 40 词。Band 不是使用次数。没有改大小写、去重音、拼后缀、填充字符或复制参考选集。

准备器固定复用本项目 Scripts/prepare-english-large-corpus.py 的读取逻辑，其 SHA `94b7036c27bbff858fee1731a7925192aa39d3e6f96772ee16259cf66990523b`。该文件、原 English 450k／频率词库及其制品均保持；新增数据没有 Python／msgpack 运行依赖。五字母输入长度约束、Lazy 资格、语言 ID、引语路由和存储格式保持。旧 1k 的前两个合成词 qqqqq／qzaaa 仅作为已捕获历史提示测试，不进入新候选。

## 制品与署名

| 文件 | SHA-256 |
| --- | --- |
| Sources/Typebar/EnglishFiveLetterCorpus.generated.swift | 11e0bd3a7215fbadd22801cb4063a3ed062ac2467d92be5b9bdcf532801dbce9 |
| Resources/EnglishFiveLetterCorpusNotices.txt | 2f7247673678da0787cbb446ace1f76ecbb594e558d5ef162664414d4b500067 |
| Resources/EnglishFiveLetterCorpusSources.txt | 323c697094922c25a6821cda7641cf7d18a18782756b6b6d3f0e53cbd221969d |
| Compatibility/english-five-letter-corpus.json | 647cc3879b0eb123cfca2f57a0098c4ff52482f046b9e66d5023a8d87a9959b0 |

映射覆盖 1,000 个唯一词形，逐行记录 SCOWL 最小级别和整词频率 band；基本池的 201 项均在其中。新原生许可入口保留完整 SCOWL／WordNet／UKACD 等版权及完整 wordfreq 发行许可，改编选集标 CC BY-SA 4.0；About 的醒目 UK Advanced Cryptics Dictionary 名称及版权继续显示，说明文字覆盖五字母与 450k。两份新资源随手工包逐字节核对。仅有字典、历史频率和形状证据，不能声称 Wordle 答案资格、当下频率或原词值／顺序／难度／分布／语言质量相同。

## 可复现与行为证据

Scripts/prepare-english-five-letter-corpus.py 支持 --self-test、--check-bundled 和显式 --scowl-root／--wordfreq-wheel 的 --check。三制品及整个 manifest 由代码内不可变 SHA 固定，不接受修改 manifest 自行重建信任。固定源完整重建通过；normal／-O 三项准备合同分别通过。隔离正常样本通过，删来源行、改 manifest、原生模板和共享读取器四类篡改在 -O 下全部拒绝，记录 /tmp/typebar-english-five-letter-mutations-20261030.json。

先行 /tmp/typebar-english-five-letter-red-20261030.log 一项三处失败（基础池 40／201、唯一数 40／201、旧基础池不在合成 1k 中），XCTest 1.293 秒、驱动 24.689 秒，输入保持。实现后 /tmp/typebar-english-five-letter-focused-20261030.log 的 20 项全部通过：XCTest 12.638 秒、驱动 102.623 秒，输入保持。覆盖两池全部候选的实际工厂／删除／No Space／Backwards／重复、跨字段无空格、既有 Lazy 资格、来源／完整署名、旧 JSON／模型／回放，以及原 450k 和两种五字母选择的隐藏生产页面。真实 About／许可像素读取亦通过，没有启动 Typebar 主程序。

另已目视检查并独立保存本批实际 About 捕获 /tmp/typebar-english-five-letter-about-20261030.png，SHA `54666e67a80bc1a9cfb46f1a0300dd07960e384db9d2f4d116b0854457f223b3`；五字母／450k 的来源说明、醒目 UKACD 名称及版权可见。这是隐藏组件捕获，不是完整产品窗口、系统字体或辅助功能验收。

扩大 /tmp/typebar-english-five-letter-regression-20261030.log 已实际退出成功：1,234 项通过、零失败／运行时跳过，XCTest 855.901 秒、驱动 871.672 秒，非 Markdown 输入保持；同前缀 .evidence.log 正式确认 146 项必需源方法通过。覆盖默认混排／Polyglot、通用多语生成、弱点、语言宿主、候选／续批、结果／回放及全部既有必需来源检查。此集合不是完整客户端套件；此前完整客户端 6,870 项和服务端 501 项属于旧数据基线，见 CLIENT_BASELINE_20261030.md，不外推本批。

/tmp/typebar-english-five-letter-package-20261030.log 的 Debug 包、严格签名、31 份许可／来源资源逐字节核对及原创性边界检查通过，驱动 43.254 秒，输入保持；未启动主程序。此边界检查不是穷尽的原创性证明。人工目录新增两项并保留待验收，结构检查通过（1,458 个唯一场景）。推送前 main 仍为 8c52fb13028f82fd8e8718d55cb7ed65463b034e，开发分支仍为本批起点，无开放 PR；Actions 总数 826、最新 39118939684 成功。本批本机验证后只合并推送开发分支一次，未更改门禁或通知设置。

只读结构复核 /tmp/typebar-english-five-letter-scale-audit-20261030.json：TypingEngine SHA `d763249482238ea6cf67db68549bec1c710a4a013c0e0a26b8a7734086c96025`，直接具名 ScaleLexicon 路由从 123 降为 122，声明位置从 1,090,989 降为 1,089,989。它不覆盖匿名／其他构造器、全部基础池或实际词汇质量；不能将剩余位置当成唯一词数。实体键盘／IME、VoiceOver、语言审校和完整 Release／最低设备性能仍开放，整体 goal active。
