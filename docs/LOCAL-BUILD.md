# 本地构建与真机测试

不需要安装 DevEco Studio，不需要修改系统 PATH。VS2022 C++/CMake 用于编译 Windows 工具；官方 CLT 和便携 JDK 用于编译 HAP。鸿蒙 SDK 编译成功与真机安装成功是两个独立验收步骤。

本机工程已迁移至 `E:\My-Code\lw.Web2Harmony`。迁移后需重新生成 CMake 缓存；原来的构建目录保存在 `build-before-move/`，新构建和样例在 `build/`。两个目录及工具链、日志均被 Git 忽略。

## 准备工具

在项目根目录打开 PowerShell。阅读并接受对应华为工具链许可后运行：

```powershell
.\tools\install-toolchain.ps1 -Archive 'C:\Users\Administrator\Downloads\commandline-tools-windows-x64-26.0.0.851.zip' -Sha256 ac8d0563f47f95ca78799ea4aa494fa260bc3f7c8f2a569ac629af1794b5d71c -AcceptHuaweiLicense
.\tools\setup-local-jdk.ps1
```

解压后的 CLT 约 7.5 GiB，另需 JDK 和构建缓存空间。已有导入成功的 CLT 时不必再次导入。JDK 脚本检查已部署目录并复用。下载失败时可从微软官方站点下载同版本 ZIP，使用 `setup-local-jdk.ps1 -Archive <ZIP>` 离线导入，仍验证固定 SHA-256。保留工具附带的许可文件。

```text
toolchain/
├── command-line-tools/   # 26.0.0.851, Hvigor 6.26.8, SDK API 26
└── jdk-21/               # Microsoft OpenJDK 21.0.12.1
```

## 先编译基础鸿蒙工程

`runtime/` 是正式维护的基础壳工程，不是临时生成目录。可用 DevEco Studio 打开，或运行：

```powershell
.\tools\build-runtime.ps1
```

基础包名 `com.lw.web2harmony.runtime`，输出 `runtime/dist/`。此步骤独立验证 Runtime 底座，正式真机安装前仍需要签名材料。

## GUI 与直接打包

运行 `build/Release/lw.Web2Harmony.GUI.exe`，只需设置网页、应用信息与 HAP 输出位置。GUI 不显示工程导出、SDK/JDK 路径。CLI 的同一流程是：

```powershell
.\build\Release\lw.Web2Harmony.exe pack samples/hello/project.json output
.\build\Release\lw.Web2Harmony.exe pack samples/remote/project.json output
```

输出目录可以非空，旧产物不覆盖。基础工程的内部副本创建在 `.work/`，成功后清理，失败保留；签名与工具自动查找应用目录。当前仍使用 Hvigor 真正编译 HAP，不是仅改 ZIP 或后缀。

## 开发者导出/构建样例

```powershell
.\tools\build-local.ps1 -Sample hello
.\tools\build-local.ps1 -Sample remote -SkipDesktopBuild
```

首次编译可能需要访问 ohpm/Hvigor 依赖仓库；有工具 ZIP 不代表所有工程依赖都已离线缓存。脚本为每次运行创建独立的 `build/local/<sample>-<id>`，不覆盖旧工程。产物在该工程的 `dist/`，日志在项目 `logs/hap-build.log`，2 MiB / 5 个轮转归档。桌面编译日志在 `build/logs/`，脚本使用干净子进程处理 PATH/Path 重复问题。

没有签名材料时生成 `-unsigned.hap`，它用于编译验收，不能直接作为真机安装包。

## 真机签名

建议先为基础工程 Bundle Name `com.lw.web2harmony.runtime` 准备自己的 P12 密钥库、调试证书、包含测试手机的调试 Profile。Android 可本地创建自签身份；商业鸿蒙调试材料不能由工具自行生成后冒充华为授权。可以借助 DevEco Studio 正常自动签名取得材料，或走开发者中心手动申请流程。

首次导入（密码交互输入）：

```powershell
.\tools\configure-signing.ps1 -BundleName com.lw.web2harmony.runtime -StoreFile D:\private\developer.p12 -Certificate D:\private\debug.cer -Profile D:\private\debug.p7b -KeyAlias your-key-alias
.\tools\build-runtime.ps1
```

材料存入应用目录 `signing/<BundleName>/`，当前 Windows 用户专用 ACL，密码经 DPAPI 加密。之后基础 Runtime、GUI 和 `pack` 自动寻找对应应用的配置。不能跨包名共用 Profile，其他 Windows 用户/电脑需重新导入。此导入只保存材料，不代表证书/设备授权已验证，须以实际签名和真机安装为准。

开发者仍可使用仓库外的 `signing.example.json`，在当前进程通过 `HARMONY_STORE_PASSWORD` 与 `HARMONY_KEY_PASSWORD` 环境变量提供密码：

```powershell
.\tools\build-local.ps1 -Sample hello -SkipDesktopBuild -SigningConfiguration D:\private\signing.local.json
```

脚本在临时写入签名配置时限制文件 ACL，结束后恢复原工程配置。不要分享密钥、Profile、含密码的工程配置或整个构建缓存。

## 手机安装

手机开启开发者模式和 USB 调试、允许连接后，在项目根目录运行：

```powershell
.\toolchain\command-line-tools\sdk\default\openharmony\toolchains\hdc.exe list targets
# 替换为上一步实际生成的 signed.hap 路径
.\toolchain\command-line-tools\sdk\default\openharmony\toolchains\hdc.exe install -r <signed.hap>
.\toolchain\command-line-tools\sdk\default\openharmony\toolchains\hdc.exe shell aa start -a EntryAbility -b com.lw.samples.harmonyhello
```

确认页面、中文图片和路径、JS 模块、localStorage、返回键，然后点击页面顶部“导出诊断日志”。未完成真机测试前不宣称设备兼容成功。CI 可随后验证同一份源码，不是本地测试前置条件。

安装基础 Runtime 时，将启动命令包名改为 `com.lw.web2harmony.runtime`。调试包只用于 Profile 中授权的测试设备，不是可任意分发的安装包。

官方参考：[华为命令行流水线](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-command-line-building-app)、[微软 OpenJDK 下载](https://learn.microsoft.com/zh-cn/java/openjdk/download)。
