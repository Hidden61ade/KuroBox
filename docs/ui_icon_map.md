# 当前界面图标

界面图标使用解包资源和用户提供的素材包；出拳图标取自本项目 Aseprite 拳手的红拳套。裁切与组合记录在 `assets/source/reference_mapping.json`，`assets/ui/` 下的 `icon_*.png` 可直接加载。

## 原 Circuit Delay 按钮

- `circuit_start_normal/hover/pressed.png`：原 `start_button1/2/3`，26×20。用于开始；保留原来的三态，不再加文字大按钮框。
- `circuit_quit_normal/hover.png`、`icon_exit.png`、`icon_quit.png`、`icon_back.png`：原 `Button_small2/3`，16×16，门和向外箭头。项目用于退出当前页、回到上层；不要同时把相同图案放成两个不同动作。
- `circuit_music_normal/hover.png`、`icon_volume.png`、`icon_music.png`：原 `Button_small4/5`，16×16，喇叭。
- `circuit_screen_normal/hover.png`、`icon_fullscreen.png`：原 `Button_small8/9`，16×16，屏幕与四角。
- `icon_restart.png`、`icon_undo.png`：原 `Button_small6`，16×16，回转箭头。当前是同一图片的两个语义别名；同屏同时提供时，应以位置或悬停名称区分。
- `icon_play.png`、`icon_next.png`：原开始按钮 normal 的别名，26×20，红色圆形内有播放箭头。

## Sprout 与 ASSET 符号

- `icon_levels.png`：Sprout `all_icons.png` 的米色领奖台，区域 `(144,16,16,16)`，项目用于关卡入口。
- `icon_settings.png`：同图米色齿轮，区域 `(144,0,16,16)`。
- `icon_check.png`：同图勾号，区域 `(144,32,16,16)`。
- `icon_import.png`：同图加号，区域 `(96,32,16,16)`，项目用于加入外部关卡。
- `icon_info.png`：同图问号，区域 `(160,0,16,16)`。
- `icon_pause.png`：从 Sprout `settings_buttons.png` 的 `(6,178,4,12)` 裁出已有竖条，在透明 16×16 画布上摆放两份，位置为 `(3,1)` 和 `(9,1)`。这是现有像素的组合。
- `icon_workshop.png`：ASSET 总表中的镐，区域 `(64,0,16,16)`，项目用于编辑工具入口。

## 红拳套

`icon_punch.png` 为透明背景的 16×16 图标，由 Aseprite MCP 从本项目的新拳手原像素裁切组合：红拳套取 `boxing_player_punch_up.png` 的 `(21,0,9,7)`，放在 `(3,3)`；护腕取 `boxing_player_down.png` 的 `(7,22,2,2)`，放在 `(7,10)`。没有新增绘制像素，也不再使用木盾。可编辑源为 `assets/source/kurobox_punch_icon.aseprite`，分为 Glove 与 Cuff 两层，由 Aseprite `export_sprite` 直接导出。

没有找到明确的震动图标，当前不提供 `icon_shake.png`，保留系统字形或短标签。16×16 图标使用最近邻采样、整数倍显示；26×20 原开始按钮按原比例缩放。悬停可以调整亮度，不再套一层厚框。
