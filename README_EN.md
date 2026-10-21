# lw.Web2Harmony

English | [简体中文](README.md)

Convert local HTML/Vue/React/Vite static output or a remote URL into a native HarmonyOS application.

Windows C++17 GUI/CLI, an ArkTS + ArkWeb runtime, and official Hvigor HAP builds. Shared foundations were copied from lw.Web2Android into an independent repository.

v0.1.0 is a development preview. Desktop compilation and project generation are implemented; the first official SDK CI run and real-device acceptance remain required.

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
.\build\Release\lw.Web2Harmony.exe build build/generated/hello toolchain/command-line-tools toolchain/jdk
```

Use an empty output directory outside the Web source. Set Vite base to './' and use hash routing. HTTP requires explicit opt-in and does not bypass CORS.

The initial template targets modelVersion 6.0.0 and SDK 6.0.0(20), using matching official Command Line Tools and JDK 17. A phone OS version is not an SDK API level.

## CI and signing

[CI setup](docs/CI.md) documents the required official toolchain URL, SHA-256 and license acceptance repository variables. Missing setup fails the HAP job explicitly.

Unsigned HAPs cannot be used as signed real-device test packages. Import your own P12, certificate and device-specific debug Profile. Six GitHub Secrets configure local-demo signing; remote-demo HAPs remain unsigned.

The pipeline compiles Windows tools, runs export/Unicode/logging regression tests, builds actual local and remote HAPs, checks their structure, and packages one final ZIP. Tagged releases require that pipeline to pass.

Public distributions exclude Huawei SDK, JDK and private signing materials.

## Diagnostics

Windows logs live under the application logs directory. Runtime and device diagnostics use local timestamps, 2 MiB rotation and five archives. The mobile diagnostic toolbar exports current and archived files to a user-selected document.

Logs redact common secrets and remove URL queries/fragments. Device UDID and serial numbers are not collected. Review application Console text before sharing diagnostics.

File chooser/capture, downloads, video fullscreen callbacks, external text integration and automatic online toolchain initialization are not implemented in this first preview.

Planned first test device: HUAWEI Mate 80 Pro, HarmonyOS 7.0.0.109 SP6. Compatibility is not claimed before successful installation and testing.

MIT License, Copyright (c) 2026 天天代码码天天.
