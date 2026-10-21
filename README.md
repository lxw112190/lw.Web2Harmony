# lw.Web2Harmony

[English](README_EN.md) | 简体中文

将本地 HTML、Vue、React、Vite 构建目录或在线网址，打包为鸿蒙原生应用。

Windows C++17 / Win32 GUI 与 CLI；手机端 ArkTS + ArkWeb；使用官方 HarmonyOS Command Line Tools / Hvigor 构建 HAP。项目从 lw.Web2Android 复用成熟基础模块，独立 Git 仓库维护。

版本：v0.1.0 开发预览。当前完成桌面工具、工程生成和 CI 脚手架，鸿蒙 SDK 编译与真机安装必须通过后才算链路验收成功。

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

GUI 支持本地网页/在线网址、名称、Bundle Name、版本、PNG 图标、屏幕方向、全屏、HTTP 选项，以及工程输出目录。按钮“导出鸿蒙工程”只生成工程；“生成鸿蒙 HAP”额外调用官方构建工具。成功后打开产物目录。

输出工程目录必须为空且不能与源网页目录重叠。PNG 必须正方形、192–4096 像素。图标沿用 lw.Web2Android 内置熊猫图片，可自行替换。

CLI：

```powershell
.\build\Release\lw.Web2Harmony.exe validate samples/hello/project.json
.\build\Release\lw.Web2Harmony.exe export samples/hello/project.json build/generated/hello
.\build\Release\lw.Web2Harmony.exe export samples/remote/project.json build/generated/remote
```

Vue/Vite 建议 base: './'，使用 hash 路由。SSR 项目需先导出静态站点。默认不启用任意 file:// 访问，不注入 Native Bridge。网页 API 调用仍需服务器满足 CORS；允许 HTTP 不等于绕过跨域规则。

## 工具链与 HAP

将配套官方工具链放在应用目录：

```text
toolchain/
├── command-line-tools/
│   ├── bin/hvigorw.bat
│   ├── bin/ohpm.bat
│   ├── tool/node/node.exe
│   └── sdk/
└── jdk/
    └── bin/java.exe
```

本地可在阅读并接受华为对应许可后导入自己下载的官方 ZIP：

```powershell
.\tools\install-toolchain.ps1 -Archive D:\downloads\command-line-tools.zip -Sha256 '<官方SHA256>' -AcceptHuaweiLicense
.\build\Release\lw.Web2Harmony.exe build build/generated/hello toolchain/command-line-tools toolchain/jdk
```

模板基线为 modelVersion 6.0.0、compatible/targetSdkVersion 6.0.0(20)，配 JDK 17。升级工具链时同步检查 toolchain.lock.json，不直接把手机系统版本填入 API Level。

没有签名配置时输出 -unsigned.hap。要安装到真机，需提供开发者自己的密钥库、证书和包含测试设备的 Profile，参照 docs/signing.example.json：

```powershell
# 在当前会话安全地设置 HARMONY_STORE_PASSWORD 与 HARMONY_KEY_PASSWORD
.\build\Release\lw.Web2Harmony.exe build build/generated/hello toolchain/command-line-tools toolchain/jdk D:\private\signing.local.json
```

签名密码从环境变量读取，不写入 project.json。应用 Bundle Name 必须与签名配置一致。生成工程可用 DevEco Studio 打开、同步并配置官方自动签名。

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

已实现工程导出、资源映射、HTTP 开关、横竖屏配置、返回键、轮转日志及签名接入。尚未实现网页文件选择/拍照、下载管理、HTML5 视频全屏回调、外部文本打开及工具链自动联网初始化。

首台计划验收设备：Mate 80 Pro / SGT-AL00 / HarmonyOS 7.0.0.109 SP6。

## 联系与支持

作者：天天代码码天天<br>
QQ：819069052<br>
群名称：天天代码码天天<br>
群号码：264292622

如果项目对你有帮助，可以扫码支持维护：

<img src="assets/sponsor.jpg" alt="支持维护" width="220">

MIT License。第三方及工具链说明见 [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md)。
