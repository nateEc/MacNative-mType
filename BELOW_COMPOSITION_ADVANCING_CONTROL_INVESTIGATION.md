# 下方候选行：VT／FF／NEL 的实际缺字框与回映缺口

起点 3e8cb915d301aaec1db8e46e92380f876431ce83，参考固定 91bd24bb8513785c7364cbea29296ff7adafac41。只读检查 frontend/src/ts/components/pages/test/CompositionDisplay.tsx，候选文本进入普通 div；不复制其实现或资产。延续 BELOW_COMPOSITION_CONTROL_WHITESPACE_CONTRACT.md 中明确未覆盖的三种控制符，不能沿用 CR／U+2028／U+2029 的零宽处理。

新增 CompositionWhitespaceBrowserTests.testAdvancingControlsKeepBrowserRowAndNativeSourceRectangles，使用自有九段文字、禁止网络的本地 WebKit 和不可见原生宿主：VT U+000B、FF U+000C、NEL U+0085 分别置于 a／b 中间、两侧空格及行首。浏览器验证 white-space:normal、实际字体 28px monospace，再读每个 UTF-16 范围几何；原生保持同一字段身份、sourceText、辅助功能原文，并核对行高和原始范围矩形。

首个探针错误地未在 CSP 放行自有内联样式，实际落回默认 16px 字体；该次仅定位问题，不能作为指定字体的最终证据。已改为同时放行自有内联 script／style，default-src 仍为 none，并断言计算字体；普通旧探针不改变字体。该修正属于测试测量条件，不是产品修复。

固定字体的 /tmp/typebar-below-advancing-control-font-red-20261030-driver.py/.json/.log 最终退出 1，一项方法九处失败，driver 25.653 秒，输入保持。浏览器三类控制符都有正的约 17 点进位，所有字符在同一行；原生 VT 的三种排列均无法给出 markedScreenRect，FF 和 NEL 的六种排列均把字段 33 点行高变为 66 点。FF／NEL 所给矩形还横跨行尾，不能将非空矩形当作正确几何。

随后加入实际 WebKit 快照而不打开窗口。/tmp/typebar-below-advancing-control-pixels-red-20261030-driver.py/.json/.log 重现同样九处失败，native 2.864 秒、driver 30.060 秒，输入指纹保持。/tmp/typebar-below-advancing-control-webkit-20261030.png 已实际查看：三种字符都画出矩形缺字框，a／b 在同一行。这是可见墨迹，不是纯空格进位，故不能删字符、统一换空格或直接采用不同的可见控制符图标来消掉断言。

产品代码未修改，复现测试仍为红色，未提交或推送。下一步需验证原生缺字 glyph 的绘制／排版策略，使显示、测量及 UTF-16 回映使用同一布局；不能仅把 markedScreenRect 返回值伪造成非空，也不能仅压低 sizeThatFits 掩盖实际多行。先用不可见实验验证，再修改生产控件并扩大原生回归。原文、候选确认／取消、计分与历史必须保持。

本批不升级 compositionDisplay 的部分兼容、不宣称全部浏览器／字体／实体 IME 等价。没有启动 Typebar 主应用或更改工作流／通知；开发分支仍为上批提交。

## 原生布局实验与当前实现

以下为同一会话的有界决策复核，不是独立审查。主张：只对三个已测字符保留原文并使用真实缺字框排版，显示与 IME 查询不能分离。约束是有墨迹、有进位、不制造额外行、UTF-16 回映不变，其他字符继续原布局行为。

本机 SDK NSLayoutManager.h 的 delegate 合同允许 shouldUseAction 覆盖控制字符动作，并以 boundingBoxForControlGlyphAt 提供 whitespace 进位。先试 shouldGenerateGlyphs 改写 glyph／属性，实际丢失后续字且仍存在换行，已排除，没有进入产品。/tmp/typebar-control-action-prototype-20261030.swift 的原文保留方案让三个 a／control／b 均为一行 33 点，宽 51.926，控制矩形宽 17.309；此时尚无绘制证明。

Sources/Typebar/BelowCompositionControlLayout.swift 采用后者：布局管理器自身作为弱 delegate，避免返回测量对象后 delegate 提前释放。三类字符改成有自定义宽度的排版动作，以字体 glyph 0 的真实 advance 度量并直接绘制轮廓；原字符串不替换为符号。Cell 的绘制、尺寸以及 Field 的 marked／insertion 测量使用相同布局类。普通候选继续用原 NSLayoutManager 测量、Cell 的 super 绘制／尺寸；非目标控制符不会取得自定义宽度。显式保活文本存储，保留颜色与背景语义。

