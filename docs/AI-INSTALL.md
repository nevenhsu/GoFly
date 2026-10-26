# AI installation runbook / AI 安裝操作說明 / AI 安装操作说明

[English](#english) · [繁體中文](#繁體中文) · [简体中文](#简体中文)

## Device-test install/update / 實機測試安裝更新（2026-10-26）

Use the shared entry below for every AI-assisted device test; do not use an install-only Xcode/devicectl command. Existing apps use `renew`, which includes pairing and device preparation. This is an implemented USB development workflow; device success must be recorded separately from offline checks.

AI 實機測試固定用以下腳本，與 Mac App 共用正式 producer。`renew` 覆蓋同一 App 並保留偏好、最愛及路線，同時核對並交付該手機的配對資料、準備必要支援；不是移除 App 後重裝。不要以單獨 Xcode／devicectl 安裝取代。目前使用者指定的 Xcode Personal Team 是 `48XD59469V`；舊 Team `NHW5EDBH4P` 已淘汰，不得使用或自動 fallback。每次核對登入帳號並明確指定 Personal Team ID；裝置或 Team 身分不符立即停止。目前這條完整交接限 USB。

```sh
# After the user authorizes installation and Apple provisioning updates / 使用者授權安裝與 Apple 佈建更新後：
bash scripts/install-ios-test.sh --device <IPHONE_UDID> --team 48XD59469V --mode renew --action preflight --allow-provisioning-updates
bash scripts/install-ios-test.sh --device <IPHONE_UDID> --team 48XD59469V --mode renew --action apply --setup-id <PREFLIGHT_SETUP_ID> --allow-provisioning-updates
# Interrupted? Do not resume; start over with preflight → apply / 中斷時不接續，從頭重新 preflight → apply
```

Always pass the verified 10-character Team ID explicitly. For this project use Personal Team `48XD59469V`; `NHW5EDBH4P` is obsolete. First installation uses `--mode install`; an existing app uses `--mode renew`. Provisioning updates are off by default; when the user authorizes them, include `--allow-provisioning-updates` on both preflight and apply. Script success requires `complete=true` and all three proofs, including an exact App activation receipt. Installation alone never counts. No automatic retry, uninstall or data reset. After an interruption, never use `--action resume`; start over with preflight → apply (2026-10-26 design, matching the Mac app). The producer has one global current transaction: `apply` abandons any unfinished transaction, regardless of its device (archived as `journal.abandoned.json`; transaction data is retained), then starts fresh. Repeating the identical setupID still returns `transaction-conflict`. Revoking an old unused pairing is not implemented yet.

首次安裝加 `--mode install`，已有 App 使用 `--mode renew`。本專案目前使用 Xcode Personal Team `48XD59469V`；舊 Team `NHW5EDBH4P` 不得再使用。預設不連 Apple 更新佈建資料；使用者授權後，`--allow-provisioning-updates` 須同時帶在 preflight 與 apply。三項證據及手機精確啟用回報全部通過才成功；VPN／定位效果仍須另外測試。中斷後不使用 `--action resume`，一律從頭重新 preflight → apply（2026-10-26 設計，與 Mac App 一致）；producer 只有一筆全域現行交易，`apply` 會放棄任何裝置的未完成交易（封存為 `journal.abandoned.json`，保留交易資料）並開新交易；相同 setupID 重送仍回 `transaction-conflict`。作廢舊的未使用配對尚未實作。

AI 实机测试同样固定使用此脚本。更新保留偏好、收藏及路线，并核对目标手机的配对资料；中断后不接续、不用 `--action resume`，从头重新 preflight → apply；全局唯一的未完成交易会在 apply 时自动放弃（封存，保留交易资料），并开新交易。不卸载、不清数据。本项目目前使用 Xcode Personal Team `48XD59469V`，旧 Team `NHW5EDBH4P` 已淘汰；用户授权 Apple provisioning 更新后，preflight 和 apply 都带 `--allow-provisioning-updates`。只有完整安装、配对、设备准备回报全部通过才算完成。

## iOS device-test prompt

### 可直接貼給 AI 的 iPhone 覆蓋安裝 prompt

以下 prompt 供使用者貼上交付任務；僅閱讀本文件不代表要求執行安裝。這裡的「重裝」指保留資料的覆蓋更新，已有 App 使用 `renew`。

```text
請在目前這個 GoFly 專案工作目錄中，使用已驗證的共用安裝流程，將最新 GoFly 覆蓋安裝到我的 iPhone，並完成配對交接。

這次已授權建置、簽署、Apple 佈建資料更新、覆蓋安裝、配對交付及必要裝置準備。請直接執行，不要只提供步驟。

要求：
- 先讀 AGENTS.md 與 docs/AI-INSTALL.md。
- 使用 scripts/install-ios-test.sh；已有 App 使用 --mode renew。
- 不卸載 App、不清除偏好設定、最愛或路線。
- 核對目前連接的實體 iPhone；若只有一台，直接使用。使用 Xcode Personal Team `48XD59469V`；舊 Team `NHW5EDBH4P` 已淘汰，不得使用或 fallback。
- 先執行 --action preflight，再執行 --action apply。
- preflight 與 apply 都帶 --allow-provisioning-updates，並將 preflight 回傳的同一 setupID 傳給 apply。
- 不得以單獨 Xcode 或 devicectl 安裝取代共用流程。
- 必須確認 complete=true，且 installationConfirmed、pairingImported、supportObserved 全部為 true，才算完成。
- 中斷時不接續、不用 --action resume：從頭重新 preflight → apply；全域唯一未完成交易會在 apply 時自動放棄（封存、保留交易資料）並重新開始，不限該交易的裝置；重送相同 setupID 仍衝突。仍不手動刪除 journal、配對或 App。舊的未使用配對作廢尚未實作。
- 比對更新前後既有偏好與資料，確認保留。
- 配對資料、憑證與原始日誌只保留在私密／忽略目錄，不貼聊天、不提交。
- 完成後回報手機上的版本/build、配對與裝置準備結果，以及資料保留核對結果。安裝成功與外部地圖定位成功分開說明。
```

## English

### Establish the task

1. Read the selected root README, this guide, [Mac capabilities](../app/GoFlyMac/README.md), and applicable workspace rules. Identify whether the user wants a GoFly release or a Mac development-preview run. Continue within existing authorization without asking for the same permission repeatedly.
2. **Current state, 2026-10-18:** no verified public DMG is recorded. The development GUI implements formal USB first installation; iPhone acceptance is deferred. Renewal includes full pairing/preparation as of 2026-10-22; portable packaging remains in development. Do not invent download URLs, bypass disabled writes, or report preview data as a real install. Do not substitute the retired LocalGo prototype.
3. Check Mac/Xcode, iPhone/iOS, USB, and signing team. Use only the intended phone. Resolve ambiguous device/team selection before writing.
4. The user handles Apple sign-in, passwords, 2FA, terms, Keychain prompts, iPhone trust/Developer Mode, and VPN permission. Do not request credentials or pairing private keys in chat. Report pending physical phone actions.

### Choose the available route

- **GoFly release — pending implementation:** when an actual release exists, verify its official source, version, architecture, minimum OS, and published checksum. Open the DMG, place the app in Applications, launch it, and run environment checks. Do not disable Gatekeeper globally or recursively remove quarantine to force it open. Connect by USB, verify the phone, then use the supported install flow. Verify signing, deployment, pairing import, and required device preparation separately. The Mac must finish necessary preparation before declaring completion; reuse ready items and do not add the old prototype's phone-side support download. After verified completion, hand off to LocalDevVPN and GoFly on the phone. A verified VPN channel is distinct from a running location task; service startup must not move the location.
- **Current Mac development app:** use the root README's build/open commands and existing Python environment; the GUI does not install missing dependencies. USB first installation uses formal GoFly, a verified device/team and explicit start. Apple provisioning updates require the per-operation option and authorization. After an interruption, start over instead of resuming; stop on `transaction-conflict` until the restart path is implemented. Keep preview results separate and honor any user instruction to defer phone operations.
- **LocalGo prototype — retired:** the prototype app and its `localgo_setup.py` install CLI were removed (2026-10-19 and 2026-10-20). GoFly is the only install path; do not attempt the old `com.neven.localgo` flow.

Do not uninstall apps, delete data, revoke certificates, or switch teams to force success. Destructive recovery needs its own authorized scope. An interrupted write may have changed the phone; inspect the same device/transaction before retrying. A completion receipt confirms app/pairing delivery only, not VPN, DDI, or other device services. Verify VPN, service, location simulation, and GPS restoration separately, without presenting this as full GoFly acceptance.

### Report results

Report version/route, redacted device label, preflight, actual writes, installation/pairing/preparation evidence, verified signing expiry, remaining phone actions, and blockers. Distinguish **completed**, **pending user action**, **failed**, and **not verified**. Preview data and old experiments are not current device evidence. Keep pairing files, credentials, signing material, and raw logs out of chat/version control.

## 繁體中文

### 確認任務

1. 先讀選用語言的根目錄 README、本文、[Mac 現況](../app/GoFlyMac/README.md)及適用的工作目錄規則。確認使用者要 GoFly 發行版還是 Mac 開發預覽。沿用已有授權，不重複詢問同一權限。
2. **2026-10-18 現況：**尚無已驗證的公開 DMG。開發版 GUI 已實作正式 USB 首次安裝，手機驗收延後；2026-10-22 起續簽納入完整配對／準備交接，可攜包仍在開發。不得捏造下載網址、繞過停用功能、把預覽回報為真實安裝，或改裝已退役的 LocalGo prototype。
3. 檢查 Mac／Xcode、iPhone／iOS、USB 及簽署 Team，只操作指定手機。多裝置／Team 且意圖不明時，寫入前先釐清。
4. Apple 登入、密碼、雙重認證、條款、鑰匙圈提示、手機信任／開發者模式及 VPN 權限由使用者處理。不在聊天索取憑證或配對私鑰；需要實體手機操作時回報待辦。

### 選擇可用路徑

- **GoFly 發行版 — 尚待實作：**實際發行後核對正式來源、版本、架構、最低系統與公布校驗碼，再開啟 DMG、放入「應用程式」、啟動及檢查環境。不以全域關閉 Gatekeeper 或遞迴移除隔離屬性強行開啟。USB 連接、核對手機，再使用正式安裝流程。分別驗證簽署、部署、配對匯入及必要裝置準備；Mac 完成準備才可宣告成功，已備妥則重用，不加回舊 prototype 手機下載步驟。驗證完成後交接手機 LocalDevVPN 與 GoFly。實際 VPN 通道可用與定位任務執行中分開，啟動服務不移動位置。
- **目前 Mac 開發版：**使用根目錄 README 的建置／開啟命令及既有 Python 環境，GUI 不會自動安裝依賴。USB 首次安裝使用正式 GoFly，核對裝置／Team 後明確開始；Apple 佈建更新須本次選項與授權。中斷後從頭重來、不接續；遇到 `transaction-conflict` 時停止回報。預覽另外標示，並遵守使用者延後手機操作的要求。
- **LocalGo prototype — 已退役：**prototype App 與其 `localgo_setup.py` 安裝 CLI 已分別於 2026-10-19、2026-10-20 移除。GoFly 是唯一安裝路徑，不要再走舊的 `com.neven.localgo` 流程。

不得為了強行成功移除 App、刪資料、撤銷憑證或更換 Team。破壞性修復需要相應授權。寫入中斷可能已改變手機，重試前核對同一裝置／交易。完成回報只證明 App／配對交付，不代表 VPN、DDI 或其他裝置服務。VPN、服務、模擬定位及 GPS 恢復分別驗證，不當作 GoFly 完整驗收。

### 回報結果

回報版本／路徑、遮蔽裝置名稱、預檢、實際寫入項目、安裝／配對／準備證據、已驗證簽名到期日、手機待辦及阻礙。區分「已完成／待使用者操作／失敗／未驗證」；預覽資料與舊實驗不是本次裝置證據。配對檔、憑證、簽署資料及原始日誌不貼聊天、不進版本控制。

## 简体中文

### 确认任务

1. 先读所选语言的根目录 README、本文、[Mac 现状](../app/GoFlyMac/README.md)及适用的工作目录规则。确认用户要 GoFly 发布版还是 Mac 开发预览。沿用已有授权，不重复询问同一权限。
2. **2026-10-18 现状：**尚无已验证的公开 DMG。开发版 GUI 已实现正式 USB 首次安装，手机验收延后；2026-10-22 起续签纳入完整配对／准备交接，可移植包仍在开发。不得编造下载网址、绕过禁用功能、把预览报告为真实安装，或改装已退役的 LocalGo prototype。
3. 检查 Mac／Xcode、iPhone／iOS、USB 及签名 Team，只操作指定手机。多设备／Team 且意图不明时，写入前先明确。
4. Apple 登录、密码、双重认证、条款、钥匙串提示、手机信任／开发者模式及 VPN 权限由用户处理。不在聊天索取凭证或配对私钥；需要实体手机操作时报告待办。

### 选择可用路径

- **GoFly 发布版 — 尚待实现：**实际发布后核对正式来源、版本、架构、最低系统与公布校验码，再打开 DMG、放入“应用程序”、启动及检查环境。不通过全局关闭 Gatekeeper 或递归移除隔离属性强行打开。USB 连接、核对手机，再使用正式安装流程。分别验证签名、部署、配对导入及必要设备准备；Mac 完成准备才可宣布成功，已就绪则复用，不加回旧 prototype 手机下载步骤。验证完成后交接手机 LocalDevVPN 与 GoFly。实际 VPN 通道可用与定位任务运行中分开，启动服务不移动位置。
- **当前 Mac 开发版：**使用根目录 README 的构建／打开命令及现有 Python 环境，GUI 不会自动安装依赖。USB 首次安装使用正式 GoFly，核对设备／Team 后明确开始；Apple 配置更新须本次选项与授权。中断后从头重来、不接续；遇到 `transaction-conflict` 时停止报告。预览另行标注，并遵守用户延后手机操作的要求。
- **LocalGo prototype — 已退役：**prototype App 及其 `localgo_setup.py` 安装 CLI 已分别于 2026-10-19、2026-10-20 移除。GoFly 是唯一安装路径，不要再走旧的 `com.neven.localgo` 流程。

不得为了强行成功移除 App、删数据、撤销证书或更换 Team。破坏性修复需要相应授权。写入中断可能已改变手机，重试前核对同一设备／事务。完成报告只证明 App／配对交付，不代表 VPN、DDI 或其他设备服务。VPN、服务、模拟定位及 GPS 恢复分别验证，不当作 GoFly 完整验收。

### 报告结果

报告版本／路径、脱敏设备名称、预检、实际写入项目、安装／配对／准备证据、已验证签名到期日、手机待办及阻碍。区分“已完成／待用户操作／失败／未验证”；预览数据与旧实验不是本次设备证据。配对文件、凭证、签名资料及原始日志不贴聊天、不进版本控制。

## Shared CLI commands / 共用 CLI 命令 / 共用 CLI 命令

The LocalGo prototype CLI (`LocalGo/MacSetup/localgo_setup.py`) and its tests were removed on 2026-10-20; GoFly is the only install path. The Python environment below is still required because the Mac app's read-only device boundary runs in that pinned environment.

LocalGo prototype CLI（`localgo_setup.py`）與其測試已於 2026-10-20 移除，GoFly 是唯一安裝路徑。下列 Python 環境仍需建立，因為 Mac App 使用剩下的唯讀裝置邊界。

LocalGo prototype CLI（`localgo_setup.py`）及其测试已于 2026-10-20 移除，GoFly 是唯一安装路径。下列 Python 环境仍需创建，因为 Mac App 使用剩下的只读设备边界。

### Python environment / Python 環境 / Python 环境

```sh
python3 -m venv work/mac-setup-env
work/mac-setup-env/bin/python -m pip install -r app/GoFlyMac/requirements.txt
```
