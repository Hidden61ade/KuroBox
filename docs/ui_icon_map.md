# 当前界面图标

界面图标使用解包资源和用户提供的素材包。出拳图标在 Aseprite 中绘制。来源与构图记录在 `assets/source/reference_mapping.json`，`assets/ui/` 下的 `icon_*.png` 可直接加载。

## 原 Circuit Delay 按钮

- `circuit_start_normal/hover/pressed.png`：原 `start_button1/2/3`，26×20。用于开始；保留原来的三态，不再加文字大按钮框。
- `circuit_quit_normal/hover.png`、`icon_exit.png`、`icon_quit.png`、`icon_back.png`：原 `Button_small2/3`，16×16，门和向外箭头。项目用于退出当前页、回到上层；不要同时把相同图案放成两个不同动作。
- `circuit_music_normal/hover.png`、`icon_volume.png`、`icon_music.png`：原 `Button_small4/5`，16×16，喇叭。
- `circuit_screen_normal/hover.png`、`icon_fullscreen.png`：原 `Button_small8/9`，16×16，屏幕与四角。
- `icon_undo.png`：原 `Button_small10`；`icon_undo_hover.png`：原 `Button_small11`，均为 16×16。原 `level.scn` 的 `./UI/before` 使用这组回退箭头，对应 Z。pressed 使用 normal 图。
- `icon_restart.png`：原 `Button_small6`；`icon_restart_hover.png`：原 `Button_small7`，均为 16×16。原 `./UI/replay` 使用这组圆形重来箭头，对应 R。pressed 使用 normal 图。
- `icon_play.png`、`icon_next.png`：原开始按钮 normal 的别名，26×20，红色圆形内有播放箭头。

## 原底部快捷键

核对来源为 `evidence/circuit_static_resources.json` 中的原 `level.scn`，只读取静态场景资源。底部从左到右为 before、replay、screen、music、quit；在原 320×180 视口中的左上角分别为 `(88,156)`、`(104,156)`、`(168,156)`、`(184,156)`、`(200,156)`，按钮均为 16×16。

Z、R、Q 并非画在键位 PNG 中。三个 Sprite2D 都用 `key.png` 作底，位置分别为 `(95,175)`、`(111,175)`、`(208,175)`；各自子 Label 文本为 Z、R、Q，局部 scale 为 `(0.5,0.5)`，offset 为 left/top `-4`、right/bottom `14`，水平与垂直均居中。原 Shortcut 的 keycode 分别为 90、82、81。

全局 `gui/theme/custom_font` 是 `uid://gnxotfiyv8js`，与原包 `Awesome 9.ttf.import` 的 UID 一致，指向 Awesome 9 字体。项目已导出为 `assets/ui/circuit_awesome9.ttf`。原 Label 没有独立字号覆盖，Godot 4.6 默认 Label 字号实测为 16；复现时可保留 16 号再缩半的处理。

`circuit_key.png` 和 `circuit_key1.png` 是 16×16 画布中央的 6×6 黑底，没有字母；`circuit_key2.png` 只额外包含 6 个白像素，是空格样式，也不含 Z/R/Q。

## Sprout 与 ASSET 符号

- `icon_levels.png`：Sprout `all_icons.png` 的米色领奖台，区域 `(144,16,16,16)`，项目用于关卡入口。
- `icon_settings.png`：同图米色齿轮，区域 `(144,0,16,16)`。
- `icon_check.png`：同图勾号，区域 `(144,32,16,16)`。
- `icon_import.png`：同图加号，区域 `(96,32,16,16)`，项目用于加入外部关卡。
- `icon_info.png`：同图问号，区域 `(160,0,16,16)`。
- `icon_pause.png`：从 Sprout `settings_buttons.png` 的 `(6,178,4,12)` 裁出已有竖条，在透明 16×16 画布上摆放两份，位置为 `(3,1)` 和 `(9,1)`。这是现有像素的组合。
- `icon_workshop.png`：ASSET 总表中的镐，区域 `(64,0,16,16)`，项目用于编辑工具入口。

## 出拳图标

`icon_punch.png` 为透明背景的 16×16 像素图。红拳套左侧是短护腕，右侧是宽拳峰，下方留有拇指轮廓，暖白色箭头指向右方。可编辑源 `assets/source/kurobox_punch_icon.aseprite` 包含 Glove、Cuff 与 Motion Arrow 三层。底栏以 48×48 显示图标，下方是小 SPACE 键帽。

没有找到明确的震动图标，当前不提供 `icon_shake.png`，保留系统字形或短标签。16×16 图标使用最近邻采样、整数倍显示；26×20 原开始按钮按原比例缩放。悬停可以调整亮度，不再套一层厚框。
