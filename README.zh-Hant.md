# GoFly — 開發中

[English](README.md) · **繁體中文** · [简体中文](README.zh-Hans.md)

用於研究 iOS 模擬定位、裝置連線與原生 App 操作流程的 Mac／iPhone 專案。預定使用方式：取得 Mac App、開啟 GoFly、以 USB 連接 iPhone，再由 Mac 安裝手機 App。

**狀態：** 尚無公開 DMG。Mac App 可完成 USB 首次安裝，並可重新簽署已安裝的 App；手機完整驗收與可攜 DMG 仍待完成。預覽資料不代表裝置實際發生過操作。

## 目錄

- [設備與環境](#設備與環境)
- [安裝](#安裝)
- [開發版建置](#開發版建置)
- [研究操作](#研究操作)
- [交給 AI 協助安裝](#交給-ai-協助安裝)
- [常見問題](#常見問題)
- [文件與原始碼](#文件與原始碼)
- [授權](#授權)

## 設備與環境

| 項目 | 需求 |
| --- | --- |
| 電腦 | 需要 macOS 15 以上的 Mac。從原始碼建置時，macOS 也須符合所用 Xcode 的需求。目前不支援 Windows／Linux。 |
| 手機 | 需要 iOS 26 以上的 iPhone。這不代表所有機型及系統版本均已驗證。 |
| 連接線 | 首次安裝需要可傳輸資料的 USB 線。裝置完成核對後，後續重新簽署也可走 Wi-Fi。 |
| 開發工具 | Xcode、所需 iOS SDK 與 Swift 工具鏈；Mac 套件需要 Swift 6.2 以上。 |
| Apple 帳號 | 開發簽署使用自己的 Apple 帳號，在 Xcode 登入。支援免費 Personal Team。 |
| 手機設定 | 解鎖 iPhone、信任 Mac，並啟用開發安裝所需的[開發者模式](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)。 |
| 連線 App | 裝置通道需要另行在 iPhone 安裝 [LocalDevVPN](https://apps.apple.com/us/app/localdevvpn/id6755608044)。 |
| 網路 | Apple 簽署、依賴下載、地圖／搜尋及必要裝置準備下載均需要網路。 |

GoFly 以免費使用為目標，Apple 簽署限制仍適用：免費 Personal Team 描述檔通常七天到期，之後需要重新簽署。請以本次可驗證的實際有效期為準，詳見 [Apple 帳號說明](https://developer.apple.com/help/account/basics/about-your-developer-account)。

## 安裝

首次安裝由 Mac App 經 USB 執行：

1. 開啟 GoFly，完成環境檢查及簽署帳號設定。
2. 以 USB 連接 iPhone，解鎖並在手機完成信任、開發者模式確認；在 GoFly 選取並核對目標裝置。
3. 開始首次安裝。Mac 負責簽署與安裝手機 App、私密交付配對，以及自動準備並驗證實際需要的裝置支援項目；已備妥的重用。
4. 等待「安裝完成」。必須同時驗證 App 部署、配對匯入及必要裝置準備，不能只憑手機出現圖示判定成功。完成後可拔除 USB。
5. 在 iPhone 安裝／開啟 LocalDevVPN、啟用 VPN 通道，再開 GoFly。首次引導須通過實際 VPN 通道檢查才能繼續。

在裝置管理選取已核對的裝置可重新簽署同一個已安裝的 App；手動重新簽名入口仍保留。兩者都保留 App 資料，不是重新安裝。公開 DMG 尚未提供，請先使用下方開發版。

## 開發版建置

在已設定 Xcode 的 Mac，從儲存庫根目錄執行：

```sh
bash app/GoFlyMac/build-app.sh
open work/gofly-mac/GoFly.app
```

這會建立本機開發 App，並非可攜式 DMG。生成設定含本機工作目錄與 Python 路徑，未做發行簽署或 notarization。唯讀裝置檢查使用既有 `work/mac-setup-env/bin/python` 環境；沒有該環境仍可查看介面預覽，App 不會自動安裝依賴。

## 研究操作

GoFly 設計涵蓋地點選取、路線／GPX、搖桿移動、裝置服務準備及恢復 GPS。功能要求見[GoFly App 說明](app/GoFly/README.md)及 [iOS UI 設計規格](docs/IOS-UI-DESIGN.md)。

實驗時記錄 App 版本、iPhone 機型、iOS 版本、連線方式及實際結果。先在 Apple 地圖與另一個 App 核對模擬位置，再停止任務、恢復 GPS，並另外核對真實位置。安裝或配對成功不能代替 GPS 恢復驗證；背景執行、斷線重連、系統更新及重啟均需分別驗證。

研究是本專案的主要用途，不是 0BSD 的非商用限制。專案不接入 AnyGo／iToolab 服務，也不散布其程式碼、素材、憑證或金鑰。

## 交給 AI 協助安裝

已有 GoFly、要在實機測試時保留資料覆蓋更新，可直接使用 [iPhone 覆蓋安裝 prompt](docs/AI-INSTALL.md#ios-device-test-prompt)；共用流程會一併完成配對交接。

先提供 [AI 安裝操作說明](docs/AI-INSTALL.md#繁體中文)，再貼上：

```text
請先閱讀 README.zh-Hant.md 與 docs/AI-INSTALL.md，協助我在 Mac 和自己的
iPhone 設定 GoFly。先確認實際發行版本、目前能力與目標裝置，再依我的授權
執行可用的設定流程。如果只有預覽版，請明確說明限制。Apple 登入、雙重認證、信任、開發者
模式與 VPN 確認由我操作。保留既有 App 資料，逐步核對實際結果，最後回報
已完成項目、待我操作的步驟及阻礙。
```

## 常見問題

| 情況 | 處理方式 |
| --- | --- |
| 找不到 DMG | DMG 尚待發行；可從原始碼建置，不以第三方安裝包替代。 |
| 找不到 iPhone | 檢查 USB 資料線、解鎖／信任狀態、Xcode 裝置支援及選取的手機。 |
| 安裝／重新簽名按鈕停用 | 核對環境、所選裝置與待續交易；預覽不會寫入裝置。 |
| 手機 App 無法開啟 | 核對實際簽署到期時間，從 Mac 重新簽署；開發者模式不會延長簽名。 |
| LocalDevVPN 已連線，GoFly 仍無法繼續 | 核對實際 VPN 通道。設計提供連線檢查，停止送點後可重置通道。 |
| 寫入途中中斷 | 先核對同一裝置與本次交易，再決定是否重試；結果不明須如實回報並保留資料。 |

## 文件與原始碼

| 路徑 | 用途 |
| --- | --- |
| [app/GoFly/README.md](app/GoFly/README.md) | 原生 iOS App，含英文、繁中、簡中資源。 |
| [app/GoFlyMac/README.md](app/GoFlyMac/README.md) | Mac 能力及開發檢查。 |
| [app/GoFlyMac/DEVELOPMENT.md](app/GoFlyMac/DEVELOPMENT.md) | 已確認的 Mac 安裝及裝置管理要求。 |
| [docs/AI-INSTALL.md](docs/AI-INSTALL.md) | 三語 AI 代理安裝操作說明。 |
| [docs/LICENSING.md](docs/LICENSING.md) | 0BSD 範圍、既有上游授權與發行條件。 |
| `work/` | 不納入版本控制的本機研究證據、建置產物及裝置實驗，不是公開發行內容。 |

README 提供英文、繁體中文、簡體中文。App 本地化同樣以三語及英文 fallback 為要求；文件翻譯不代表 UI 本地化或實機驗證已全部完成。

## 授權

新撰寫、獨立持有權利的內容選用 **0BSD**，允許免費使用、修改、再散布，無須署名。[LICENSE](LICENSE) 涵蓋三份根目錄 README 及 `docs/` 的指南，不改授既有 App 程式碼或依賴授權。可查閱 [0BSD 官方條文](https://opensource.org/license/0bsd)。

LocalGo／StikDebug、重用的 Mac 裝置邊界及新版 GoFly 的[衍生／原生元件](app/GoFly/Legal/SOURCES.txt)保留 AGPL-3.0 註記。Mac App 使用 GPL-3.0 的 `pymobiledevice3`。整合發行的 App 不能宣稱全部免署名，詳見[授權說明](docs/LICENSING.md)及[上游來源](app/LocalGo/UPSTREAM.md)。

文件結構參考 [Best-README-Template](https://github.com/othneildrew/Best-README-Template) 的專案介紹、必要條件、安裝、使用與授權章節，依研究專案重新撰寫。
