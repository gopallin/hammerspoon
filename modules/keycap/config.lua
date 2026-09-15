return {
    -- 外觀（畫在右下角）
    FONT_SIZE        = 25,
    BACKGROUND_ALPHA = 0.3,
    CANVAS_WIDTH     = 170,
    CANVAS_HEIGHT    = 38,

    -- 緩衝區
    CHAR_BUFFER_LENGTH     = 8,    -- 畫面上最多顯示幾個字
    CHAR_TTL_SECONDS       = 1.5,  -- 一個字停留多久後消失
    EXPIRE_CHECK_INTERVAL  = 0.2,  -- 過期檢查間隔（只在畫面上有東西時才跑）

    -- 只是保險上限。快取一偵測到任何可能移動焦點的動作就立刻失效
    -- （見 protection.lua 的 invalidate），所以這個值限制的是「那些訊號全都
    -- 沒抓到的焦點變化」能造成多久的誤判，而不是正常路徑。
    AX_PROBE_MAX_AGE = 0.5,

    -- 每一次 accessibility 查詢都是對「擁有焦點元件的那個行程」的同步 IPC，
    -- 而 OS 預設的逾時是以「秒」為單位。探測已經不在按鍵路徑上了，但它仍然跑在
    -- Hammerspoon 唯一的主執行緒上，所以不能讓一個不回應的 app 在它慢慢不回答
    -- 的期間把整份設定卡住。這個逾時設在 systemwide element 上，因為那才是
    -- 所有衍生元件的全域預設值（hs.axuielement:setTimeout）。
    AX_MESSAGING_TIMEOUT = 0.2,
}
