# LocalGo 首次 Mac 設定

這是 LocalGo prototype 的 USB CLI，不是新版 GoFly 安裝器。GoFly 預定 DMG 流程、Mac／iPhone 需求與三語使用者文件見[專案 README](../../../README.zh-Hant.md)；AI 代理執行前請讀[安裝操作說明](../../../docs/AI-INSTALL.md)。目前 Mac GUI 仍為唯讀／預覽，沒有公開 DMG 發行網址。

此工具將自己的 LocalGo 簽署版本安裝至指定 USB iPhone，建立獨立 RP 配對身分，並透過 USB 自動交付至 App 私有空間。不需要手動輸入 UDID 或搬配對檔；沒有常駐 Mac tunnel，也不連接 AnyGo／iToolab 服務。

目前使用免費 Apple ID／Personal Team，手機另裝並啟用 LocalDevVPN。**Apple 官方說明免費 Personal Team 預設有七日佈建限制；請以工具顯示的實際核發有效期為準，屆期需續簽重裝。首次 Mac 設定後獨立操作，不表示永久免續簽。** 開發者模式不能解除簽署期限。

## Mac App 後續裝置管理需求

2026-10-17 使用者確認：Mac App 裝置管理選擇裝置並成功連線後，USB／Wi-Fi 均自動重新簽名 GoFly，現有手動重新簽名 flow 保留，且應保留 App 資料。這是後續 GUI 開發要求，見 [Mac 開發規格](../../GoFlyMac/DEVELOPMENT.md)；不代表本 CLI 已加入 Wi-Fi 簽署／安裝能力，也不改變下方首次設定的 USB 限制與停止／清除模擬定位等前置條件。本輪只更新 docs，沒有實際簽名或寫入裝置。

## 最新安裝完成條件（待實作）

2026-10-17 最新設計：Mac 在部署 App、匯入配對的同一安裝流程，依實際需要自動完成 DDI 等裝置準備與驗證；已備妥則重用／略過，UI 只顯示「準備裝置」。完成後才能交接，不增加 iOS 下載／資料設定或 Mac U19 頁。現有 CLI 成功回報仍只證明 App／配對匯入，不代表已達此新門檻；實作要求見 [Mac 開發規格](../../GoFlyMac/DEVELOPMENT.md)。

## 首次執行

