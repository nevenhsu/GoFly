# Licensing / 授權 / 许可

[English](#english) · [繁體中文](#繁體中文) · [简体中文](#简体中文)

## English

The requested policy is free use without mandatory attribution. **0BSD** is selected for newly authored material independently owned by the project. It permits use, copying, modification, and distribution for any purpose, with or without a fee, without an attribution condition. Research is the primary project purpose, not a noncommercial-only license condition. See the [OSI 0BSD terms](https://opensource.org/license/0bsd).

**Applied now:** the root [LICENSE](../LICENSE) covers only `README.md`, `README.zh-Hant.md`, `README.zh-Hans.md`, `docs/AI-INSTALL.md`, and this file. This change does not establish 0BSD licensing for app source code or a combined binary.

| Existing material | Current license / source | Release implication |
| --- | --- | --- |
| LocalGo-derived files from StikDebug | [AGPL-3.0](../app/GoFly/Legal/AGPL-3.0.txt); [provenance](../app/GoFly/Legal/UPSTREAM-LOCALGO.md) | Preserve upstream license/notices and meet applicable source-distribution obligations. |
| Mac app read-only device boundary | Authored for GoFly in `app/GoFlyMac/Bridge/Device/gofly_device.py`; uses pinned `pymobiledevice3==11.31.0` (GPL-3.0-or-later per wheel metadata) | No LocalGo code or license is bundled for this boundary. |
| New GoFly app's adapted/native components | [AGPL-3.0](../app/GoFly/Legal/AGPL-3.0.txt); [source notices](../app/GoFly/Legal/SOURCES.txt) | Retain the existing notices; a new app identifier does not remove upstream obligations. |
| Mac app's `pymobiledevice3` | GPL-3.0-or-later; [pinned PyPI release](https://pypi.org/project/pymobiledevice3/11.31.0/) and source repository `https://github.com/doronz88/pymobiledevice3` | Preserve its license text under the bundled `.dist-info/licenses/`; review integration and source obligations before release. |
| Bundled CPython | CPython 3.14.6 arm64, PSF License Version 2; [pinned python-build-standalone release](https://github.com/astral-sh/python-build-standalone/releases/tag/20260610) | Source and license are linked from the release record and [Python 3.14 license page](https://docs.python.org/3.14/license.html). |
| Locked Python runtime dependencies | Exact names and versions in [`requirements.txt`](../app/GoFlyMac/requirements.txt); each wheel's declared SPDX expression/classifier, project URL, PyPI source, and bundled license-file path are listed in the DMG's `THIRD-PARTY-NOTICES.md` | Source is acquired from the pinned PyPI project release and/or its recorded upstream repository. The generated metadata inventory is publisher-supplied, not a complete legal audit; entries without a declaration and licenses needing review remain release blockers. |
| `pylzss==0.3.9` | LGPL-3.0-only per wheel metadata; [pinned PyPI release](https://pypi.org/project/pylzss/0.3.9/) | The corresponding `COPYING` and `COPYING.LESSER` files are retained in its bundled `.dist-info/licenses/`. |
| `idevice` FFI and other transitive dependencies | Partial exact provenance in [UPSTREAM-LOCALGO.md](../app/GoFly/Legal/UPSTREAM-LOCALGO.md); full audit pending | Do not infer a binary's license from current upstream or call the entire app attribution-free. |
| LocalDevVPN | Separately installed external app | This repository grants no license to redistribute or re-sign it. |

The local DMG build includes `GoFly.app`, `install.sh`, and a generated `THIRD-PARTY-NOTICES.md`. The notice file inventories every installed Python distribution using its wheel metadata and points to retained license files under the app bundle. Obtain corresponding source from the repository plus each pinned upstream release; a public release must provide a matching source archive and DMG checksum. The inventory does not replace checking exact license texts, the native FFI's transitive dependency licenses, Mac app source terms, or distribution obligations.

Before a public software release, classify original code, derivatives, bundled assets, and dependencies; verify ownership and exact dependency licenses; then apply 0BSD only where the project has the necessary rights. A wholly attribution-free distribution requires addressing every incompatible component through replacement or appropriate permission. Adding a root license cannot remove upstream obligations.

The repository is therefore **mixed-license**, with 0BSD applied to the listed new documents. Existing app licenses remain unchanged. Neither the new GoFly app nor a combined Mac/iPhone release has completed a license audit.

## 繁體中文

使用者要求「免費使用、無須署名」，因此新撰寫且由專案獨立持有權利的內容選用 **0BSD**，允許任何用途的使用、複製、修改與再散布，可收費或免費，沒有署名條件。研究是主要用途，不是僅限非商用的授權限制。正式條文見 [OSI 0BSD](https://opensource.org/license/0bsd)。

**本次套用範圍：**根目錄 [LICENSE](../LICENSE) 僅涵蓋三份根目錄 README、`docs/AI-INSTALL.md` 及本文；未將 App 原始碼或整合執行檔改授為 0BSD。

| 既有內容 | 目前授權／來源 | 發行影響 |
| --- | --- | --- |
| 衍生自 StikDebug 的 LocalGo 檔案 | [AGPL-3.0](../app/GoFly/Legal/AGPL-3.0.txt)；[來源紀錄](../app/GoFly/Legal/UPSTREAM-LOCALGO.md) | 保留上游授權／註記，履行適用的原始碼提供義務。 |
| Mac App 唯讀裝置邊界 | GoFly 自有的 `app/GoFlyMac/Bridge/Device/gofly_device.py`，使用固定版 `pymobiledevice3==11.31.0`（依 wheel metadata 為 GPL-3.0-or-later） | 此邊界不再打包 LocalGo 程式碼或授權。 |
| 新版 GoFly 的衍生／原生元件 | [AGPL-3.0](../app/GoFly/Legal/AGPL-3.0.txt)；[來源註記](../app/GoFly/Legal/SOURCES.txt) | 保留既有註記，新 App 識別碼不會消除上游義務。 |
| Mac App 的 `pymobiledevice3` | GPL-3.0-or-later；[固定 PyPI 版本](https://pypi.org/project/pymobiledevice3/11.31.0/)及來源庫 `https://github.com/doronz88/pymobiledevice3` | 保留 bundle `.dist-info/licenses/` 中的授權文字，發行前檢查整合與原始碼義務。 |
| 內建 CPython | CPython 3.14.6 arm64，PSF License Version 2；[固定 python-build-standalone 版本](https://github.com/astral-sh/python-build-standalone/releases/tag/20260610) | 原始碼與授權連結列於該 release 及 [Python 3.14 授權頁](https://docs.python.org/3.14/license.html)。 |
| 固定版 Python runtime 依賴 | 精確名稱與版本見 [`requirements.txt`](../app/GoFlyMac/requirements.txt)；DMG 的 `THIRD-PARTY-NOTICES.md` 列出各 wheel 宣告的 SPDX expression／分類、專案網址、PyPI 來源及 bundle 授權檔路徑 | 從固定 PyPI 版本及／或所記錄的上游來源庫取得原始碼。產生的 metadata 清單由套件發佈者提供，不等於完整法律稽核；缺少宣告或仍待檢視的授權皆是發行前阻礙。 |
| `pylzss==0.3.9` | 依 wheel metadata 為 LGPL-3.0-only；[固定 PyPI 版本](https://pypi.org/project/pylzss/0.3.9/) | bundle `.dist-info/licenses/` 保留對應的 `COPYING` 與 `COPYING.LESSER`。 |
| `idevice` FFI 及間接依賴 | [UPSTREAM-LOCALGO.md](../app/GoFly/Legal/UPSTREAM-LOCALGO.md) 記錄部分精確來源，完整稽核未完成 | 不以上游現況推定既有二進位授權，不宣稱整個 App 免署名。 |
| LocalDevVPN | 使用者另行安裝的外部 App | 此儲存庫不授予散布或重新簽名該 App 的權利。 |

本機 DMG 含 `GoFly.app`、`install.sh` 及產生的 `THIRD-PARTY-NOTICES.md`。notice 依 wheel metadata 列出每個已安裝 Python distribution，並指向 App bundle 內保留的授權檔。原始碼由儲存庫及每個固定上游版本取得；正式公開發行須同時提供對應原始碼封存檔與 DMG 校驗碼。該 metadata 清單不能取代精確授權文字、原生 FFI 間接依賴授權、Mac App 原始碼條款或散布義務的稽核。

正式軟體發行前需分類自有程式碼、衍生內容、隨附素材與依賴，核對權利歸屬及精確版本授權，再將有權授出的部分套用 0BSD。若要整包完全免署名，須逐一替換不相容元件或取得適當許可；新增根目錄授權無法消除上游義務。

目前為**混合授權**，上述新文件採 0BSD，既有 App 授權維持。新版 GoFly 或 Mac／iPhone 整合發行尚未完成授權稽核。

## 简体中文

用户要求“免费使用、无须署名”，因此新编写且由项目独立持有权利的内容选用 **0BSD**，允许任何用途的使用、复制、修改与再分发，可收费或免费，没有署名条件。研究是主要用途，不是仅限非商用的许可限制。正式条款见 [OSI 0BSD](https://opensource.org/license/0bsd)。

**本次应用范围：**根目录 [LICENSE](../LICENSE) 仅涵盖三份根目录 README、`docs/AI-INSTALL.md` 及本文；未将 App 源代码或整合可执行文件改为 0BSD。

| 现有内容 | 当前许可／来源 | 发布影响 |
| --- | --- | --- |
| 基于 StikDebug 的 LocalGo 文件 | [AGPL-3.0](../app/GoFly/Legal/AGPL-3.0.txt)；[来源记录](../app/GoFly/Legal/UPSTREAM-LOCALGO.md) | 保留上游许可／声明，履行适用的源代码提供义务。 |
| Mac App 只读设备边界 | GoFly 自有的 `app/GoFlyMac/Bridge/Device/gofly_device.py`，使用固定版 `pymobiledevice3==11.31.0`（按 wheel metadata 为 GPL-3.0-or-later） | 此边界不再打包 LocalGo 代码或许可。 |
| 新版 GoFly 的衍生／原生组件 | [AGPL-3.0](../app/GoFly/Legal/AGPL-3.0.txt)；[来源声明](../app/GoFly/Legal/SOURCES.txt) | 保留现有声明，新 App 标识符不会消除上游义务。 |
| Mac App 的 `pymobiledevice3` | GPL-3.0-or-later；[固定 PyPI 版本](https://pypi.org/project/pymobiledevice3/11.31.0/)及源代码库 `https://github.com/doronz88/pymobiledevice3` | 保留 bundle `.dist-info/licenses/` 中的许可文本，发布前检查整合与源代码义务。 |
| 内置 CPython | CPython 3.14.6 arm64，PSF License Version 2；[固定 python-build-standalone 版本](https://github.com/astral-sh/python-build-standalone/releases/tag/20260610) | 源代码与许可链接列于该 release 及 [Python 3.14 许可页](https://docs.python.org/3.14/license.html)。 |
| 固定版 Python runtime 依赖 | 精确名称与版本见 [`requirements.txt`](../app/GoFlyMac/requirements.txt)；DMG 的 `THIRD-PARTY-NOTICES.md` 列出各 wheel 声明的 SPDX expression／分类、项目网址、PyPI 来源及 bundle 许可文件路径 | 从固定 PyPI 版本及／或所记录的上游源代码库获取源代码。生成的 metadata 清单由软件包发布者提供，不等于完整法律审查；缺少声明或仍待检查的许可均是发布前阻碍。 |
| `pylzss==0.3.9` | 按 wheel metadata 为 LGPL-3.0-only；[固定 PyPI 版本](https://pypi.org/project/pylzss/0.3.9/) | bundle `.dist-info/licenses/` 保留对应的 `COPYING` 与 `COPYING.LESSER`。 |
| `idevice` FFI 及间接依赖 | [UPSTREAM-LOCALGO.md](../app/GoFly/Legal/UPSTREAM-LOCALGO.md) 记录部分精确来源，完整审查未完成 | 不根据上游现状推定现有二进制许可，不宣称整个 App 免署名。 |
| LocalDevVPN | 用户另行安装的外部 App | 此仓库不授予分发或重新签名该 App 的权利。 |

本地 DMG 包含 `GoFly.app`、`install.sh` 及生成的 `THIRD-PARTY-NOTICES.md`。notice 根据 wheel metadata 列出每个已安装 Python distribution，并指向 App bundle 内保留的许可文件。源代码从仓库及每个固定上游版本获取；正式公开发布须同时提供对应源代码归档与 DMG 校验码。该 metadata 清单不能取代精确许可文本、原生 FFI 间接依赖许可、Mac App 源代码条款或分发义务的审查。

正式软件发布前需分类自有代码、衍生内容、附带素材与依赖，核对权利归属及精确版本许可，再将有权授出的部分应用 0BSD。若要整包完全免署名，须逐一替换不兼容组件或取得适当许可；新增根目录许可无法消除上游义务。

当前为**混合许可**，上述新文档采用 0BSD，现有 App 许可维持。新版 GoFly 或 Mac／iPhone 整合发布尚未完成许可审查。
