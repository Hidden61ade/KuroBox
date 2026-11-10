# 素材来源与署名

## Aseprite 绘制内容

当前拳手、木箱和红筒沙袋根据用户提供的三张外观参考，在 Aseprite MCP 中重新绘制为 32×32 像素图。它们保留斜撑木箱、黑发胡须与红拳套蓝短裤、红筒灰挂带等识别特征，没有裁切复制 stock 预览图或处理水印。

可编辑源为 `assets/source/kurobox_boxing.aseprite`，有 Shadow、Silhouette、Features 三层和 10 帧，包括真背面、四向待机及四向出拳。单独文件以 `assets/sprites/boxing_` 开头；Aseprite 实际层、帧、标签信息保存在 `assets/source/boxing_source_info.json`。

## Circuit Delay

- 作品：[Circuit Delay](https://lht-hhh.itch.io/circuit-delay)
- 作者：lhthhh
- 使用内容：像素 UI、开始按钮三态、关卡选择图、透明气氛层、双色地格的场景配色、条纹、部分环境物件，以及 Awesome 9 / Regular 字体数据。

资源取自网页公开加载的 Godot 发布包，由 REA 提取并通过 Godot 4.6 转换。本项目没有恢复或沿用原游戏代码架构。这些文件属于第三方素材，不标为原创，也不据公开发布推断商业发行授权。字体原始作者与单独许可尚未从包内确认。

## Universal UI Soundpack

作者：[Nathan Gibson](https://nathangibson.myportfolio.com)
许可：[Creative Commons Attribution 4.0 International（CC BY 4.0）](https://creativecommons.org/licenses/by/4.0/)

使用 Minimalist1、Minimalist2、Minimalist5、Wood Block1、Wood Block2 和 Retro12，按事件名称分别保存为 `ui_confirm.ogg`、`ui_back.ogg`、`undo.ogg`、`place.ogg`、`wood_contact.ogg`、`goal.ogg`。文件只做事件重命名，播放时可调整音量或参数。原许可文本保存在 `assets/audio/UI_Soundpack_LICENSE.txt`。

## 用户提供的图片素材包

- `Effect.zip`：32×32 特效图集及挥击弧光帧。
- `ASSET_v0.2.zip`：物品图集中的工具等 UI 符号。

两个包内均未附作者及许可文本，当前只按用户提供的文件记录来源，不补写未知作者或授权结论。

## Sprout Lands UI Basic Pack

作者：Cup Nooble。来源为用户提供的 `Sprout Lands - UI Pack - Basic pack.zip`。当前使用 UI 图标、按钮和像素字体；兔子表情不作为当前角色。

随包 Free Basic Pack 许可允许修改，仅用于非商业项目，并禁止重新分发或转售素材（包括修改版本）。原文保存在 `assets/ui/sprout/read_me.txt`。作者随包提供的作品链接为 [Sprout Lands](https://cupnooble.itch.io/sprout-lands-asset-pack)，本项目不据此补写额外授权。

## 本项目合成声音

`assets/audio/punch.ogg` 是低频波形与滤波噪声合成的短音，母版为 `punch_thud.wav`，没有第三方拳击录音。`assets/audio/music.ogg` 是原创合成的 20 秒循环，使用低音、柔和和弦与少量敲击，没有第三方录音或复制的旋律；`tools/asset_generate_music.py` 可重建。

声音已检查解码、峰值和循环边界，尚未进行主观听感评估。逐项文件与制作记录见 [素材清单](docs/asset_manifest.md)。

## Jamkit Sokoban v2

作者：Napping Cloud Studio。来源为用户提供的 `Jamkit-Sokoban-v2.zip`。使用 Mine 图集中的目标标记和压板，裁切位置见 [Sokoban 素材记录](docs/sokoban_assets.md)。随包许可允许商业和非商业项目使用与修改，署名非必需；不允许把素材包作为素材重新销售或分发。原文保存在 `assets/source/Jamkit_Sokoban_LICENSE.txt`。
