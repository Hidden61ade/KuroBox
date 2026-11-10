# Jamkit Sokoban 素材接入

本次只采用目标标记和压板两张图，作者为 **Napping Cloud Studio**。源包是用户提供的 `C:\Users\yhxx3\Downloads\Jamkit-Sokoban-v2.zip`，作者地址见包内许可：[nappingcloud.itch.io](https://nappingcloud.itch.io/)。

两张图均从 `Pack/Mine/Objects.png` 裁切。原图尺寸为 64×112 像素，以左上角为坐标原点，区域按 `x, y, width, height` 记录：

- `assets/sprites/sokoban_goal.png`：`48, 0, 16, 16`。白色四角及斜线标记，用作关卡目标格，替代容易被误认成实体障碍的图案。
- `assets/sprites/sokoban_plate.png`：`48, 16, 16, 16`。米黄色底、红色中心的按钮图案，用作压力板。压下状态由本项目表现层处理，源包未提供经确认的配对状态。

导出保持原始 16×16 像素和透明通道，没有缩放、重绘或调色。游戏内使用最近邻采样。文件名表达的是本项目的用途，源图集没有为每一格单独标注机制名称。

包内 `_Sprite Asset License.pdf` 的许可原文已提取至 `assets/source/Jamkit_Sokoban_LICENSE.txt`：允许商业及非商业项目使用和修改，署名非必需；禁止把原包或修改后的素材包作为素材包再次销售、分发或重新打包。

门的开启与关闭配对未确认，因此不采用 Mine 图集中的门候选。`Objects.png` 的 `32, 16, 16, 16` 区域是梯子，不用作开门图。此次也不替换墙、角色、木箱、沙袋、原双色地格或界面素材。