第一版几何通过的 /tmp/typebar-below-advancing-control-focused-20261030.log 为 7 项通过（native 6.351 秒、driver 89.617 秒，输入稳定），但新增像素断言后 /tmp/typebar-below-advancing-control-ink-20261030.log 九处无墨迹失败，不能用前次绿色声称绘制正确。实际字体探针 /tmp/typebar-missing-glyph-font-probe-20261030.swift 证明 SF Mono 的 glyph 0 有进位但 path=nil；Menlo-Regular 和系统比例字体有真实轮廓。因此仅主字体无轮廓时回退 Menlo-Regular（不可用则系统字体），宽度与绘制同步选用这一字体。仍不是 U+FFFD、可见控制符图标或人为描边矩形。

回退后 /tmp/typebar-below-advancing-control-ink-verified-20261030.log 的 7 项通过（native 6.388 秒、driver 44.077 秒、输入稳定）。新像素检查截取每个实际候选矩形的内部列，要求存在不透明文字墨迹；为可视检查在测试字段明确使用黑字白底，实际读取 /tmp/typebar-below-advancing-control-native-12-20261030.png 已看到 a／矩形框／b。生产颜色未固定为黑白。

扩大到 28 点等宽／40 点系统字体、emoji＋组合附加符和阿拉伯／希伯来混合文字后发现 TextKit 与 NSCell 回退字体行高有 2 点差异（35／33、50／48）。不把该差异掩盖成字体等同：测试改为检查实际首尾字形处于同一行，字段高度等于实际行高，三类控制符都有正确源范围与正宽矩形、两侧插入坐标不同，组合字符内部查询回映完整字素。这证明没有制造新行，但不是所有字体逐像素等价证明；相关度量差异仍开放。

期间白底绘制补丁最初把可选 backgroundColor 当作非可选，编译失败（/tmp/typebar-below-advancing-control-final-focused-20261030.log）；已用可选绑定修正，没有将编译错误当运行行为。最终 /tmp/typebar-below-advancing-control-row-verified-20261030-driver.py/.json/.log 共 8 项、0 失败／跳过，driver 30.776 秒，native_exit=0，inputs_unchanged=true。范围含旧零宽控制、空白与更新／取消测试，以及新的浏览器、墨迹、字体、双向与字素检查。

纯控制符／全空白候选仍必须补测：旧默认字体探针曾记录单独 FF 的 div 没有内容高度，不能把夹在普通文字中的缺字框规则直接推广到整个候选。窄行、缩放、动态外观和更多字体、全部生产组合宿主、146 项必需源码合同、最终打包与实体 IME 仍待验证。当前实现尚未提交／推送或升级矩阵；没有可见 Typebar 实例。

## 纯控制符与整个文本节点的空白

独立固定 28px monospace 的 /tmp/typebar-composition-control-only-probe-20261030.swift 实际返回 19 条结果，保存于 /tmp/typebar-composition-control-only-geometry-20261030.json，全部验证计算字体。单个／多个 FF、FF 与空格／tab／CR／LF 及重复 CR 的全 ASCII 空白节点，innerText 为空、div 高度和所有单位范围宽均为 0。VT、NEL 单独仍有正宽缺字框；FF 与它们、U+2028／U+2029、U+200B、NBSP 或普通文字混合时仍有正宽。因此空内容判断取整个节点，不能对所有 FF 一律删去。

新增 testControlOnlyCandidatesAgainstActualBrowserEmptyContentAndNativeRanges，将 19 条预期逐一断言，并实际挂载同一不可见原生候选字段。先行 /tmp/typebar-below-control-only-red-20261030-driver.py/.json/.log 一项方法 23 处失败，native 3.263 秒、driver 26.033 秒、inputs_unchanged=true。失败包括全空白却显示缺字框、虚假字符矩形／插入点，及 CR 空白段仍被当作可见空间；浏览器预期验证通过。

投影现在仅在整个原文都是 U+0009／000A／000C／000D／0020 时跳过显示，仍创建原始 UTF-16 源范围，sourceText／辅助功能标签不改。这样空行保留既有原生一行占位，却不为不可见内容捏造矩形。VT／NEL、NBSP 及其他零宽字符不会被纳入这一条件；混合候选保持前述缺字框规则。

