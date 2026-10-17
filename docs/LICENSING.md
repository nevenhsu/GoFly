# Licensing / 授權 / 许可

[English](#english) · [繁體中文](#繁體中文) · [简体中文](#简体中文)

## English

The requested policy is free use without mandatory attribution. **0BSD** is selected for newly authored material independently owned by the project. It permits use, copying, modification, and distribution for any purpose, with or without a fee, without an attribution condition. Research is the primary project purpose, not a noncommercial-only license condition. See the [OSI 0BSD terms](https://opensource.org/license/0bsd).

**Applied now:** the root [LICENSE](../LICENSE) covers only `README.md`, `README.zh-Hant.md`, `README.zh-Hans.md`, `docs/AI-INSTALL.md`, and this file. This change does not establish 0BSD licensing for app source code or a combined binary.

| Existing material | Current license / source | Release implication |
| --- | --- | --- |
| LocalGo derived from StikDebug | [AGPL-3.0](../app/LocalGo/LICENSE); [provenance](../app/LocalGo/UPSTREAM.md) | Preserve upstream license/notices and meet applicable source-distribution obligations. |
| Device boundary copied into the Mac app | The build script copies LocalGo's `localgo_device.py` and license | Bundling this boundary does not make it 0BSD. |
| New GoFly app's adapted/native components | [AGPL-3.0](../app/GoFly/Legal/AGPL-3.0.txt); [source notices](../app/GoFly/Legal/SOURCES.txt) | Retain the existing notices; a new app identifier does not remove upstream obligations. |
| Mac prototype's `pymobiledevice3` | GPL-3.0 per the [dependency record](../app/LocalGo/UPSTREAM.md) | Preserve its terms; assess the actual distribution/integration before release. |
| Bundled Noto Sans TC font | [OFL-1.1 notice](../app/GoFlyMac/Sources/GoFlyMac/Resources/NotoSansTC-OFL.txt) | Keep the font license and notices with the font. |
| `idevice` FFI and other transitive dependencies | Partial exact provenance in [UPSTREAM.md](../app/LocalGo/UPSTREAM.md); full audit pending | Do not infer a binary's license from current upstream or call the entire app attribution-free. |
| LocalDevVPN | Separately installed external app | This repository grants no license to redistribute or re-sign it. |

Before a software release, classify original code, derivatives, bundled assets, and dependencies; verify ownership and exact dependency licenses; then apply 0BSD only where the project has the necessary rights. A wholly attribution-free distribution requires addressing every incompatible component through replacement or appropriate permission. Adding a root license cannot remove upstream obligations.

The repository is therefore **mixed-license**, with 0BSD applied to the listed new documents. Existing app licenses remain unchanged. Neither the new GoFly app nor a combined Mac/iPhone release has completed a license audit.

## 繁體中文

使用者要求「免費使用、無須署名」，因此新撰寫且由專案獨立持有權利的內容選用 **0BSD**，允許任何用途的使用、複製、修改與再散布，可收費或免費，沒有署名條件。研究是主要用途，不是僅限非商用的授權限制。正式條文見 [OSI 0BSD](https://opensource.org/license/0bsd)。

**本次套用範圍：**根目錄 [LICENSE](../LICENSE) 僅涵蓋三份根目錄 README、`docs/AI-INSTALL.md` 及本文；未將 App 原始碼或整合執行檔改授為 0BSD。

| 既有內容 | 目前授權／來源 | 發行影響 |
| --- | --- | --- |
| 衍生自 StikDebug 的 LocalGo | [AGPL-3.0](../app/LocalGo/LICENSE)；[來源紀錄](../app/LocalGo/UPSTREAM.md) | 保留上游授權／註記，履行適用的原始碼提供義務。 |
| 複製進 Mac App 的裝置邊界 | 建置腳本複製 LocalGo 的 `localgo_device.py` 及授權 | 打包不會使其變成 0BSD。 |
| 新版 GoFly 的衍生／原生元件 | [AGPL-3.0](../app/GoFly/Legal/AGPL-3.0.txt)；[來源註記](../app/GoFly/Legal/SOURCES.txt) | 保留既有註記，新 App 識別碼不會消除上游義務。 |
| Mac prototype 的 `pymobiledevice3` | [依賴紀錄](../app/LocalGo/UPSTREAM.md)記載 GPL-3.0 | 保留條款，依實際散布／整合方式確認發行要求。 |
| 隨附 Noto Sans TC 字體 | [OFL-1.1](../app/GoFlyMac/Sources/GoFlyMac/Resources/NotoSansTC-OFL.txt) | 字體須附原授權與註記。 |
| `idevice` FFI 及間接依賴 | [UPSTREAM.md](../app/LocalGo/UPSTREAM.md) 記錄部分精確來源，完整稽核未完成 | 不以上游現況推定既有二進位授權，不宣稱整個 App 免署名。 |
| LocalDevVPN | 使用者另行安裝的外部 App | 此儲存庫不授予散布或重新簽名該 App 的權利。 |

軟體發行前需分類自有程式碼、衍生內容、隨附素材與依賴，核對權利歸屬及精確版本授權，再將有權授出的部分套用 0BSD。若要整包完全免署名，須逐一替換不相容元件或取得適當許可；新增根目錄授權無法消除上游義務。

目前為**混合授權**，上述新文件採 0BSD，既有 App 授權維持。新版 GoFly 或 Mac／iPhone 整合發行尚未完成授權稽核。

## 简体中文

用户要求“免费使用、无须署名”，因此新编写且由项目独立持有权利的内容选用 **0BSD**，允许任何用途的使用、复制、修改与再分发，可收费或免费，没有署名条件。研究是主要用途，不是仅限非商用的许可限制。正式条款见 [OSI 0BSD](https://opensource.org/license/0bsd)。

**本次应用范围：**根目录 [LICENSE](../LICENSE) 仅涵盖三份根目录 README、`docs/AI-INSTALL.md` 及本文；未将 App 源代码或整合可执行文件改为 0BSD。

| 现有内容 | 当前许可／来源 | 发布影响 |
| --- | --- | --- |
| 基于 StikDebug 的 LocalGo | [AGPL-3.0](../app/LocalGo/LICENSE)；[来源记录](../app/LocalGo/UPSTREAM.md) | 保留上游许可／声明，履行适用的源代码提供义务。 |
| 复制进 Mac App 的设备边界 | 构建脚本复制 LocalGo 的 `localgo_device.py` 及许可 | 打包不会使其变成 0BSD。 |
| 新版 GoFly 的衍生／原生组件 | [AGPL-3.0](../app/GoFly/Legal/AGPL-3.0.txt)；[来源声明](../app/GoFly/Legal/SOURCES.txt) | 保留现有声明，新 App 标识符不会消除上游义务。 |
| Mac prototype 的 `pymobiledevice3` | [依赖记录](../app/LocalGo/UPSTREAM.md)记载 GPL-3.0 | 保留条款，根据实际分发／整合方式确认发布要求。 |
| 附带 Noto Sans TC 字体 | [OFL-1.1](../app/GoFlyMac/Sources/GoFlyMac/Resources/NotoSansTC-OFL.txt) | 字体须附原许可与声明。 |
| `idevice` FFI 及间接依赖 | [UPSTREAM.md](../app/LocalGo/UPSTREAM.md) 记录部分精确来源，完整审查未完成 | 不根据上游现状推定现有二进制许可，不宣称整个 App 免署名。 |
| LocalDevVPN | 用户另行安装的外部 App | 此仓库不授予分发或重新签名该 App 的权利。 |

软件发布前需分类自有代码、衍生内容、附带素材与依赖，核对权利归属及精确版本许可，再将有权授出的部分应用 0BSD。若要整包完全免署名，须逐一替换不兼容组件或取得适当许可；新增根目录许可无法消除上游义务。

当前为**混合许可**，上述新文档采用 0BSD，现有 App 许可维持。新版 GoFly 或 Mac／iPhone 整合发布尚未完成许可审查。
