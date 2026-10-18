# AI installation runbook / AI 安裝操作說明 / AI 安装操作说明

[English](#english) · [繁體中文](#繁體中文) · [简体中文](#简体中文)

## English

### Establish the task

1. Read the selected root README, this guide, [Mac capabilities](../app/GoFlyMac/README.md), and applicable workspace rules. Identify whether the user wants a GoFly release, a Mac preview, or an explicitly chosen LocalGo prototype experiment. Continue within existing authorization without asking for the same permission repeatedly.
2. **Current state, 2026-10-18:** no verified public DMG is recorded. The development GUI implements formal USB first installation, same-device reinstallation with selected data, and local backup management; iPhone acceptance is deferred. Re-signing, pairing repair, Wi-Fi writes, and portable packaging remain in development. Do not invent download URLs, bypass disabled writes, or report preview data as a real install. Do not silently substitute LocalGo.
3. Check Mac/Xcode, iPhone/iOS, USB, and signing team. Use only the intended phone. Resolve ambiguous device/team selection before writing.
4. The user handles Apple sign-in, passwords, 2FA, terms, Keychain prompts, iPhone trust/Developer Mode, and VPN permission. Do not request credentials or pairing private keys in chat. Report pending physical phone actions.

### Choose the available route

- **GoFly release — pending implementation:** when an actual release exists, verify its official source, version, architecture, minimum OS, and published checksum. Open the DMG, place the app in Applications, launch it, and run environment checks. Do not disable Gatekeeper globally or recursively remove quarantine to force it open. Connect by USB, verify the phone, then use the supported install flow. Verify signing, deployment, pairing import, and required device preparation separately. The Mac must finish necessary preparation before declaring completion; reuse ready items and do not add the old prototype's phone-side support download. After verified completion, hand off to LocalDevVPN and GoFly on the phone. A verified VPN channel is distinct from a running location task; service startup must not move the location. Verify automatic USB/Wi-Fi re-signing and data preservation on the actual release before claiming support.
- **Current Mac development app:** use the root README's build/open commands and existing Python environment; the GUI does not install missing dependencies. USB first installation uses formal GoFly, a verified device/team and explicit start. Apple provisioning updates require the per-operation option and authorization. Same-device reinstallation additionally requires explicit data selection, source admission and a fully verified durable backup before removal. An unknown write remains pending in its original transaction; never resubmit blindly. Backup cleanup only affects confirmed completed local copies. Keep preview results separate and honor any user instruction to defer phone operations.
- **LocalGo prototype — only when chosen:** read the [CLI guide](../app/LocalGo/MacSetup/README.md), then use the shared commands below. This installs `com.neven.localgo`, not the new GoFly identifier `com.neven.gofly`. Create the isolated environment only if absent and install requirements as needed. Run preflight first. Execute only when prototype installation and Apple provisioning are authorized, target/team are unambiguous, preflight passes, and existing location simulation has been stopped and cleared. `--allow-provisioning-updates` lets Xcode contact Apple and may create signing material; without authorization, complete preflight and report this pending action. For ambiguous selection, resolve the target and use explicit device/team options from the CLI guide. Keep full identifiers local.

Do not add `--repair`, uninstall apps, delete data, revoke certificates, or switch teams to force success. Pairing replacement and destructive recovery need their own authorized scope. An interrupted write may have changed the phone; inspect the same device/transaction before retrying. The prototype receipt confirms app/pairing delivery only; phone-side support downloads remain prototype behavior. Verify VPN, service, location simulation, and GPS restoration separately, without presenting this as full GoFly acceptance.

### Report results

Report version/route, redacted device label, preflight, actual writes, installation/pairing/preparation evidence, verified signing expiry, remaining phone actions, and blockers. Distinguish **completed**, **pending user action**, **failed**, and **not verified**. Preview data and old experiments are not current device evidence. Keep pairing files, credentials, signing material, and raw logs out of chat/version control.

## 繁體中文

### 確認任務

1. 先讀選用語言的根目錄 README、本文、[Mac 現況](../app/GoFlyMac/README.md)及適用的工作目錄規則。確認使用者要 GoFly 發行版、Mac 預覽，或明確選擇的 LocalGo prototype 實驗。沿用已有授權，不重複詢問同一權限。
2. **2026-10-18 現況：**尚無已驗證的公開 DMG。開發版 GUI 已實作正式 USB 首次安裝、所選資料同機重裝與本機備份管理，手機驗收延後；重新簽名、配對修復、Wi-Fi 寫入與可攜包仍在開發。不得捏造下載網址、繞過停用功能、把預覽回報為真實安裝，或默默改裝 LocalGo。
3. 檢查 Mac／Xcode、iPhone／iOS、USB 及簽署 Team，只操作指定手機。多裝置／Team 且意圖不明時，寫入前先釐清。
4. Apple 登入、密碼、雙重認證、條款、鑰匙圈提示、手機信任／開發者模式及 VPN 權限由使用者處理。不在聊天索取憑證或配對私鑰；需要實體手機操作時回報待辦。

### 選擇可用路徑

- **GoFly 發行版 — 尚待實作：**實際發行後核對正式來源、版本、架構、最低系統與公布校驗碼，再開啟 DMG、放入「應用程式」、啟動及檢查環境。不以全域關閉 Gatekeeper 或遞迴移除隔離屬性強行開啟。USB 連接、核對手機，再使用正式安裝流程。分別驗證簽署、部署、配對匯入及必要裝置準備；Mac 完成準備才可宣告成功，已備妥則重用，不加回舊 prototype 手機下載步驟。驗證完成後交接手機 LocalDevVPN 與 GoFly。實際 VPN 通道可用與定位任務執行中分開，啟動服務不移動位置。USB／Wi-Fi 自動重新簽名及保留資料須在實際發行版驗證後才宣告可用。
- **目前 Mac 開發版：**使用根目錄 README 的建置／開啟命令及既有 Python 環境，GUI 不會自動安裝依賴。USB 首次安裝使用正式 GoFly，核對裝置／Team 後明確開始；Apple 佈建更新須本次選項與授權。同機重裝另須明確資料選取、來源准入，以及移除前完整持久備份驗證。未知寫入保留原交易待核對，不盲目重送；備份清理只影響已確認完成的本機副本。預覽另外標示，並遵守使用者延後手機操作的要求。
- **LocalGo prototype — 僅限使用者選擇時：**先讀 [CLI 說明](../app/LocalGo/MacSetup/README.md)，再用下方共用命令。它安裝 `com.neven.localgo`，不是新版 GoFly 的 `com.neven.gofly`。隔離環境不存在才建立，依需要安裝依賴；先預檢。僅在 prototype 安裝及 Apple 佈建均已有授權、目標／Team 明確、預檢通過，且既有模擬定位已停止並清除時才執行。`--allow-provisioning-updates` 允許 Xcode 聯絡 Apple，可能建立簽署資料；尚未授權時先完成預檢並回報待辦。有選取歧義時先釐清，再依 CLI 說明傳入明確裝置／Team；完整識別碼留在本機。

不得為了強行成功自行加 `--repair`、移除 App、刪資料、撤銷憑證或更換 Team。替換配對及破壞性修復需要相應授權。寫入中斷可能已改變手機，重試前核對同一裝置／交易。Prototype 回報只證明 App／配對交付，手機端支援下載仍是其現有行為。VPN、服務、模擬定位及 GPS 恢復分別驗證，不當作 GoFly 完整驗收。

### 回報結果

回報版本／路徑、遮蔽裝置名稱、預檢、實際寫入項目、安裝／配對／準備證據、已驗證簽名到期日、手機待辦及阻礙。區分「已完成／待使用者操作／失敗／未驗證」；預覽資料與舊實驗不是本次裝置證據。配對檔、憑證、簽署資料及原始日誌不貼聊天、不進版本控制。

## 简体中文

### 确认任务

1. 先读所选语言的根目录 README、本文、[Mac 现状](../app/GoFlyMac/README.md)及适用的工作目录规则。确认用户要 GoFly 发布版、Mac 预览，或明确选择的 LocalGo prototype 实验。沿用已有授权，不重复询问同一权限。
2. **2026-10-18 现状：**尚无已验证的公开 DMG。开发版 GUI 已实现正式 USB 首次安装、所选数据同机重装与本机备份管理，手机验收延后；重新签名、配对修复、Wi-Fi 写入与可移植包仍在开发。不得编造下载网址、绕过禁用功能、把预览报告为真实安装，或默默改装 LocalGo。
3. 检查 Mac／Xcode、iPhone／iOS、USB 及签名 Team，只操作指定手机。多设备／Team 且意图不明时，写入前先明确。
4. Apple 登录、密码、双重认证、条款、钥匙串提示、手机信任／开发者模式及 VPN 权限由用户处理。不在聊天索取凭证或配对私钥；需要实体手机操作时报告待办。

### 选择可用路径

- **GoFly 发布版 — 尚待实现：**实际发布后核对正式来源、版本、架构、最低系统与公布校验码，再打开 DMG、放入“应用程序”、启动及检查环境。不通过全局关闭 Gatekeeper 或递归移除隔离属性强行打开。USB 连接、核对手机，再使用正式安装流程。分别验证签名、部署、配对导入及必要设备准备；Mac 完成准备才可宣布成功，已就绪则复用，不加回旧 prototype 手机下载步骤。验证完成后交接手机 LocalDevVPN 与 GoFly。实际 VPN 通道可用与定位任务运行中分开，启动服务不移动位置。USB／Wi-Fi 自动重新签名及保留数据须在实际发布版验证后才宣布可用。
- **当前 Mac 开发版：**使用根目录 README 的构建／打开命令及现有 Python 环境，GUI 不会自动安装依赖。USB 首次安装使用正式 GoFly，核对设备／Team 后明确开始；Apple 配置更新须本次选项与授权。同机重装另须明确数据选择、来源准入，以及移除前完整持久备份验证。未知写入保留原事务待核对，不盲目重送；备份清理只影响已确认完成的本机副本。预览另行标注，并遵守用户延后手机操作的要求。
- **LocalGo prototype — 仅限用户选择时：**先读 [CLI 说明](../app/LocalGo/MacSetup/README.md)，再用下方共用命令。它安装 `com.neven.localgo`，不是新版 GoFly 的 `com.neven.gofly`。隔离环境不存在才创建，按需安装依赖；先预检。仅在 prototype 安装及 Apple 配置均已有授权、目标／Team 明确、预检通过，且现有模拟定位已停止并清除时才执行。`--allow-provisioning-updates` 允许 Xcode 联系 Apple，可能创建签名资料；尚未授权时先完成预检并报告待办。有选择歧义时先明确，再按 CLI 说明传入明确设备／Team；完整标识符留在本机。

不得为了强行成功自行加 `--repair`、移除 App、删数据、撤销证书或更换 Team。替换配对及破坏性修复需要相应授权。写入中断可能已改变手机，重试前核对同一设备／事务。Prototype 报告只证明 App／配对交付，手机端支持下载仍是其现有行为。VPN、服务、模拟定位及 GPS 恢复分别验证，不当作 GoFly 完整验收。

### 报告结果

报告版本／路径、脱敏设备名称、预检、实际写入项目、安装／配对／准备证据、已验证签名到期日、手机待办及阻碍。区分“已完成／待用户操作／失败／未验证”；预览数据与旧实验不是本次设备证据。配对文件、凭证、签名资料及原始日志不贴聊天、不进版本控制。

## Shared CLI commands / 共用 CLI 命令 / 共用 CLI 命令

All commands run from the repository root, for the explicitly selected LocalGo prototype only.

以下均從儲存庫根目錄執行，僅供明確選擇的 LocalGo prototype。

以下均从仓库根目录执行，仅供明确选择的 LocalGo prototype。

### 1. Python environment / Python 環境 / Python 环境

```sh
python3 -m venv work/mac-setup-env
work/mac-setup-env/bin/python -m pip install -r app/LocalGo/MacSetup/requirements.txt
```

### 2. USB list and preflight / USB 清單與預檢 / USB 列表与预检

Without `--execute`, setup does not install on the phone. 未加 `--execute` 不會安裝至手機。未加 `--execute` 不会安装至手机。

```sh
work/mac-setup-env/bin/python app/LocalGo/MacSetup/localgo_setup.py devices
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  work/mac-setup-env/bin/python app/LocalGo/MacSetup/localgo_setup.py setup \
  --output work/localgo-signed
```

### 3. Authorized execution / 已授權執行 / 已授权执行

```sh
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  work/mac-setup-env/bin/python app/LocalGo/MacSetup/localgo_setup.py setup \
  --output work/localgo-signed --execute --allow-provisioning-updates
```
