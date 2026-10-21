# lw.Web2Harmony

[English](README_EN.md) | 简体中文

将本地 HTML、Vue、React、Vite 构建目录或在线网址，打包为鸿蒙原生应用。

Windows C++17 / Win32 GUI 与 CLI；手机端 ArkTS + ArkWeb；使用官方 HarmonyOS Command Line Tools / Hvigor 构建 HAP。项目从 lw.Web2Android 复用成熟基础模块，独立 Git 仓库维护。

版本：v0.1.0 开发预览。已通过 Windows GUI/CLI 构建、工程生成测试，以及官方 CLT 26.0.0.851 本地/在线样例 HAP 编译与包内容校验；真机签名、安装和页面运行仍待验证。

## 本地编译 Windows 工具

安装 VS2022“使用 C++ 的桌面开发”和 CMake：

```powershell
cmake -S . -B build -A x64 -DBUILD_TESTING=ON
cmake --build build --config Release --parallel
ctest --test-dir build -C Release --output-on-failure
.\build\Release\lw.Web2Harmony.GUI.exe
```

若当前进程环境同时含 PATH/Path，建议使用已处理干净子进程环境和 TEMP/TMP 的脚本：

```powershell
.\tools\build-desktop.ps1
```

本地不需要安装鸿蒙 SDK 即可编译 Windows 工具或导出工程。构建 HAP 在 CI 或具备配套工具链的电脑上执行。spdlog 使用锁定 SHA-256；可以复用 .deps/spdlog.tar.gz 离线归档。

## 使用

GUI 只负责打包：选择本地网页/在线网址，填写应用名称、Bundle Name、版本、PNG 图标、屏幕方向、全屏和 HTTP 选项，选择 HAP 输出目录，点击唯一的“生成鸿蒙 HAP”按钮。成功后自动打开 HAP 所在文件夹。

GUI 不提供“导出工程”，也不要求普通用户填写 SDK、JDK 或签名文件路径。工具从应用目录内自动寻找，签名按 Bundle Name 自动匹配。输出目录可以非空；重复构建采用编号保留旧产物，不覆盖原 HAP。PNG 必须正方形、192–4096 像素，留空使用内置熊猫图标。

CLI：

```powershell
.\build\Release\lw.Web2Harmony.exe validate samples/hello/project.json
.\build\Release\lw.Web2Harmony.exe pack samples/hello/project.json output
```

开发者仍可通过 CLI 导出完整工程，导出目录必须为空且不能与源网页目录重叠：

```powershell
.\build\Release\lw.Web2Harmony.exe export samples/hello/project.json build/generated/hello
.\build\Release\lw.Web2Harmony.exe export samples/remote/project.json build/generated/remote
```

Vue/Vite 建议 base: './'，使用 hash 路由。SSR 项目需先导出静态站点。默认不启用任意 file:// 访问，不注入 Native Bridge。网页 API 调用仍需服务器满足 CORS；允许 HTTP 不等于绕过跨域规则。

## 基础鸿蒙工程

`runtime/` 是固定、可独立编译的 ArkTS + ArkWeb 基础工程，对应 lw.Web2Android 中的 Runtime 底座。通用代码只维护这一份，应用相关的替换模板位于 `packer/templates/`。

```powershell
.\tools\build-runtime.ps1
```

基础应用包名为 `com.lw.web2harmony.runtime`，输出在 `runtime/dist/`，也可用配套 DevEco Studio 打开 `runtime/`。先以此工程完成真机验证，再扩展 Runtime 能力。

GUI 内部使用 `.work/` 创建基础工程的工作副本，注入用户网页/配置/图标并调用官方工具链；只向输出目录交付 HAP、SHA-256 和发行元数据。成功后清理本次内部副本，失败时保留以排障。不会复制基础工程的构建缓存，也不会把导出工程当作普通用户的最终产物。当前鸿蒙实现仍由官方 Hvigor 编译，不宣称已实现 Android 预编译 DEX 式的免编译重组。

## 工具链与 HAP

将配套官方工具链放在应用目录：

```text
toolchain/
├── command-line-tools/
│   ├── bin/hvigorw.bat
│   ├── bin/ohpm.bat
│   ├── tool/node/node.exe
│   └── sdk/
└── jdk-21/
    └── bin/java.exe
```

本地可在阅读并接受华为对应许可后导入自己下载的官方 ZIP：

```powershell
.\tools\install-toolchain.ps1 -Archive D:\downloads\command-line-tools.zip -Sha256 '<官方SHA256>' -AcceptHuaweiLicense
.\tools\setup-local-jdk.ps1
.\tools\build-local.ps1 -Sample hello
```

