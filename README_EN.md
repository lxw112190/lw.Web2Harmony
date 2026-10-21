# lw.Web2Harmony

English | [简体中文](README.md)

Convert local HTML/Vue/React/Vite static output or a remote URL into a native HarmonyOS application.

Windows C++17 GUI/CLI, an ArkTS + ArkWeb runtime, and official Hvigor HAP builds. Shared foundations were copied from lw.Web2Android into an independent repository.

v0.1.0 is a development preview. Windows GUI/CLI builds, export tests, and local/remote sample HAP builds and package checks have passed locally with official CLT 26.0.0.851. Device signing, installation, and runtime acceptance remain pending.

## Desktop build

```powershell
cmake -S . -B build -A x64 -DBUILD_TESTING=ON
cmake --build build --config Release --parallel
ctest --test-dir build -C Release --output-on-failure
.\build\Release\lw.Web2Harmony.GUI.exe
```

VS2022 Desktop development with C++ and CMake are required. HarmonyOS SDK is not needed to compile the desktop tools or export projects.

```powershell
.\build\Release\lw.Web2Harmony.exe export samples/hello/project.json build/generated/hello
.\tools\setup-local-jdk.ps1
.\tools\build-runtime.ps1
.\build\Release\lw.Web2Harmony.exe pack samples/hello/project.json output
.\tools\build-local.ps1 -Sample hello
```

The GUI is packaging-only: Web source, app settings, icon and HAP output directory, followed by one Build HAP button. SDK/JDK paths and project export are developer details, not GUI fields. Tools are discovered under the application directory. Outputs contain the HAP, SHA-256 and release metadata; repeated builds preserve previous outputs with numbered names. Only the developer CLI `export` command requires an empty directory. Set Vite base to './' and use hash routing. HTTP requires explicit opt-in and does not bypass CORS.

`runtime/` is the standalone, buildable ArkTS + ArkWeb base project (`com.lw.web2harmony.runtime`). Shared runtime code lives there; `packer/templates/` contains only app-specific replacement templates. The packer creates a private `.work/` copy, injects user assets/settings, invokes Hvigor and publishes final HAP files. Success cleans the workspace; failure keeps it for diagnosis. It is not yet an Android-style precompiled DEX reassembly pipeline.

The pinned Windows CLT is 26.0.0.851 (Hvigor 6.26.8, SDK 26.0.0.105 / API 26). The template uses modelVersion 26.0.0, minimum SDK 6.0.0(20), target SDK 26.0.0, and JDK 21. A phone OS version is not an SDK API level. Device compatibility still requires installation testing.

Local HAP builds do not require CI. Import the official CLT ZIP with `tools/install-toolchain.ps1` after accepting its license. `setup-local-jdk.ps1` downloads a SHA256-pinned portable Microsoft OpenJDK into `toolchain/jdk-21`; no system installation or environment changes are made. `build-local.ps1` builds/tests desktop tools and compiles a fresh sample project (`-Sample hello` or `remote`). See [local build instructions](docs/LOCAL-BUILD.md). Keep toolchains and signing materials out of public distributions.

## CI and signing

[CI setup](docs/CI.md) documents the required official toolchain URL, SHA-256 and license acceptance repository variables. Missing setup fails the HAP job explicitly.

Unsigned HAPs cannot be used as signed real-device test packages. Import your own P12, certificate and device-specific debug Profile. Six GitHub Secrets configure local-demo signing; remote-demo HAPs remain unsigned.

For local use, run `tools/configure-signing.ps1 -BundleName <bundle> -StoreFile <p12> -Certificate <cer> -Profile <p7b> -KeyAlias <alias>`. Passwords are entered securely and Windows DPAPI-protected for the current user. The GUI and `pack` automatically reuse `signing/<bundle>/signing.local.json`; the base Runtime build does likewise. Re-import credentials on another Windows account/computer. Import does not grant device eligibility: Huawei-issued certificates and a matching Profile authorizing the device are still required. No locally self-signed identity is claimed to replace Huawei authorization.

The pipeline compiles Windows tools, runs export/Unicode/logging regression tests, builds actual local and remote HAPs, checks their structure, and packages one final ZIP. Tagged releases require that pipeline to pass.

Public distributions exclude Huawei SDK, JDK and private signing materials.

## Diagnostics

Windows logs live under the application logs directory. Runtime and device diagnostics use local timestamps, 2 MiB rotation and five archives. The mobile diagnostic toolbar exports current and archived files to a user-selected document.

Logs redact common secrets and remove URL queries/fragments. Device UDID and serial numbers are not collected. Review application Console text before sharing diagnostics.

File chooser/capture, downloads, video fullscreen callbacks, external text integration and automatic online toolchain initialization are not implemented in this first preview.

Planned first test device: HUAWEI Mate 80 Pro, HarmonyOS 7.0.0.109 SP6. Compatibility is not claimed before successful installation and testing.

MIT License, Copyright (c) 2026 天天代码码天天.
