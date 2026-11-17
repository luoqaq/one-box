# OneBox V1 模块交互原型

打开方式：

```bash
open prototypes/v1-module-details/index.html
```

视图：

- `#launcher`：工具箱汇总入口（支持按需启用/停用工具）
- `#clipboard`：剪贴板历史工作台（含历史列表、预览与工具内配置）
- `#screenshots`：截图与标注工作台（含开始截图、最近截图画廊与截图配置，兼容 `#captures`）
- `#capture`：截图选区（全屏框选与悬浮操作条）
- `#annotation`：标注编辑（深色画布）
- `#settings`：全局设置（工具插件管理、通用、全局快捷键、权限与存储）
- `#states`：异常与空状态

已验证：

- 1440×900 与 1280×800 无头 Chrome 渲染截图走查。
- 工具按需启用/停用同步、工具内配置切换、视图切换、选区拖拽与无脚本报错。
