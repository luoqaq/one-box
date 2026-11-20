---
name: reload-onebox
description: >-
  Packages OneBox and replaces the running macOS app in place (quit old process,
  open Scripts/build/OneBox.app). Use when finishing OneBox UI or native changes
  that need a fresh .app, or when the user asks to 打包替换、热更新、reload、
  替换当前 APP、重新打开 OneBox — do not ask the user to quit and reopen manually.
---

# Reload OneBox（打包并替换当前 App）

## 何时用

OneBox 相关改动需要验证真机 UI / 菜单栏 / Dock 时，**开发收尾默认走本流程**，不要让用户自己退出再双击。

触发词示例：打包替换、reload、热更新、替换当前 APP、重新打开看看。

## 怎么做

在仓库根目录用 Shell 执行（**必须** `required_permissions: ["all"]`：签名、杀进程、`open` 在沙箱里会失败；不要用 smart-mode 审批卡凑合）：

```bash
./Scripts/reload-app.sh
```

行为顺序（不要改）：

1. 先 `package-app.sh` 打出新包（构建失败则**不**杀旧进程）
2. 对 `com.onebox.app` / `OneBox` 优雅退出，必要时 SIGTERM
3. `open Scripts/build/OneBox.app`，确认新 pid

仅替换已有包、不再编译：

```bash
./Scripts/reload-app.sh --no-build
```

若 `swift build` / `package-app.sh` 单独跑也因嵌套 `sandbox-exec` 失败，同样加 `required_permissions: ["all"]`，或对 `swift` 加 `--disable-sandbox`。

改了方案 A 图标资源后，先 `./Scripts/gen-icon.sh`，再 `./Scripts/reload-app.sh`。

## 代理约束

- 改完需要用户看效果时：**主动跑** `reload-app.sh`，不要只写「请退出后重新打开」。
- **Shell 一律带 `required_permissions: ["all"]`**，不要省略；若仍被沙箱拦住再带同参重试。本仓库 `.cursor/sandbox.json` 为 `insecure_none`；若会话仍提示审批，让用户在 **Cursor Settings → Agents → Approvals & Execution** 选 **Run Everything**，或把 `./Scripts/reload-app.sh` 加入 Command Allowlist。
- 不要用 `kill -9` 作为默认路径；脚本已处理优雅退出。
- 不要同时开多个 OneBox；替换前确保旧进程已退出。
- 验证：脚本打印新 pid，或确认菜单栏 / Dock 已是新实例。

## 不要用本 skill 的情况

- 只跑单元测试：`./Scripts/run-tests.sh`
- 只编译不启动：`swift build` 或 `./Scripts/package-app.sh`
