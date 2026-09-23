-- ==================== 低耗能可調整參數 (Low-Power Configuration) ====================
-- 省電的主要槓桿是「沒人在用就完全停」(IDLE_PAUSE_SECONDS)，不是降低幀率：
-- 有人在看時給滿 ≈6FPS，一離開就停到 0.2 次喚醒/秒。所以兩種電源的間隔幾乎
-- 相同，電池只略降。想恢復明顯的「電池降幀」把 MOVE_INTERVAL_BATTERY 調大即可。
return {
    MOVE_INTERVAL_AC      = 0.16,  -- 接電時的更新間隔（秒；0.16s≈6FPS）
    MOVE_INTERVAL_BATTERY = 0.17,  -- 電池供電時的更新間隔（秒）
    IDLE_PAUSE_SECONDS    = 25,    -- 無操作超過這麼久就停止捲動（沒人在看）
    IDLE_POLL_INTERVAL    = 5,     -- idle 暫停期間的偵測間隔（秒）
    MOUSE_POLL_INTERVAL   = 0.3,   -- 游標壓在跑馬燈上、變暗暫停期間的偵測間隔（秒）
    MOUSE_CHECK_EVERY     = 2,     -- 正常執行時每 N 個 tick 才檢查一次游標
    WATCHDOG_INTERVAL     = 30,    -- sleep 暫停期間的保險偵測間隔（秒）

    TEXT_ALPHA   = 0.50,  -- 字身透明度
    LEAD_ALPHA   = 0.75,  -- 領頭字（最高位數字）透明度
    DIMMED_ALPHA = 0.15,  -- 游標碰到跑馬燈時整體變暗的透明度
    FONT_SIZE    = 22,    -- 數字字型大小
    GLYPH_STEP   = 24,    -- 上下相鄰字元的間距（點）

    -- 文字外框：這張圖捲過去的是桌布，亮色桌布上半透明的白字會整個消失。
    -- 單位是「字級的百分比」，不是點數；填正值，符號由 canvas.lua 處理。
    --
    -- 描邊以字形輪廓為中心往兩邊各長一半，canvas.lua 的上層字身會蓋掉往內那半，
    -- 所以「看得到的黑邊」只有這個值的一半 -- 8% 在 22pt 下是 1.76pt 總寬、
    -- 0.88pt 露在字外面。加粗只會往外長，不會侵蝕字身。改 FONT_SIZE 就要回來
    -- 重看這個值。
    --
    -- 欄位會自動往右多讓出這麼多空間給黑邊（geometry.STROKE_PAD），所以調大它
    -- 只會從 COLUMN_MARGIN 吃掉一點點，不會讓黑邊被切成一條直邊。
    TEXT_STROKE_WIDTH = 8,
    TEXT_STROKE_COLOR = { white = 0 },   -- 不透明；半透明是 canvas 層級的事

    -- 「字與右邊框的距離」就只看這一個值：字是靠右對齊到欄位右緣的，而欄位右緣
    -- 就貼在「螢幕可用區右緣往左 COLUMN_MARGIN 點」的位置。調大 = 離邊框更遠。
    -- 上限參考：keycap 的按鍵框右緣在距離右緣 40 點處，COLUMN_MARGIN 超過
    -- 約 27 就會讓數字疊到那個框上。
    COLUMN_MARGIN = 18,   -- 數字右緣距離螢幕可用區右緣的距離（點）
    SCROLL_SPEED  = 46,   -- 捲動速度（點/秒），由下往上
    LOOP_GAP      = 120,  -- 整串跑完到下一輪自螢幕下方再進場之間的空白（點）
    BOTTOM_INSET  = 24,   -- 底部留白，避開 modules/statusbar 的 20pt 狀態列

    -- 倒數的目標時刻。
    TARGET = { year = 2068, month = 9, day = 29, hour = 0, min = 0, sec = 0 },
}
