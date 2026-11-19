# Windows SteamPipe 内容目录

从经过校验的 Windows 构建生成同一版本的 SteamPipe 目录。运行程序、PCK、版本清单及三份授权文件都放在 content 下，EXE 和 PCK 处于同一层。STAGING_INFO.json 记录源提交、启动文件、各文件长度和 SHA-256。应用构建脚本留在 scripts 中，SteamPipe 的中间文件写入 output。 [Steamworks 构建脚本说明](https://partner.steamgames.com/doc/sdk/uploading)

GitHub 的 MSI 供直接安装。SteamPipe 使用同一构建的游戏文件，由 Steam 客户端负责部署和更新。

~~~powershell
powershell -NoProfile -File tools/stage_steam.ps1 -BuildDirectory build/<本次构建目录>
~~~

构建机上已有 App ID 和 Windows Depot ID 时，可加 -AppId 和 -WindowsDepotId 生成对应的 VDF。省略两项会生成带占位符的 app_build.vdf.template。VDF 使用 Preview 模式，供账号持有人先核对文件清单。Steamworks 的 Windows 启动文件填 SigilsAndOaths.exe。 [Steamworks 安装设置与预览模式](https://partner.steamgames.com/doc/sdk/uploading)

把整份 content 复制到新目录也可以在本机双击 EXE 验证开发包。Steam 平台下载安装仍需在授权的测试分支走一遍，检查新装首次启动、存档位置及补丁更新后读档。商店预告、截图及内容披露是商店素材。 [商店素材与披露](README.md) · [Steam 测试](https://partner.steamgames.com/doc/store/testing)

已测环境为 Windows x64 25H2（内部版本 26200）、RTX 4060 Laptop GPU，Godot Compatibility 的 OpenGL 3.3 路径。原生界面已检查 1008×700 和 1920×1080。最低硬件配置仍需在低配 Windows 设备上测定。
