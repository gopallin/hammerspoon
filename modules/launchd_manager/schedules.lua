-- ~/hammerspoon/modules/launchd_manager/schedules.lua
-- 定義所有的 launchd 排程
-- 之後你可以把需要執行的 shell scripts 或捷徑檔，統一放在 ./scripts 資料夾中集中管理

return {
    {
        label = "com.user.charge-mac-to-100",
        -- 呼叫捷徑，捷徑檔案(.shortcut)也可以備份在 scripts 資料夾中
        programArguments = {"/usr/bin/shortcuts", "run", "Charge Mac To 100"},
        calendar = { Hour = 16, Minute = 30, Weekday = 5 },
        stdOut = "/tmp/charge-mac-to-100.out",
        stdErr = "/tmp/charge-mac-to-100.err"
    },
    {
        label = "com.user.insight-reporter",
        programArguments = {"/bin/bash", os.getenv("HOME") .. "/.hammerspoon/modules/launchd_manager/scripts/run_insights.sh"},
        calendar = { Hour = 10, Minute = 17, Weekday = 1 },
        stdOut = "/tmp/insightreporter.out",
        stdErr = "/tmp/insightreporter.err"
    }
}
