# CI 与真机测试

本项目采用 Windows 工具本地开发、GitHub Actions 编译鸿蒙 HAP、Mate 80 Pro 真机验证的流程。

## 一次性配置

从华为官方下载与模板基线配套的 Command Line Tools（开发态 modelVersion 6.0.0、目标 6.0.0(20)、JDK 17）。请确认该版本在提供的 SDK 中可用。HarmonyOS 7.0 是手机系统版本，不能直接作为 SDK API Level。

在 GitHub 仓库 Settings → Secrets and variables → Actions → Variables 添加：

| Variable | 内容 |
| --- | --- |
| HARMONY_CLT_URL | 配套 Windows x64 官方工具链 ZIP 的 HTTPS 地址 |
| HARMONY_CLT_SHA256 | 官方页面提供的 ZIP SHA-256，64 位十六进制 |
| HARMONY_SDK_LICENSE_ACCEPTED | 阅读并接受对应华为许可后设为 true |

这里不填写未经验证的下载地址。首次 CI 必须配置以上变量，缺失会明确失败，不能把工程导出成功当作 HAP 编译成功。每次使用缓存仍校验压缩包 SHA-256。工具链只在构建环境使用，不装进公开发行包。

## 真机签名

未配置签名时 CI 构建未签名 HAP，不能直接用于商业鸿蒙真机安装。

为本地 Demo 的包名 com.lw.samples.harmonyhello 创建应用，申请调试证书、注册设备并申请包含该设备的调试 Profile。通过平台或 DevEco Studio 正常准备材料。添加六项 GitHub Secrets：

- HARMONY_P12_BASE64：密钥库文件的 Base64。
- HARMONY_CERT_BASE64：调试证书文件的 Base64。
- HARMONY_PROFILE_BASE64：包含测试设备的调试 Profile 文件的 Base64。
- HARMONY_KEY_ALIAS：密钥别名。
- HARMONY_STORE_PASSWORD：密钥库密码。
- HARMONY_KEY_PASSWORD：私钥密码。

PowerShell 生成文件 Base64（输出是敏感材料，仅放入 Secrets）：

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes('D:\private\developer.p12'))
```

六项必须全部配置，否则 CI 拒绝构建，避免误生成未签名包。只对本地 Demo 使用这套身份；在线 Demo 保持未签名，换包名需对应 Profile。

密钥不会进入源码或 Artifact，临时签名配置会在构建后恢复，密钥文件由 always 清理步骤移除。不要上传包含密码的 build-profile.json5。

## 编译与验收

1. 推送 main，等待 desktop、hap、package 三个任务成功。
2. 下载唯一最终 ZIP，demo-haps/local 下以 -signed.hap 结尾的文件用于已注册设备。
3. hdc 连接手机并安装；不要把未签名包改名后当作已签名包。
4. 在手机验证中文页面、JS 模块、图片、localStorage、返回键及中文路径。
5. 点击页面顶部“导出诊断日志”，把包含 device-info.log / runtime.log 的诊断文本发回分析。

```powershell
hdc list targets
hdc install -r .\com.lw.samples.harmonyhello-signed.hap
hdc shell aa start -a EntryAbility -b com.lw.samples.harmonyhello
```

截图设备：HUAWEI Mate 80 Pro，SGT-AL00，HarmonyOS 7.0.0.109 SP6。当前设备的 API Level 由安装后 device-info.log 记录；未做真机验证前不宣称兼容成功。

## 官方参考

- https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-command-line-building-app
- https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-hvigor-commandline
- https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/web-page-loading
- https://developer.huawei.com/consumer/cn/doc/doccenter-getting-started/agc-help-debug-profile-0000002248181278
