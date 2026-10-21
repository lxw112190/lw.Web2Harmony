# lw.Web2Harmony 基础鸿蒙工程

这是独立、可编译的 ArkTS + ArkWeb 基础壳工程，不是临时导出目录。可直接用配套 DevEco Studio 打开此目录，也可在仓库根目录使用便携工具链构建：

```powershell
.\tools\build-runtime.ps1
```

默认 Bundle Name：`com.lw.web2harmony.runtime`；版本 `0.1.0`。

入口是 `entry/src/main/ets/pages/Index.ets`，基础页面在 `entry/src/main/resources/rawfile/www/`。支持本地网页、网页日志、设备诊断、视口设置和日志导出。页面通过独立 HTTPS 来源和精确资源映射加载，默认禁止任意 `file://` 访问。

修改基础网页后，先运行 `build-runtime.ps1`，它会刷新资源映射和校验清单。通过 DevEco Studio 构建时，若增加、删除或改名网页文件，也需先刷新映射。运行时通用代码只在本目录维护；`packer/templates/` 仅包含打包时替换的应用配置、Manifest 和资源映射模板。

GUI 使用此工程的源码创建内部工作副本，替换用户网页、应用配置和图标，完成 HAP 构建后把最终 HAP、SHA-256 和发行元数据写到用户选择的输出目录。不会把临时工程当作 GUI 的交付物，也不会把本工程构建缓存复制进用户包。

`dist/*-unsigned.hap` 只能验证编译与包结构，不能直接用于商业鸿蒙真机安装。基础工程真机测试请为本工程的 Bundle Name 申请证书与包含测试手机的调试 Profile，详见 [本地构建](../docs/LOCAL-BUILD.md)。不要把签名私钥、密码或已配置签名的 `build-profile.json5` 提交到仓库。
