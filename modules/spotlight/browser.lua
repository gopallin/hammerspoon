-- 把網址交給 Safari 打開，以及「使用者輸入的那串字」要變成什麼網址。
local M = {}

local function applescriptEscape(s)
    return (s:gsub("\\", "\\\\"):gsub('"', '\\"'))
end

-- AppleScript 的字串常值不能跨行，所以網址裡一個原始換行就會把它結束掉，後面的
-- 東西全都落進腳本本體。只跳脫引號和反斜線 -- 舊版做的全部 -- 對那件事完全沒有幫助。
-- 任何不是單純 http(s) 網址的東西一律拒絕。
function M.isSafeUrl(url)
    if type(url) ~= "string" or #url == 0 or #url > 2048 then return false end
    if not url:match("^https?://") then return false end
    if url:find("%c") then return false end
    return true
end

-- 把使用者輸入的自由文字變成網址。判斷它是什麼意思是在「這裡」做，不是在頁面裡：
-- 頁面可以要求搜尋一個字串或造訪一個裸主機名，而兩條路都產生不出非 http(s) 的網址。
-- 不合法時回傳 nil。
function M.urlForQuery(q)
    if type(q) ~= "string" or #q == 0 or #q > 512 or q:find("%c") then return nil end
    if q:match("^https?://") then return q end
    if q:find("%.") and not q:find("%s") then return "https://" .. q end
    return "https://www.google.com/search?q=" .. hs.http.encodeForQuery(q)
end

local SCRIPT = [[
    set targetURL to "%s"
    tell application "Safari"
      activate
      if (count of windows) is 0 then
        make new document with properties {URL:targetURL}
        return
      end if
      set curTab to current tab of front window
      set curURL to ""
      try
        set curURL to (URL of curTab) as text
      end try
      if curURL is "" or curURL is "about:blank" or curURL starts with "favorites://" or curURL starts with "topsites://" then
        set URL of curTab to targetURL
      else
        tell front window
          set current tab to (make new tab with properties {URL:targetURL})
        end tell
      end if
    end tell
]]

function M.open(url)
    if not M.isSafeUrl(url) then
        print("[spotlight] refusing to open unsafe url: " .. tostring(url))
        return
    end
    hs.osascript.applescript(string.format(SCRIPT, applescriptEscape(url)))
end

return M