1. 在 Xcode → Settings → Apple Accounts 登入自己的 Apple ID，確認 Personal Team 可用，並自行接受 Apple 要求的條款。
2. USB 連接並解鎖自己的 iPhone，信任此 Mac，手機啟用開發者模式。
3. 在 iPhone 從 App Store 安裝 [LocalDevVPN](https://apps.apple.com/us/app/localdevvpn/id6755608044)。不要用免費帳號重新簽它的 IPA，因為 Personal Team 不支援其 Network Extension 權限。
4. 從專案根目錄建立專用環境：

```sh
python3 -m venv work/mac-setup-env
work/mac-setup-env/bin/python -m pip install -r app/LocalGo/MacSetup/requirements.txt
```

先做唯讀前置檢查。只連接一台 USB iPhone 且 Xcode 只有一個免費 Personal Team 時，會自動選擇；有歧義便停止，不會選其他付費團隊。

```sh
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  work/mac-setup-env/bin/python app/LocalGo/MacSetup/localgo_setup.py setup \
  --output work/localgo-signed
```

實際執行：

```sh
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  work/mac-setup-env/bin/python app/LocalGo/MacSetup/localgo_setup.py setup \
  --output work/localgo-signed --execute --allow-provisioning-updates
```

`--allow-provisioning-updates` 允許 Xcode 聯絡 **Apple** 管理你的開發簽署資料，可能建立開發憑證及裝置描述檔，不會撤銷其他憑證。密碼、雙重認證、條款或系統鑰匙圈提示須由使用者在 Apple／macOS 介面完成。工具不接收 Apple ID 密碼。

自動選擇不適用時，可加 `--device <完整USB識別碼> --team <你的TeamID>`。可用 `devices --show-identifiers` 在本機查看 USB 目標，勿把配對檔貼到聊天。已有自己的開發簽署 `.app` 時，可跳過建置：

```sh
work/mac-setup-env/bin/python app/LocalGo/MacSetup/localgo_setup.py install \
  --device <USB識別碼> --team <TeamID> --app <StikDebug.app完整路徑> --execute
```

`install` 未加 `--execute` 只檢查。既有配對會先驗證並重用；驗證失敗時不默默換身分，明確指定 `--repair` 才重建。再次執行設定／續簽前，先在 LocalGo 停止並清除模擬定位；安裝更新不代表定位已恢復。

## 手機獨立操作與驗收（現有 CLI 行為）

現有 CLI 回報「安裝及匯入成功」後，在手機啟用 LocalDevVPN，再開 LocalGo → 啟動，目前程式仍會下載及掛載 DDI。這是現有行為，尚未符合上方 Mac 安裝完成前準備的最新要求；後續 GUI 不應把此手機下載當成額外步驟。之後斷開 USB、停止 Mac 工具，在 Apple 地圖與另一個 App 驗證位置，再回 LocalGo 停止清除。

匯入回報只證明此交易的配對已被 App 接收；不表示 VPN、DDI、手機開發者服務或其他 App 的定位已成功。iOS 26、27 的接收效果、VPN／網路切換、鎖屏與重啟需分開驗收。路線在背景暫停，保留最後送出位置，返回需手動繼續。

## 交付與保護

- USB only：核對完整裝置身分、iOS 26+、開發者模式；開啟並確認 Wi-Fi debugging，供之後手機端通道使用。
- 配對函式庫固定 `pymobiledevice3==11.31.0`，啟動檢查 API。Ed25519 金鑰與 UUID 身分由自己產生，完成後重新開啟 USB session 驗證，才發布配對檔。
- 安裝前核對 `com.neven.localgo`、Apple Development 信任鏈、Team／App ID、描述檔裝置清單、憑證、有效期及 `get-task-allow`，不接受未簽署產物或其他 App。
- Mac 狀態預設在 `~/Library/Application Support/LocalGoSetup`：0700／0600、排除 Time Machine、單一設定程序鎖定。這裡含配對憑證；不要同步或上傳。
- 先啟動 LocalGo 建立私有交付目錄及 ready marker，再終止並確認程序停止；資料傳完才重新啟動。配對不進 Documents、URL、剪貼簿、雲端或原始診斷。
- App 檢查有界 payload、SHA-256、RP 金鑰、裝置綁定與交易 UUID，走既有原子配對匯入。清除一次性輸入後，原子寫入不含金鑰的回報。
- 保留最多 1000 筆交易回報以拒絕重播，達上限便停止；不自動刪除舊回報。Mac 只接受本次 UUID 的成功回報。
- 已完成的裝置配對、Wi-Fi debugging 或 App 安裝不會因後續步驟失敗自動撤回；失敗訊息不是「裝置完全未變更」。

## 開發驗證

```sh
PYTHONDONTWRITEBYTECODE=1 work/mac-setup-env/bin/python -m unittest discover \
  -s app/LocalGo/MacSetup/Tests
```

測試使用假裝置及子程序回應檢查失敗門檻、配對保存、簽署限制、傳輸順序與回報；macOS 另實測備份排除屬性。實機配對／安裝成功與否以當次實機紀錄為準。

依賴來源：[pymobiledevice3](https://github.com/doronz88/pymobiledevice3)（GPL-3.0；在 Mac 獨立執行），[idevice RP 格式](https://github.com/jkcoxson/idevice/blob/3854a5df4a5a6dee71ffce4d8befc2ea356a8065/idevice/src/remote_pairing/rp_pairing_file.rs)。保留各依賴授權，未複製 AnyGo 元件。

Apple 限制：[免費帳號與七日期限](https://developer.apple.com/help/account/basics/about-your-developer-account)、[能力對照](https://developer.apple.com/help/account/reference/supported-capabilities-ios)。

## 本次實機紀錄（2026-10-15）

iOS 27.0.1 USB 身分／開發者模式核對成功，已建立自己的 RP 並以新 USB session 驗證，安裝簽署 LocalGo、交付配對及收到本次成功回報。使用者另確認手機端裝置身分及 DDI 已核對。使用者已確認拔除 USB 後兩個其他 App 收到選定位置；使用者也已確認停止清除後恢復真實位置。

本次 Apple 核發描述檔的實際到期時間為 2027-10-15 17:48:35（Asia/Taipei）；不應把此紀錄推廣為所有免費帳號的期限或永久有效保證。
