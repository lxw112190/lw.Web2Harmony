# 本地生成密钥与申请真机签名

本地工具可以生成 P12 私钥库和 CSR 证书申请文件，但不能签发华为真机接受的证书或 Profile。本流程无需安装完整 IDE，仅需应用目录中的便携 JDK 21。

## 1. 生成 P12 与 CSR

在项目/应用根目录打开 PowerShell，按平台要求填写申请者信息：

```powershell
.\tools\create-signing-request.ps1 -BundleName com.lw.web2harmony.runtime -CommonName '天天代码码天天'
```

交互输入并确认至少 8 位密码，不要把密码放进命令行。默认生成目录：

```text
signing/requests/com.lw.web2harmony.runtime/
├── developer.p12             # 私钥库：保密并备份，不能提交或分享
├── developer.csr             # 证书申请：提交给华为证书申请页面
├── credentials.dpapi.json    # 当前 Windows 用户加密的密码：保密
└── request.json              # 别名、算法、哈希和完成标记；无明文密码
```

可选参数：`-KeyAlias`、`-Organization`、`-Country`、`-OutputDirectory`、`-JavaHome`。默认别名 `web2harmony`，算法 EC / secp256r1 / SHA256withECDSA，密钥库格式 PKCS12。PKCS12 使用相同的库密码和私钥密码。目录已存在时拒绝覆盖，避免把已有应用的签名身份换掉。

P12 内部会包含 keytool 创建的占位自签证书，它不是华为签发的调试证书，也不授予真机安装资格。工具不会创建伪装成华为证书的 `.cer` 或 Profile。

密码临时通过子进程环境传给 keytool，结束后恢复原环境；磁盘只保存 DPAPI 加密值。请求目录限制为当前 Windows 用户访问。日志在 `logs/signing-request.log`，本地时间、2 MiB / 5 个轮转归档，不记录密码；中文主体和路径使用 UTF-8。

## 2. 向华为申请证书和 Profile

1. 在华为开发者中心准备对应应用，Bundle Name 与打包配置一致。
2. 在申请调试证书时上传 `developer.csr`，下载平台签发的 `.cer`。不要上传 P12 私钥库或密码文件。
3. 注册测试手机，申请包含该设备、对应应用和证书的调试 Profile，下载 `.p7b`。

此步骤需要你使用自己的开发者账号完成。生成本地文件不表示平台申请已获批准。

官方流程：[申请调试证书](https://developer.huawei.com/consumer/en/doc/app/agc-help-add-debugcert-0000001914263178)、[申请调试 Profile](https://developer.huawei.com/consumer/cn/doc/doccenter-getting-started/agc-help-debug-profile-0000002248181278)。

## 3. 导入平台返回的材料

使用刚才的请求目录即可复用已加密保存的密码，无需重新输入：

```powershell
.\tools\configure-signing.ps1 -BundleName com.lw.web2harmony.runtime -RequestDirectory .\signing\requests\com.lw.web2harmony.runtime -Certificate D:\private\debug.cer -Profile D:\private\debug.p7b
.\tools\build-runtime.ps1
```

导入前会检查请求完成标记、应用包名，以及 P12/CSR 是否被修改。材料保存到 `signing/<BundleName>/` 后，GUI、`pack`、基础 Runtime 构建自动复用。已存在的正式配置不覆盖，请先在私有位置备份，再明确决定是否更换。

已有其他工具生成的 P12 仍可手动导入：

```powershell
.\tools\configure-signing.ps1 -BundleName com.lw.web2harmony.runtime -StoreFile D:\private\developer.p12 -Certificate D:\private\debug.cer -Profile D:\private\debug.p7b -KeyAlias your-key-alias
```

此方式交互输入库密码和私钥密码。导入只保存材料，不代表证书有效性、平台签发和设备授权已经验证；须以真实签名与真机安装为准。

## 4. 保密与备份

只有 CSR 应提交到证书申请页面。P12 和密码必须做好独立的安全备份；DPAPI 文件通常不能在另一台电脑或另一个 Windows 用户下解密，不能把它当作唯一备份。换电脑时使用原 P12 和你保管的密码重新导入，不要为了迁移随意重新生成密钥。

换应用包名、增加手机、证书/Profile 到期时，按华为要求更新匹配材料。不要把 `signing/`、工作缓存、私钥、密码放入 Git、公开 ZIP、GitHub Actions Secrets 或 Artifact。当前 CI 不读取真实签名材料。

实现参考：[JDK 21 keytool](https://docs.oracle.com/en/java/javase/21/docs/specs/man/keytool.html)。
