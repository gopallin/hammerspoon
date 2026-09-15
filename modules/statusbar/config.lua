return {
    BAR_HEIGHT       = 20,
    FONT_SIZE        = 14,
    BACKGROUND_ALPHA = 0.55,
    REFRESH_INTERVAL = 5,

    -- 每個指標區段之間插入的間隔，想寬想窄改這裡。
    SEPARATOR = "                 ",

    -- 每 N 次刷新才更新一次磁碟用量（12 x 5s = 一分鐘一次）。
    --
    -- df 只出現在「慢」的那支腳本裡。磁碟用量不會用網路速率的速度變動，而每 5 秒
    -- 跑一次代表每次刷新要開三個行程（df、route、netstat）而不是兩個 -- 一天
    -- 17,280 次 df，只為了看一個最多一小時才動一個百分點的數字。
    DISK_EVERY = 12,
}
