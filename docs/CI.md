# CI：Windows 打包器验证与发布

CI 不再下载鸿蒙工具链、不编译 HAP、不读取真实签名材料。HAP 在本机用应用目录内的工具链构建，再用真机验证，见 [LOCAL-BUILD.md](LOCAL-BUILD.md)。

## CI 做什么

`desktop` 任务使用只读仓库权限：

1. 检查产品版本、CMake 版本及 PowerShell 脚本语法。
2. 校验/缓存 spdlog，编译 Windows C++ GUI、CLI。
3. 运行工程导出、Unicode 资源、日志轮转、GUI、DPAPI 凭据和模块路径隔离测试。
4. 用 JDK 21 在临时目录生成测试 P12/CSR，验证 EC-256、公钥匹配、ECDSA 签名、中文主体、密码保密、拒绝覆盖及导入流程，然后删除测试私钥。这不是向华为申请证书，也不产生真机 Profile。
5. 导出本地/在线样例工程，验证打包器的工程生成能力；不运行 Hvigor。
6. 生成一个 Windows 发行 ZIP，检查不含 HAP、私钥、证书、Profile 或 SDK，并上传最终 ZIP 与 SHA-256。Artifact 保留 7 天。

JDK 21 仅用于密钥/CSR 回归测试，不代表 CI 又在编译鸿蒙应用。普通只编译 C++ 的本机若没有 JDK，相关集成测试明确不启用；CI 显式提供 JDK，必须运行该项测试。

桌面 ZIP 包含 GUI/CLI、`runtime/` 基础工程源码、`packer/templates/`、样例、脚本、文档与校验和。不含预编译 HAP、鸿蒙 SDK/JDK 或个人签名材料。`release.json` 标明 `harmonySdkIncluded=false`、`demoHapsIncluded=false`。

## 不再需要配置的变量

本工作流不再引用 `HARMONY_CLT_URL`、`HARMONY_CLT_SHA256`、`HARMONY_SDK_LICENSE_ACCEPTED`，也不读取先前配置的 P12/CER/Profile/密码/别名 Secrets。你可以自行移除这些旧配置；本次代码修改不会替你删除 GitHub 上的变量或 Secrets。

鸿蒙许可仍适用于你在本地使用官方工具链；CI 不使用它，不等于可以忽略本地许可。

## 发布

普通推送与 PR 只执行桌面构建、测试和 Artifact 打包。只有 `push` 的 `v*` 标签才启动独立 `publish` 任务；该任务单独申请仓库写权限，从桌面任务下载最终 ZIP 后创建 GitHub Release。PR 不执行发布任务，也不获得仓库写权限。

确认本地 HAP 和真机验收通过、版本一致后再创建标签：

```powershell
git tag -a v0.1.0 -m 'lw.Web2Harmony v0.1.0'
git push origin v0.1.0
```

## 验收边界

CI 绿色只说明 Windows 工具、脚本与工程导出回归通过，不能证明 ArkTS/HAP 编译成功，更不能证明华为证书、Profile、手机安装和网页运行已经通过。

本地仍使用 CLT 26.0.0.851 / SDK API 26 / JDK 21：先编译基础 `runtime/`，再按 [SIGNING.md](SIGNING.md) 生成 P12/CSR、申请真实平台材料、导入并签名，在 Mate 80 Pro 上安装测试。未完成真机验证前不宣称设备兼容成功。
