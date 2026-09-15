-- 指標的收集與格式化。
--
-- ── 指標為什麼是這樣取得的 ───────────────────────────────────────────────────
-- 這個模組以前是 shell out 跑 `top -l 1` 來拿 CPU 數字。實測，光那一個指令就要
-- 196ms 的 CPU，在 5 秒刷新下等於 24 小時不間斷燒掉 4.2% 的一顆核心 -- 比這份
-- 設定裡任何其他東西高一個數量級。更糟的是它還是「錯的」：`top -l 1` 回報的單次
-- 取樣視窗包含 top 自己的啟動時間，所以「量測的成本」被算成了負載。連續三次讀到
-- 16.2% / 20.2% / 21.6%，而 `top -l 2`（取第二次取樣）和 ps 差分都說 ~8%。
-- 這條 bar 顯示的大約是真實數字的兩倍。
--
-- CPU 和記憶體現在來自 hs.host，在行程內取得，不 fork 也不阻塞。剩下的 shell
-- 呼叫只剩 hs 沒有 API 的部分：介面位元組計數器（hs.network 提供的是組態，不是
-- 流量）和 df。實測 208.8ms -> 9.1ms 每次刷新，也就是一顆核心的 4.18% -> 0.18%。
local config = require("modules.statusbar.config")

local M = {}

-- 只取 hs.host 沒有 API 的那些。輸出格式："disk|rxBytes txBytes"。
-- 快版把 disk 欄位留空，summarize() 這時會沿用上一次的讀數。
local SCRIPT_FAST = [[
iface=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
net=$(netstat -ibn -I "$iface" | awk 'NR==2 {print $7" "$10}')
printf '%s|%s\n' "" "$net"
]]

local SCRIPT_FULL = [[
disk=$(df -k /System/Volumes/Data | awk 'NR==2 {gsub("%","",$5); print $5}')
iface=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
net=$(netstat -ibn -I "$iface" | awk 'NR==2 {print $7" "$10}')
printf '%s|%s\n' "$disk" "$net"
]]

-- 累計型計數器的上一次取樣；用來做差分算出「這段區間」的值。
local prevRx, prevTx, prevTime = nil, nil, nil
local prevCpuActive, prevCpuIdle = nil, nil
local lastDisk = nil
local refreshCount = 0

local function log(fmt, ...)
    print(string.format("[statusbar] " .. fmt, ...))
end

-- 這次刷新該跑哪一支腳本。
function M.nextScript()
    refreshCount = refreshCount + 1
    return (refreshCount % config.DISK_EVERY == 1) and SCRIPT_FULL or SCRIPT_FAST
end

-- 系統整體 CPU 負載百分比，跟上一次刷新做差分，所以描述的是整段區間而不是某個
-- 瞬間。第一次呼叫時沒有基準可差分，回傳 nil。
local function cpuPercent()
    local ok, ticks = pcall(hs.host.cpuUsageTicks)
    if not ok or type(ticks) ~= "table" or type(ticks.overall) ~= "table" then
        return nil
    end
    local active, idle = ticks.overall.active, ticks.overall.idle
    if type(active) ~= "number" or type(idle) ~= "number" then return nil end

    local pct = nil
    if prevCpuActive then
        local dActive = active - prevCpuActive
        local dIdle = idle - prevCpuIdle
        local total = dActive + dIdle
        -- 兩個差值都必須非負，不能只檢查 dActive：計數器重置時，負的 dIdle 配上
        -- 正的 dActive 仍然會讓 total > 0，然後算出超過 100 的假百分比。
        if total > 0 and dActive >= 0 and dIdle >= 0 then
            pct = dActive / total * 100
        end
    end
    prevCpuActive, prevCpuIdle = active, idle
    return pct
end

