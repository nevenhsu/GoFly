# GoFly for Mac — DMG 安装

[English](README.md) · [繁體中文](README.zh-Hant.md) · **简体中文**

用于研究 iOS 模拟定位、设备连接与原生 App 操作流程的 Mac／iPhone 项目。预定使用方式：获取 Mac App、打开 GoFly、通过 USB 连接 iPhone，再由 Mac 安装手机 App。

**发布状态：** 尚未公开 DMG。已完成本地 DMG 构建器与安装脚本；手机验收及干净 Mac 下载测试仍待完成。预览数据不代表设备实际执行过操作。

## 目录

- [设备与环境](#设备与环境)
- [安装](#安装)
- [开发版构建](#开发版构建)
- [研究操作](#研究操作)
- [交给 AI 协助安装](#交给-ai-协助安装)
- [常见问题](#常见问题)
- [文档与源代码](#文档与源代码)
- [许可](#许可)

## 设备与环境

| 项目 | 要求 |
| --- | --- |
| 电脑 | 需要 macOS 15 以上的 Mac。从源代码构建时，macOS 也须符合所用 Xcode 的要求。目前不支持 Windows／Linux。 |
| 手机 | 需要 iOS 26 以上的 iPhone。这不代表所有机型及系统版本均已验证。 |
| 连接线 | 首次安装需要可传输数据的 USB 线。设备完成核对后，后续重新签名也可使用 Wi-Fi。 |
| 开发工具 | Xcode、所需 iOS SDK 与 Swift 工具链；Mac 软件包需要 Swift 6.2 以上。 |
| Apple 账号 | 开发签名使用自己的 Apple 账号，在 Xcode 登录。支持免费 Personal Team。 |
| 手机设置 | 解锁 iPhone、信任 Mac，并启用开发安装所需的[开发者模式](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)。 |
| 连接 App | 设备通道需要另行在 iPhone 安装 [LocalDevVPN](https://apps.apple.com/us/app/localdevvpn/id6755608044)。 |
| 网络 | Apple 签名、依赖下载、地图／搜索及必要设备准备下载均需要网络。 |

GoFly 以免费使用为目标，Apple 签名限制仍适用：免费 Personal Team 描述文件通常七天到期，之后需要重新签名。请以本次可验证的实际有效期为准，详见 [Apple 账号说明](https://developer.apple.com/help/account/basics/about-your-developer-account)。

## 安装

安装前，请使用符合 Xcode 要求的 Mac，安装完整 Xcode 与 iOS 平台，并在 Xcode → Settings → Apple Accounts 登录自己的 Apple 账号。支持免费 Personal Team。iPhone 需要 iOS 26 以上、开启开发者模式，并信任这台 Mac。GoFly 不会要求或处理 Apple 账号凭证。

1. 从正式发布页下载 DMG 及对应的 `.sha256` 文件。
2. 打开 DMG 前，在“终端”核对下载文件名：

   ```sh
   shasum -a 256 -c GoFly-1.0.0-arm64.dmg.sha256
   ```

   结果必须显示 `OK`。校验码不符时不要运行安装脚本。
3. 打开 DMG，在“终端”运行 `bash /Volumes/GoFly/install.sh`（如果挂载名称不同，请使用 `/Volumes` 中显示的名称）。
4. 如果 `/Applications/GoFly.app` 已存在，请先阅读提示再确认覆盖。安装器只会替换该 App bundle、移除它的隔离属性并打开 App；GoFly 状态及手机数据分开保存，不会被移除。
5. 打开 GoFly，完成 Mac 环境步骤，通过 USB 连接 iPhone 并开始首次安装。必须等到 App 部署、配对导入及必要设备准备都验证完成，才算安装成功。
6. 在 iPhone 从 App Store 安装 LocalDevVPN、启用 VPN 通道，再打开 GoFly。

目前尚未公开 DMG。正式发布及校验码公布前，可用下方命令构建本地产物；本地 DMG 不代表正式发布版。

## 构建本地 DMG

在已安装完整 Xcode 的 Apple Silicon Mac，从仓库根目录运行，并传入生成 GoFly iOS Bundle ID 所用的 Team ID：

```sh
bash app/GoFlyMac/make-dmg.sh <你的 Xcode Team ID>
```

脚本会构建自给自足的 App、使用 ad-hoc 深度签名、验证签名，并在 `work/dist/` 生成 `GoFly-<版本>-arm64.dmg` 与旁边的 `.sha256` 校验码。DMG 是本地构建产物，不提交到版本控制。此版本没有 Developer ID 签名或 notarization；安装器只移除已安装 GoFly App 的隔离属性。

只做 Swift 开发时，运行 `bash app/GoFlyMac/build-app.sh <你的 Xcode Team ID>`，再打开 `work/gofly-mac/GoFly.app`。

## 研究操作

GoFly 设计涵盖地点选择、路线／GPX、摇杆移动、设备服务准备及恢复 GPS。功能要求见[GoFly App 说明](app/GoFly/README.md)及 [iOS UI 设计规范](docs/IOS-UI-DESIGN.md)。

实验时记录 App 版本、iPhone 机型、iOS 版本、连接方式及实际结果。先在 Apple 地图与另一个 App 核对模拟位置，再停止任务、恢复 GPS，并另外核对真实位置。安装或配对成功不能代替 GPS 恢复验证；后台运行、断线重连、系统更新及重启均需分别验证。

研究是本项目的主要用途，不是 0BSD 的非商用限制。项目不接入 AnyGo／iToolab 服务，也不分发其代码、素材、凭证或密钥。

## 交给 AI 协助安装

已有 GoFly、需要在实机测试时保留数据覆盖更新，可直接使用 [iPhone 覆盖安装 prompt（繁体中文）](docs/AI-INSTALL.md#ios-device-test-prompt)；共用流程会一并完成配对交接。

先提供 [AI 安装操作说明](docs/AI-INSTALL.md#简体中文)，再粘贴：

```text
请先阅读 README.zh-Hans.md 与 docs/AI-INSTALL.md，协助我在 Mac 和自己的
iPhone 设置 GoFly。先确认实际发布版本、当前能力与目标设备，再根据我的授权
执行可用的设置流程。如果只有预览版，请明确说明限制。Apple 登录、双重认证、信任、开发者
模式与 VPN 确认由我操作。保留现有 App 数据，逐步核对实际结果，最后报告
已完成项目、待我操作的步骤及阻碍。
```

## 常见问题

| 情况 | 处理方式 |
| --- | --- |
| 找不到正式 DMG | 尚未公开发布。维护者可按上方命令构建本地 DMG；不要使用第三方安装包替代。 |
| 校验码验证失败 | 删除不完整下载，从同一正式发布页重新下载 DMG 与匹配的 `.sha256` 文件。 |
| 找不到 iPhone | 检查 USB 数据线、解锁／信任状态、Xcode 设备支持及选择的手机。 |
| 安装／重新签名按钮禁用 | 核对环境、所选设备与待续事务；预览不会写入设备。 |
| 手机 App 无法打开 | 核对实际签名到期时间，从 Mac 重新签名；开发者模式不会延长签名。 |
| LocalDevVPN 已连接，GoFly 仍无法继续 | 核对实际 VPN 通道。设计提供连接检查；无法停止时可在设置使用“重置”。 |
| 写入途中中断 | 先核对同一设备与本次事务，再决定是否重试；结果不明须如实报告并保留数据。 |

## 文档与源代码

| 路径 | 用途 |
| --- | --- |
| [app/GoFly/README.md](app/GoFly/README.md) | 原生 iOS App，含英文、繁中、简中资源。 |
| [app/GoFlyMac/README.md](app/GoFlyMac/README.md) | Mac 能力及开发检查。 |
| [app/GoFlyMac/DEVELOPMENT.md](app/GoFlyMac/DEVELOPMENT.md) | 已确认的 Mac 安装及设备管理要求。 |
| [docs/AI-INSTALL.md](docs/AI-INSTALL.md) | 三语 AI 代理安装操作说明。 |
| [docs/LICENSING.md](docs/LICENSING.md) | 0BSD 范围、现有上游许可与发布条件。 |
| `work/` | 不纳入版本控制的本机研究证据、构建产物及设备实验，不是公开发布内容。 |

README 提供英文、繁体中文、简体中文。App 本地化同样以三语及英文 fallback 为要求；文档翻译不代表 UI 本地化或真机验证已全部完成。

## 许可

新编写、独立持有权利的内容选用 **0BSD**，允许免费使用、修改、再分发，无须署名。[LICENSE](LICENSE) 涵盖三份根目录 README 及 `docs/` 的指南，不更改现有 App 代码或依赖许可。可查阅 [0BSD 官方条款](https://opensource.org/license/0bsd)。

LocalGo／StikDebug、复用的 Mac 设备边界及新版 GoFly 的[衍生／原生组件](app/GoFly/Legal/SOURCES.txt)保留 AGPL-3.0 声明。Mac App 使用 GPL-3.0 的 `pymobiledevice3`。整合发布的 App 不能宣称全部免署名，详见[许可说明](docs/LICENSING.md)及[上游来源](app/GoFly/Legal/UPSTREAM-LOCALGO.md)。

文档结构参考 [Best-README-Template](https://github.com/othneildrew/Best-README-Template) 的项目介绍、必要条件、安装、使用与许可章节，按研究项目重新编写。
