# KuroBox

一款拳馆里的格子解谜游戏。推木箱，击打沙袋，再借压板打开通路。角色站在哪里、物件停在哪里，是每关要解决的问题。

项目使用 Godot 4.6 和 GDScript，包含八个关卡、开始与选关界面、暂停、设置、通关结算和关卡工坊。通关记录、最好步数与设置保存在 `user://profile.json`；保存时保留备份。

## 运行和操作

用 Godot 4.6 打开 `project.godot`，按 F5 运行。完整流程的入口是 `features/shell/main.tscn`，工坊可以单独按 F6 运行。桌面端使用键盘和鼠标，窗口可缩放，F11 切换全屏。

开始界面中，红色播放按钮进入训练，领奖台选择关卡，镐头打开工坊。图标悬停显示名称和快捷键。游玩时只显示关卡编号和操作图标，说明保留在本文与工坊中。

- 方向键或 WASD 移动；靠近木箱后继续向前即可推一格。
- Space 朝当前方向出拳。沙袋最多前进两格，遇阻提前停下，角色留在原地；拳头不会隔着物件传递，也不会推动木箱。
- Z 撤销，R 重开，Esc 暂停。无效动作不计步，撤销会一起还原朝向和机关状态。
- 把所有目标格占满即可过关。目标格不会让飞行中的沙袋自动停下。

主菜单可以进入关卡工坊，选关页也能导入外部 JSON 直接游玩。设置中可调整声音、背景音乐音量和屏幕震动。

## 编辑关卡

工坊按格绘制地图，宽高为 4–24 格。地板可以画成不规则形状，再分别摆放墙、目标、出生点、木箱、沙袋和机关。右键只擦当前图层，避免顺手删掉其他内容。

画笔 B、擦除 E、矩形 R、填充 F、框选 S、移动 M、粘贴 V；Ctrl+Z 撤销，Ctrl+Y 或 Ctrl+Shift+Z 重做。框选复制会重新分配物件 ID，连在选区内部的门和压板会一起复制；移动则保留原 ID。选区越界时整笔拒绝。

选中压板后，用“连线到门”点击目标门，也可以在属性区勾选。F5 立即测试当前文档，Esc 返回编辑。试玩用的是文档副本，玩家和物件的移动不会写回关卡。也可以单独运行 `features/editor/editor.tscn`，不用先经过主菜单。

导出格式为 `.kuro.json` 或 `.json`。测试和导出前都会检查坐标、叠放和机关引用；点击错误可以定位到棋盘。检查通过只表示文件结构有效，不保证谜题可解。未导出的修改会提示保留或放弃。详细行为见 [关卡工坊说明](docs/editor_workflow.md)。

## 内容怎样扩展

关卡初始布局保存在 `content/levels/`，正式关卡的顺序由其中的 `campaign.json` 决定。标题可以修改，关卡 ID 应保持稳定，存档依赖这个 ID。内置关卡的 `metadata.solution` 记录 U/D/L/R/P 解法命令，测试用实际规则重放它们。

物件目录在 `content/definitions/objects.json`。同一份定义供规则、编辑器和画面读取。增加已有行为的变体时，可添加稳定类型 ID、参数与贴图；增加新行为还需要在 `core/board_state.gd` 实现规则，在 `core/level_codec.gd` 补校验，再添加规则测试。登记名称不会自动生成新玩法。

职责按修改原因划分：

- 内容作者维护关卡文件和机关连线；编辑器负责文档、撤销历史与导入导出。
- 规则程序维护 `BoardState`、物件目录和格式校验。这里不依赖动画或物理帧率。
- 木箱、拳击手和沙袋在 Aseprite 中绘制，源文件为 `assets/source/kurobox_boxing.aseprite`。UI、环境和特效的现成资源裁切见 `assets/source/reference_mapping.json`。表现集中在 `features/play/board_view.gd`。
- 音频事件映射在 `features/shell/audio_service.gd`；菜单、存档和场景切换由 `features/shell/` 维护。

关卡定义、运行状态和编辑状态各自保存。试关与正式游玩使用同一个 `BoardState`，避免编辑器里能用、发布后规则却不同。格式有版本，未知版本和坏数据会报错。更多说明见 [实现约定](docs/architecture.md) 与 [接口及关卡格式](docs/implementation_contract.md)。

## 检查

在项目目录执行，下面的 `Godot` 指 Godot 4.6 控制台程序：

```powershell
Godot --headless --path . --log-file "$PWD/evidence/import.log" --editor --quit
Godot --headless --path . --log-file "$PWD/evidence/core.log" --script res://tests/test_core.gd
Godot --headless --path . --log-file "$PWD/evidence/editor.log" --script res://tests/test_editor.gd
Godot --headless --path . --log-file "$PWD/evidence/flow.log" --script res://tests/test_flow.gd
```

核心检查覆盖碰撞、沙袋位移、机关、撤销、坏数据和八关记录解法；编辑器检查覆盖图层、整笔撤销、复制移动、连线与试关副本。脚本输出检查数和失败项，失败时返回非零退出码。自动重放能证明已有布局存在解法，新手是否能看懂、声音是否合适，仍需要试玩判断。

当前不含关卡求解器、手柄操作或在线关卡分享。背景音乐为本项目合成的 20 秒循环，音乐与音效的最终音量和听感仍需要实际试听。第三方 UI、字体和声音的来源及署名见 [CREDITS](CREDITS.md)；逐项资源记录见 [素材清单](docs/asset_manifest.md)。

## 视觉与导出

双色地格直接使用 Circuit Delay 原包的两张 16 像素纹理，按格子坐标奇偶交替。背景平铺同包的斜条纹，持续滚动，并叠加原透明气氛层。滚动速度是本项目的可调参数，原脚本速度未恢复。转场的 11 条斜带、颜色键和两个 0.46 秒动画来自原场景静态轨道，换场发生在全遮盖时。

一键检查：`./tools/validate.ps1 -GodotBin "Godot 4.6 控制台程序路径"`。

导出 Windows：`./tools/export_windows.ps1 -GodotBin "Godot 4.6 控制台程序路径" -FetchTemplates`。该开关从 Godot 官方发布包只取 Windows 模板，校验成员 CRC 并记录 SHA-256；不会安装到全局目录。已有模板时不需要该开关。输出在 `builds/windows/KuroBox.exe`，导出后会在实际 release runtime 中重放八关并检查工坊试玩隔离。

源码、可编辑素材和关卡提交到 Git；`.godot`、运行存档、模板和本地构建不提交。最新检查结果见 `evidence/validation_summary.json`。自动检查证明的范围与首次试玩、音频听感分别记录。