-- 記憶體佔用佔實體 RAM 的百分比。對應舊版 `vm_stat` + sysctl 算的東西：
-- active + wired + 壓縮器持有的分頁。
-- 注意：壓縮器那一項是 pagesUsedByVMCompressor（目前持有壓縮資料的分頁數），
-- 不是 pagesCompressed -- 後者是開機以來的累計值，會算出遠超過 100% 的數字。
local function memPercent()
    local ok, vm = pcall(hs.host.vmStat)
    if not ok or type(vm) ~= "table" then return nil end
    local pageSize, memSize = vm.pageSize, vm.memSize
    local active, wired = vm.pagesActive, vm.pagesWiredDown
    local compressor = vm.pagesUsedByVMCompressor
    if type(pageSize) ~= "number" or type(memSize) ~= "number" or memSize <= 0
        or type(active) ~= "number" or type(wired) ~= "number"
        or type(compressor) ~= "number" then
        log("vmStat missing an expected key; memory will read as --")
        return nil
    end
    return (active + wired + compressor) * pageSize * 100 / memSize
end

local function formatRate(bps)
    if bps >= 1024 * 1024 then return string.format("%.1fM/s", bps / 1024 / 1024) end
    if bps >= 1024 then return string.format("%.0fK/s", bps / 1024) end
    return string.format("%.0fB/s", bps)
end

local function formatPercent(v, label)
    return v and string.format("%s %d%%", label, math.floor(v + 0.5)) or (label .. " --")
end

-- 解析腳本輸出，算出下載／上傳速率。
local function parseNetwork(stdOut)
    -- 用定位比對，不用 gmatch("[^|]+")：gmatch 會跳過空欄位，所以一個什麼都沒產出的
    -- df（"|1000 2000"）會把 net 計數器滑進 disk 欄位，同時弄壞兩個讀數而不只是磁碟那個。
    local diskField, netField = stdOut:match("^([^|]*)|([^\n]*)")

    -- 快刷新時是空的（而大部分刷新都是快的）：沿用上一次的讀數，而不是把一個
    -- 仍然為真的數字清空。
    local disk = tonumber(diskField) or lastDisk
    lastDisk = disk

    local rx, tx = (netField or ""):match("(%d+)%s+(%d+)")
    rx, tx = tonumber(rx), tonumber(tx)

    local now = hs.timer.secondsSinceEpoch()
    local downRate, upRate = 0, 0
    if rx and prevRx and prevTime then
        local dt = now - prevTime
        -- 防止計數器重置（換介面）產生負值。
        if dt > 0 and rx >= prevRx and tx >= prevTx then
            downRate = (rx - prevRx) / dt
            upRate = (tx - prevTx) / dt
        end
    end
    prevRx, prevTx, prevTime = rx, tx, now

    return disk, downRate, upRate
end

-- 把腳本輸出變成要顯示在 bar 上的那一整行字。
function M.summarize(stdOut)
    -- CPU 和記憶體來自 hs.host，不是來自 shell。兩者都可能回答 nil（還沒有基準，
    -- 或 vmStat 形狀不如預期），而 "--" 是對那件事誠實的顯示 -- 舊版退回 0，
    -- 但 0 是一個「真實的讀數」。
    local cpu = cpuPercent()
    local mem = memPercent()
    local disk, downRate, upRate = parseNetwork(stdOut)

    local battery = hs.battery.percentage()
    local batText = battery and string.format("%d%%", math.floor(battery + 0.5)) or "--"
    local batPrefix = hs.battery.isCharging() and "⚡ " or ""

    return table.concat({
        formatPercent(cpu, "CPU"),
        formatPercent(mem, "MEM"),
        string.format("↓ %s  ↑ %s", formatRate(downRate), formatRate(upRate)),
        formatPercent(disk, "SSD"),
        string.format("%sBAT %s", batPrefix, batText),
    }, config.SEPARATOR)
end

-- 丟掉快取的基準值。恢復時的第一次取樣否則會把「整段睡眠期間的平均速率」
-- 當成當下速率呈現出來。寧可有一次刷新顯示 "--"，也不要顯示一個謊。
function M.resetBaselines()
    prevRx, prevTx, prevTime = nil, nil, nil
    prevCpuActive, prevCpuIdle = nil, nil
end

function M.reset()
    M.resetBaselines()
    refreshCount, lastDisk = 0, nil
end

return M