已核对 Windows Command Line Tools 26.0.0.851：Hvigor 6.26.8、SDK 26.0.0.105 / API 26。模板使用 modelVersion 26.0.0，最低兼容版本保留 6.0.0(20)，targetSdkVersion 为 26.0.0，配 JDK 21。手机系统版本不直接等于 API Level，真机兼容性以实际安装测试为准。

本地 HAP 构建不依赖 CI。`setup-local-jdk.ps1` 从微软官方源下载锁定 SHA-256 的便携 OpenJDK 21；`build-local.ps1` 编译桌面工具、运行测试、导出全新样例工程并构建 HAP。使用 `-Sample remote` 测试在线模式，已编译桌面工具时可加 `-SkipDesktopBuild`。工具链和 JDK 只放在项目目录，不修改系统环境；不要把它们提交到仓库或公开发行包。详细步骤见 [本地构建](docs/LOCAL-BUILD.md)。

签名体验是“首次配置，以后自动复用”，但签名资格不能照搬 Android 自签名。Android 可本地创建自签身份；商业鸿蒙真机调试需要开发者证书和包含测试设备的调试 Profile。没有材料时输出 `-unsigned.hap`，仅用于构建验证，不能直接装真机。

首次准备 P12、CER、P7B 后，在项目根目录导入；密码交互输入，不写进命令行：

```powershell
.\tools\configure-signing.ps1 -BundleName com.lw.web2harmony.runtime -StoreFile D:\private\developer.p12 -Certificate D:\private\debug.cer -Profile D:\private\debug.p7b -KeyAlias your-key-alias
.\tools\build-runtime.ps1
```

导入后材料位于 `signing/<BundleName>/`，密码使用 Windows DPAPI 加密并限制当前用户访问。GUI、`pack` 和基础 Runtime 构建会自动使用对应应用的配置；GUI 中的 Bundle Name 必须与 Profile 匹配。换 Windows 用户/电脑需重新导入密码；增加测试手机、证书过期或换应用包名时需准备匹配的有效 Profile。CI 仍支持环境变量密码，不使用本机 DPAPI 文件。不要将整个签名目录提交、打包或发送给他人。

官方流程：[申请调试 Profile](https://developer.huawei.com/consumer/cn/doc/doccenter-getting-started/agc-help-debug-profile-0000002248181278)、[DevEco Studio 自动签名](https://developer.huawei.com/consumer/cn/doc/doccenter-deveco-studio/ide-signing-auto)。

## CI、发布与真机验收

完整配置见 [docs/CI.md](docs/CI.md)，包括工具链 URL / SHA-256、许可确认、签名 Secrets 和 hdc 安装命令。

推送后 CI 先编译 Windows 工具及回归测试，再真实编译本地和在线 Demo 的 HAP。工具链变量未配置会明确失败，未签名包会明确标识。成功后生成单个发行 ZIP，附带 HAP、Windows 工具、工程模板和 SHA-256。

```bash
git add .
git commit -m "feat: bootstrap Web to HarmonyOS packer"
git remote add origin https://github.com/lxw112190/lw.Web2Harmony.git
git push -u origin main
# 等完整 CI、签名和真机测试通过后再发布：
git tag -a v0.1.0 -m "lw.Web2Harmony v0.1.0"
git push origin v0.1.0
```

## 日志

- Windows：应用目录 logs/packer.log、logs/hap-build.log。
- 鸿蒙：应用沙箱 files/logs/runtime.log、device-info.log。
- 每个日志 2 MiB、5 个归档；设备端本地时间带时区偏移。
- 第一版在页面顶部保留“导出诊断日志”按钮，合并当前日志与归档为用户选择位置的文本文件。
- 记录型号、系统/API、屏幕、App 版本、页面加载和 Console；不采集 UDID/序列号。常见密码、Token、Cookie、Authorization 脱敏，URL 移除 query/fragment。
- 前端自己打印的业务正文仍可能含隐私；分享日志前检查内容。

## 当前范围

已实现基础 Runtime 工程、GUI 单按钮打包、CLI 工程导出、资源映射、HTTP 开关、横竖屏配置、返回键、轮转日志及签名导入/自动复用。尚未实现网页文件选择/拍照、下载管理、HTML5 视频全屏回调、外部文本打开及工具链自动联网初始化。签名/安装链路在取得实际材料并真机测试前不宣称验收完成。

首台计划验收设备：Mate 80 Pro / SGT-AL00 / HarmonyOS 7.0.0.109 SP6。

## 联系与支持

作者：天天代码码天天<br>
QQ：819069052<br>
群名称：天天代码码天天<br>
群号码：264292622

如果项目对你有帮助，可以扫码支持维护：

<img src="assets/sponsor.jpg" alt="支持维护" width="220">

MIT License。第三方及工具链说明见 [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md)。
