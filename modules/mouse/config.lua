return {
    -- 合成點擊按住的時間。刻意遠低於舊版的 100ms：沒有任何東西需要那麼久，
    -- 而且現在是排程延遲而非阻塞式 sleep（見 click.lua）。
    CLICK_HOLD_SECONDS = 0.03,

    -- 連續移動：每 MOVE_INTERVAL 秒移動 MOVE_SPEED 點。
    MOVE_SPEED    = 3,
    MOVE_INTERVAL = 0.01,

    -- 沒有人會按住方向鍵十秒，所以超過這個時間還在跑的 timer，代表它的
    -- stopMove() 從來沒送到 -- 通常是按鍵還按著時焦點就換掉，macOS 沒送出
    -- 放開事件。沒有這個上限，timer 會以 100Hz 一路跑到 session 結束，把游標
    -- 拖過整個螢幕，而且除了 reload 之外沒有辦法停下來。
    MAX_MOVE_SECONDS = 10,
}