最终 /tmp/typebar-below-control-only-focused-20261030-driver.py/.json/.log 共 9 项、0 失败／跳过，native 10.192 秒、driver 49.532 秒，输入保持。范围包含 19 条新浏览器／原生场景，原先九条缺字框及墨迹、两种字体与字素／双向几何，以及既有零宽控制／空白／取消测试。不是所有字体或实际 IME 的完整证明。

随后启动 /tmp/typebar-below-advancing-control-regression-20261030-driver.py（原会话 75411；启动时 driver PID 43832、Swift PID 43846，ps 已确认存活）。范围为组合输入测试类、Below 字段、提示装配／换行、许可宿主以及全部 146 项固定源码必需方法，结束后自动运行正式来源证据检查。运行期间冻结全部非 Markdown 文件。启动记录不能作为通过证据；必须沿该实际会话等待终态，不能因日志缓冲或一次观察超时重跑。尚未执行当前变更的最终包检查或推送。

续检同一会话仍运行：ps 确认原 driver 43832、Swift 43846 及 XCTest 43953 存活，日志从 CustomGeneratedSelection 推进至 LocalFontCommandSourceTests 通过。独立重算全部 1,422 个非 Markdown 文件的成员及 SHA-256，与该次启动记录完全相同；未修改代码或资源、未另开原生任务。新增 TST-BELOW-ADVANCING-CONTROL-65 自动／人工追踪行，人工仍待验收，扩大回归仍写进行中；Ruby 清单检查 1,471 个唯一场景通过。这些中途记录不是最终门禁结果。

再次沿 75411 续检，原进程仍存活，日志已明确 ArabicBangla／ArabicGujarati1k 的生产宿主分别 28.741／28.454 秒通过。后续输出停在半行时，只做 1 秒、10ms 间隔的只读 sample；/tmp/typebar-below-advancing-control-live-sample-20261030.txt 实际调用栈已推进至 testArabicMixedDirectionProductionCompositionPreservesJoinedRun，以及 checkProductionHost 的布局／RunLoop 刷新。确认是仍在执行后续宿主而不是凭旧状态文件猜测存活；未重启、终止或追加测试。没有最终通过或来源证据终态，保持待结果。

后续同一 Swift PID 43846 持续存活，日志确认 MyanmarBurmese、Nepali1k、Nepali 的相反方向混排生产宿主分别 28.240／28.446／28.894 秒通过，并开始 Sanskrit 场景。预先从已验证包驱动复制出 /tmp/typebar-below-advancing-control-package-20261030-driver.py，仅准备文件，没有执行；必须等当前回归终态后再串行打包。此阶段仍只读代码，未改非 Markdown 输入、提交或推送。

## 扩大回归终态

沿同一 75411 等待至原 driver／Swift 进程成功退出，没有另起回归。/tmp/typebar-below-advancing-control-regression-20261030-driver.py/.json/.log 最终 395 项、0 失败／跳过，native 1419.120 秒、driver 1430.496 秒，inputs_unchanged=true、native_exit=0、evidence_exit=0。同名 .evidence.log 正式确认全部 146 项必需源码方法通过；其中 42 项实际生产组合宿主全部通过，947.969 秒。不是全客户端、全部服务或实体 IME 门禁完成，也不把布局计数当作 Release 性能基准。

终态后才串行执行已准备的包驱动，结果待另记。推送前只读检查 main=8c52fb13028f82fd8e8718d55cb7ed65463b034e、开发分支=3e8cb915d301aaec1db8e46e92380f876431ce83，开放 PR 0；Actions 总数仍 826，最新 39118939684 completed/success 属于该 main。仅在本批全部必要本地检查通过后一次推送开发分支；不改通知／工作流、不推 main 或新建 PR。

最终 /tmp/typebar-below-advancing-control-package-20261030-driver.py/.json/.log 退出 0，46.544 秒、inputs_unchanged=true。Debug 应用严格签名、全部 41 份 txt 资源逐字节比较及固定参考原创性边界检查通过；无主应用启动。EXIT trap 清理临时应用，不将日志中的临时路径当交付安装包。人工清单最终 1,471 个唯一场景通过结构审计；TST-BELOW-ADVANCING-CONTROL-65 仍为待实体验收。395 项扩大与包检查之间只有 Markdown 追踪更新，生产代码／测试／资源未变。
