# docs/screenshots

README / Wiki 使用的界面展示图。这些图由 [showcase.html](showcase.html) 按应用真实 UI
（`lib/ui/theme/app_theme.dart` 配色、`lib/l10n/app_strings.dart` 双语文案）1:1 复刻后，
用无头 Chrome 渲染生成；界面改动后可重新生成保持同步。

`showcase-zh.png` / `showcase-en.png` 为四屏横幅（首页 · Wi-Fi 房 · 蓝牙 PTT 房 · 房内消息），
分别用于中文 / 英文 README；`screen-*.png` 为单屏图，供 Wiki 页面引用。

重新生成（任意安装了 Chrome 的机器）：

```powershell
$chrome = "C:\Program Files\Google\Chrome\Application\chrome.exe"
$url    = "file:///" + (Resolve-Path "showcase.html").Replace("\", "/")

# 横幅（中 / 英）
& $chrome --headless=new --disable-gpu --no-first-run --hide-scrollbars `
  --default-background-color=00000000 --force-device-scale-factor=2 `
  --window-size=1360,708 --screenshot="$PWD\showcase-zh.png" "$url?mode=all&lang=zh"
& $chrome --headless=new --disable-gpu --no-first-run --hide-scrollbars `
  --default-background-color=00000000 --force-device-scale-factor=2 `
  --window-size=1360,708 --screenshot="$PWD\showcase-en.png" "$url?mode=all&lang=en"

# 单屏图：把 mode 换成 home / wifi / ble / chat，窗口 360x708
& $chrome --headless=new --disable-gpu --no-first-run --hide-scrollbars `
  --default-background-color=00000000 --force-device-scale-factor=2 `
  --window-size=360,708 --screenshot="$PWD\screen-home.png" "$url?mode=home&lang=zh"
```

> `--screenshot` 必须使用绝对路径，相对路径在 Windows 上会写入失败（拒绝访问）。
