# 素材清单

当前拳手、木箱和沙袋按用户给出的外观参考，使用 Aseprite MCP 绘制为统一的 32×32 像素图。UI、双色地格、目标、障碍、门和压板沿用原游戏与用户提供的素材包，出拳弧光来自 Effect。游戏内使用最近邻采样与整像素缩放。

## 拳击主体

可编辑源为 `assets/source/kurobox_boxing.aseprite`，尺寸 32×32，共 10 帧，包含 Shadow、Silhouette、Features 三层。实际 `get_sprite_info` 结果及帧名记录在 `assets/source/boxing_source_info.json`。

- 第 1 帧 `boxing_crate.png`：暖棕木箱，竖向木板和单根斜撑。
- 第 2 帧 `boxing_bag.png`：红色圆筒训练沙袋，带灰色挂带和小底座。
- 第 3–6 帧 `boxing_player_down/up/right/left.png`：黑发胡须、红拳套、蓝短裤的拳手。up 单独绘制背面，left 由 right 镜像。
- 第 7–10 帧 `boxing_player_punch_down/up/right/left.png`：对应方向出拳，手套向前延伸，画布与鞋底位置保持不变。

源文件的标签为 objects（1–2）、idle_directions（3–6）、punch_directions（7–10）。这些方向帧是资源索引，不应把四个朝向直接循环播放成走路动画。

全部单独 PNG 由 Aseprite `export_frame` 导出；`assets/sprites/boxing_atlas.png` 与同名 JSON 由 `export_spritesheet` 导出。源目录还保留 `boxing_preview.gif` 和放大检查图 `boxing_pixels_preview.png`。像素直接通过 `draw_pixels_at` 绘入 Aseprite，没有先用 Python 生成最终 PNG 再导入。

用户的三张参考图只用于识别斜撑、发型胡须、拳套短裤和挂带等特征。没有裁切复制 stock 预览图，也没有去除或覆盖水印。已看过整套 4 倍像素图；运行时动作与地格对比由整体验证继续确认。

## Circuit Delay

输入为网页加载的 `index.pck`，SHA-256 为 `84eff76d9e42a25a0719d4d3f4d1e24e5ffe62fe925dd6367df488141fe90862`。REA 提取记录为 `ev_ce145a9179203e28eb29c282861e836688b445acf1eb263bb30d338ace4b06e8`。资源通过 Godot 4.6 转成可读文件，没有恢复或沿用原项目代码架构。

- `assets/ui/circuit_Button_small2.png` 到 `small11.png`：16×16 小按钮，另有 quit、music、screen 及 `icon_*` 别名。
- `circuit_start_normal/hover/pressed.png`：原 `start_button1/2/3` 三态，26×20。
- `circuit_level_select1~4.png`、`circuit_select.png`、`circuit_num_under.png`：关卡选择及选中图。
- `circuit_background.png`、`circuit_background2.png`：128×128 气氛层。RGB 接近单色，Alpha 分别有 46、128 个值，使用时保留透明渐变。
- `circuit_all.png`、`circuit_stripes.png`：物件总表及条纹。绿色双色地格依据原场景取色，由表现层使用。
- `assets/sprites/ref_goal.png`、`ref_wall.png`、`ref_plate.png`、`ref_door.png`：原 Socket、灰凸台、八角底座和 X 阻挡；`ref_door_open.png` 为同一阻挡图透明度乘 0.22 的打开状态。
- `circuit_awesome9.ttf`：原包中的 Awesome 9 / Regular 字体数据，已由 Godot 4.6 读取并确认名称。


## 用户提供的素材包

`Effect.zip` 中的 `Effect/sheets/32x32.png` 保存为 `assets/effects/supplied_effects_32.png`，图集为 192×352。`ref_punch_arc_0~5.png` 裁自第 7 行，每帧 32×32。第 5 帧源格透明，可作结束帧；实际播放可使用 0–4 帧后清除。



## 声音


- `ui_confirm.ogg`：Minimalist1；`ui_back.ogg`：Minimalist2。
- `place.ogg`：Wood Block1；`undo.ogg`：Minimalist5；`goal.ogg`：Retro12。
- `wood_contact.ogg`：额外保留的 Wood Block2。

`punch.ogg` 为本项目合成的 0.16 秒短音，由衰减低频与滤波噪声组成，母版为 `punch_thud.wav`，没有第三方拳击录音。

`music.ogg` 为原创 20 秒循环，44.1 kHz 双声道、96 BPM，以低音、柔和和弦和少量敲击构成。`tools/asset_generate_music.py` 可重建。没有第三方采样或复制的旋律；尾音写回循环缓冲，边界两侧各做 22 毫秒余弦收边。

Godot 4.6 已成功解码运行 OGG。音乐解码后长度 20.000 秒，峰值 0.5520，RMS 0.1059，接缝相邻样本差 0.000336。音乐和音效尚未经主观听感评估；数值检查只用于排查解码、削波与硬切。
