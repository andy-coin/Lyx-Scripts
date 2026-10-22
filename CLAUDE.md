# Lyx Scripts — 專案說明

## GUI 腳本清單（改共用函式庫時要逐一檢查）

改 `_lib/_Lyx_GUI.lua` 或 `_lib/_Lyx_Theme.lua`，或新增共用功能、想套用到所有 GUI 時，照這張表一個一個看過，避免有的腳本已經跟上、有的還是舊寫法。
新增或移除 GUI 腳本時，記得同步更新這張表。

### A. ImGui，交給 `G.new` + `G.run` 管理主迴圈
共用函式庫的改動（主題、字型、Esc、錯誤追蹤、置頂釘選）會自動套用到這組。

| 腳本 | 主題設定鍵 | 釘選 | 備註 |
|---|---|---|---|
| `Lyx_Global theme manager.lua` | Lyx Global Theme | 有 | 另外用 `_Lyx_Theme`（T.load / T.save / T.set_ui） |
| `Lyx_Tap tempo.lua` | TapTempo | 有 | `esc = false`，自己處理 Esc；每幀搶鍵盤（tap 用） |
| `Lyx_FFMPEG replace audio in video(McS).lua` | FFMPEG | 有（右下，待決定是否移到右上） | |
| `Lyx_Insert free fall midi notes .lua` | FreeFall | 有 | |
| `Lyx_Randomize....lua` | Randomize | 有 | |

### B. ImGui，自己寫主迴圈（只借用部分 `G.*`）
共用函式庫的改動**不會**自動套用，要手動補。

| 腳本 | 主題 | Esc | 釘選 | 備註 |
|---|---|---|---|---|
| `Lyx_Select items with same name or source.lua` | `G.load_theme()` 不帶設定鍵，一律繼承 | `G.esc()` | 無 | 沒有主題設定列 |
| `MIDI Editor/Lyx_MIDI note compressor and expander.lua` | `G.load_theme(THEME_KEY)` + 主題設定列 | `G.esc()` | 無 | 也直接用 `_Lyx_Theme` |
| `MIDI Editor/Lyx_MIDI_note_quantize_filter.lua` | `G.load_theme(THEME_KEY)` + 主題設定列 | `G.esc()` | 有 | 暫時的 `[IND]` 輸出待驗證後移除 |
| `Theme Layout Modifier/Lyx_Theme Layout Modifier.lua` | `G.load_theme(THEME_KEY)` + 主題設定列 | `G.esc()` + 自己的 Esc（經過未存檔提示） | 有 | 用 `require "imgui" "0.10"` 與 `tlm_walter` |

### C. 非 ImGui（別人的框架，Lyx 修改版）
只讀 `_Lyx_Theme` 的顏色，Esc 用內嵌的 `lyx_esc()`（同一套 ExtState 規則）。

| 腳本 | 框架 | 主題 | Esc |
|---|---|---|---|
| `Buss Driver/MB_Buss Driver(LYX mod) - ….lua` | rtk | T.get / T.mix / T.inherit / T.changed / T.open_manager | `lyx_esc()` → `self:close()` |
| `neutronic_Quick Adder (Lyx mod)/neutronic_Quick Adder 2.lua` | gfx | 同上 | `lyx_esc()` → `gfx.quit` |
| `Realauncher 2.5.2 (Lyx mod).lua` | gfx | **未接**主題 | **未接** Esc |

### 相關但不是 GUI
- `Lyx_ESC.lua`：全域 Esc。會關 FX 視窗、Kill_list 裡的視窗，並透過 ExtState `Lyx_GUI`（`alive` / `close`）請上面所有腳本自己關閉；焦點在 ImGui 視窗上時不介入。改 Esc 規則時，A、B、C 三組都要對照。
- `Realive/`：獨立專案（GSD），連結到外部資料夾，不在這張表裡。
- `Theme Layout Modifier/test/gui_test.lua`：測試用，不發佈。

### 共用函式庫
- `_lib/_Lyx_GUI.lua`：ImGui 外框（`G.new`、`G.run`、`G.esc`、`G.pin`、`G.theme_row`、`G.load_theme`、字型與顏色）。
- `_lib/_Lyx_Theme.lua`：主題資料（預設主題、儲存、共用版面設定 `ui`、繼承開關）。
- `_lib/_Lyx_HOME.lua`：使用者的 Lua 函式庫，**不可擅自修改**。
