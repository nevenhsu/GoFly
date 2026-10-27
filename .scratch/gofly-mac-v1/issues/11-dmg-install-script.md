# 11 · DMG 與 install.sh

**Status:** implemented; software-verified
**Blocked by:** 01、02
**Spec:** MAC-INSTALLER-SPEC §3；F-dmg-architecture「第三階段」。

**Scope**
- `make-dmg.sh`：執行 `build-app.sh`、ad-hoc 深度簽名（`codesign --force --deep -s -`）、`codesign --verify --deep --strict`、產生 `work/dist/GoFly-<版本>-arm64.dmg` 並輸出 SHA-256。產物不進版本控制。
- `install.sh`：只動 `/Applications/GoFly.app`；已存在時先詢問再覆蓋；不用 sudo、不改系統 Gatekeeper；複製後 `xattr -dr com.apple.quarantine` 再開啟 App。
- 隔離屬性模擬測試：給 App 加 `com.apple.quarantine`，執行 install.sh，確認 App、內建 Python、原生擴充模組都能執行。
- 三語 README 改以 DMG 為主；`docs/LICENSING.md` 列出 DMG 內附元件授權與原始碼取得方式；同步 `docs/AI-INSTALL.md`。

**Acceptance**
- 本機 DMG 產生與隔離模擬通過。乾淨 Mac／另一個使用者帳號的下載測試由使用者執行，寫步驟後暫停此項。

**Evidence**
- `bash app/GoFlyMac/make-dmg.sh 48XD59469V` 以本機 ad-hoc 簽章產生 `work/dist/GoFly-1.0.0-arm64.dmg`；codesign build-time verify 通過，DMG SHA-256 為 `08e6d057d4df69623b27bdc7f971345426f8da591602978256f2841f6b587ac7`，sidecar 核對與 `hdiutil verify` 均通過。
- `bash app/GoFlyMac/test-install-quarantine.sh work/dist/GoFly-1.0.0-arm64.dmg` 通過：在隔離暫存目錄模擬 quarantine 下載與安裝、移除 bundle quarantine、驗證安裝後簽章、執行內建 CPython／CFFI／cryptography 原生模組、檢查 arm64 FFI，並從暫存使用者目錄啟動 App capture mode。沒有安裝到 `/Applications`，未修改使用者 GoFly 資料。
- DMG 內附 95 筆 runtime package 授權／來源清單。固定 CPython archive 的實際根目錄與 bundle layout 對齊；為 CPython 3.14 arm64 可安裝 wheel 將 `pylzss` 固定版升至 0.3.9，授權與來源已記錄於 `docs/LICENSING.md`。Bridge 使用 `-I -B`，避免 Python 忽略環境變數後在 ad-hoc 簽署 bundle 內寫入 bytecode。
- 最新離線驗證：GoFlyMac Swift 65 tests passed；Bridge 94 tests passed（2 skipped）；四個交付 shell scripts `bash -n` 通過。

**Not verified**
- 尚未在乾淨 Mac／另一帳號驗收下載、首次開啟與實際 `/Applications` 安裝；步驟見 `work/gofly-mac/v1/DMG-VERIFY.md`，待使用者操作。未做 Developer ID 公證或正式公開發行；公開前的完整應用程式與 FFI 授權審查仍待完成。
