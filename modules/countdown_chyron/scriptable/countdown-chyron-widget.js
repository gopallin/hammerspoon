// countdown-chyron-widget.js — Scriptable (iOS) 小工具
//
// 這支檔案不是 Hammerspoon 模組，不會被 init.lua require，也不在 modules/reload
// 的監看副檔名裡（它只看 .lua/.html/.json）。它放在這裡是因為它是 countdown_chyron
// 的 iOS 對應版：TARGET 必須和 ../config.lua 的 TARGET 一致，格式對應 Mac 版的
// %d:%02d:%02d:%02d。改其中一邊就要回來改另一邊 —— 兩份常數沒有任何機制會同步。
//
// 部署：內容貼進 iOS 的 Scriptable App 建一支同名腳本，再加主畫面小工具。
// 手機上的那份是副本，不是這個檔案；這裡只是版本控管的單一來源。
//
// ── 為什麼 ticker 倒數到「days 減一的那一刻」，而不是午夜或整點 ─────────────
// applyTimerStyle() 畫的是 SwiftUI 的系統文字，格式由系統決定、沒有參數可給。
// 它只有三種樣子，而且只砍「最高那一級」的開頭零：
//
//     餘量 ≥ 1 小時      →  H:MM:SS    （MM、SS 補零，H 不補）
//     10 分鐘 ~ 1 小時   →  MM:SS      （SS 補零，MM 不補）
//     < 10 分鐘          →  M:SS
//
// 關鍵在最後那句：被砍的永遠只有最高一級。所以只要讓最高級是我們「不在乎有沒有
// 補零」的那一級，它以下的每一級就自動都是兩位數 —— 不需要任何刷新來補。
//
// 第一版把 ticker 倒數到「下一個整點」，餘量恆 < 1 小時、格式鎖在 MM:SS，
// DD:HH: 用靜態文字接在前面。那讓最高級變成「分鐘」，於是剩不到 10 分鐘就掉成
// M:SS（15340:14:9:52）。補那個 0 要在整點前 10 分鐘多排一次刷新 —— 一天 48 次。
// 2026-09-29 09:00 實測失效：畫面停在 15340:15:0:21，HH 該是 14 卻是 15，代表
// T-10min 與整點兩次刷新都被 WidgetKit 丟掉，ticker 走過目標往上數了 21 秒。
// 沒有任何視覺線索，看起來就像正常在跑。
//
// 這一版把目標往外推一級，推到「days 這個數字減一的那一刻」（= TARGET 往回數
// 整數個 24 小時）。餘量落在 [0, 24h)，格式變成 H:MM:SS，最高級是小時 ——
// MM:SS 從此永遠兩位數，一毛刷新都不用花。靜態文字也只剩下 days。
//
// 帳當然要有人付：改成小時去背。H 不補零，而且餘量掉到 1 小時以下時整個 H 欄
// 會消失（格式退成 MM:SS）。這些用靜態前綴補（見 PAD_FIELDS），而前綴只在四個
// 門檻上改變：R = 10h、1h、10min、0。一天 4 次刷新，不是 48 次。

// ==================== 可調整參數 (Appearance) ====================
const TARGET = new Date(2068, 8, 29, 0, 0, 0);   // JS 月份 0-based：8 = 九月

const SHOW_SUBTITLE = false;      // 底下那行「→ 2068-09-29」

// 顏色與透明度。alpha 是 new Color() 的第二個參數：0 = 全透明、1 = 不透明。
// 兩段設成一樣就是單色；HEAD/TICK 分開是為了保留原版 LEAD_COLOR 的層次。
const HEAD_COLOR = "#ffffff";  const HEAD_ALPHA = 0.75;  // days 那一段
const TICK_COLOR = "#ffffff";  const TICK_ALPHA = 0.75;  // 跳動的 HH:MM:SS
const BG_COLOR   = "#000000";  const BG_ALPHA   = 0.70;  // 小工具底色

// 字體。改 FONT_FACE 換字型家族，可填下面 FACES 裡的任一個 key。
// 想用具體字型就填 CUSTOM_FONT（優先於 FONT_FACE），iOS 內建可用的例子：
//   "Menlo-Bold"、"Courier-Bold"、"CourierNewPS-BoldMT"、
//   "AmericanTypewriter-Bold"、"Futura-Bold"、"HelveticaNeue-Bold"
const FONT_FACE   = "boldMonospacedSystemFont";
const CUSTOM_FONT = null;

// 排版：
//   "one-line"  →  15340:14:09:52     （一整串，字較小）
//   "two-lines" →  15340              （拆兩行，字可以大約 1.5 倍）
//                  14:09:52
const LAYOUT = "one-line";

// 字級：填 null 就用「塞得下的最大字級」。填數字是「希望的字級」，但仍然會被
// 塞得下的上限夾住 —— 這是刻意的：以前它是硬性覆蓋，填太大時整串會被截成
// 15340:…09:52，中間的欄位就這樣消失。想要更大的字請改 LAYOUT，不是改這裡。
const MANUAL_SIZE = null;
const MAX_SIZE    = 60;   // 上限，避免大版位的字高過版位
const PAD         = 7;    // 版位內縮（點）。調小可以換到更大的字。

// WidgetKit 自己會在內容外圍留一圈邊界（每側約 16pt），這在 setPadding() 之外、
// 腳本關不掉。漏算它就是被截字的第二個原因：可用寬度少 32pt，算出的字級偏大
// 約 8%。若你的機型仍然截字，把這個值往上加。
const SYSTEM_MARGIN = 16;

// 打開會在底下多一行 w=螢幕寬 size=算出的字級 n=字元數 pad=當下前綴，
// 用來對照實際狀況。調 TICK_RESERVE 時把它打開。
const SHOW_DEBUG = false;

// ticker 當下只顯示 8 個字元（HH:MM:SS），前綴最長 4 個（"00:0"），但兩者是
// 互補的 —— 前綴越長代表 ticker 的最高級越少，合起來永遠剛好 8 個可見字元：
//     ""     + "23:59:59"
//     "0"    + "9:59:59"
//     "00:"  + "59:59"
//     "00:0" + "9:59"
// 但 applyTimerStyle() 的內容每秒在變，SwiftUI 會替它預留「最寬可能內容」的
// 空間而不是當下的寬度，而且那個預留量沒有 API 可問。一行排版時兩段在水平
// stack 裡競爭寬度，ticker 先拿走它預留的份，HEAD 拿到剩下的 —— 不夠就被截成
// 15340:…。所以這裡按 10 個字元估（8 個可見 + 2 格餘裕），不是 8。
//
// ⚠️ 未在實機驗證：第一版的 ticker 餘量恆 < 1 小時，這一版變成 < 24 小時，
// SwiftUI 的預留量可能跟著變大。若看到 15340:…09:52 這種中間被吃掉的樣子，
// 把這個值往上加（每加 1 大約讓字級小 2pt）；兩行排版不受此影響。
const TICK_RESERVE = 10;

// 靜態前綴，補上系統砍掉的最高級開頭零。依餘量 R 有四種狀態：
//
//     R ≥ 10h          ""      ticker 已經是 14:09:52
//     1h  ≤ R < 10h    "0"     ticker 是 9:09:52   →  09:09:52
//     10m ≤ R < 1h     "00:"   ticker 是 59:52     →  00:59:52
//     R < 10m          "00:0"  ticker 是 9:52      →  00:09:52
//
// 前綴是靜態文字，只在這四個門檻上變，所以一天只要 4 次刷新（見檔尾）。
// 第一版是每個整點前 10 分鐘補一次 0、一天 48 次超出預算，差別就在這裡：
// 同樣是靜態補零，貼在哪一級決定了它要花幾次刷新。
//
// 設 false 就完全不補，回到一天 1 次刷新，接受 H 少一位數、且最後一小時沒有 H
// 欄（會變成 15340:59:52，看起來像分鐘卻是小時的位置 —— 不建議）。
const PAD_FIELDS = true;

// 內距與字寬的關係：等寬字每個字元的前進寬度約為字級的 0.62 倍（SF Mono
// 的數字與冒號同寬）。用 0.62 而非量到的 0.596 是留邊，免得剛好卡在溢出。
const ADVANCE_RATIO = 0.62;

// 一行文字實際佔的高度相對於字級的倍率（含行距）。
const LINE_HEIGHT_RATIO = 1.3;
// ================================================================

const HEAD_C = new Color(HEAD_COLOR, HEAD_ALPHA);
const TICK_C = new Color(TICK_COLOR, TICK_ALPHA);

// 用明確的 map 而不是 Font[FONT_FACE] 動態取值：打錯字時錯誤訊息看得懂，
// 而且不依賴 Scriptable 原生橋接把 static method 暴露成可枚舉屬性。
const FACES = {
  boldMonospacedSystemFont:    (s) => Font.boldMonospacedSystemFont(s),
  heavyMonospacedSystemFont:   (s) => Font.heavyMonospacedSystemFont(s),
  regularMonospacedSystemFont: (s) => Font.regularMonospacedSystemFont(s),
  boldRoundedSystemFont:       (s) => Font.boldRoundedSystemFont(s),   // 原版 Mac chyron 的味道
  heavyRoundedSystemFont:      (s) => Font.heavyRoundedSystemFont(s),
  boldSystemFont:              (s) => Font.boldSystemFont(s),
  mediumSystemFont:            (s) => Font.mediumSystemFont(s),
};

function font(size) {
  if (CUSTOM_FONT) return new Font(CUSTOM_FONT, size);
  const maker = FACES[FONT_FACE];
  if (!maker) throw new Error(`FONT_FACE 不認得：${FONT_FACE}`);
  return maker(size);
}

const HOUR = 3600000;
const DAY  = 24 * HOUR;

// ticker 的目標：TARGET 往回數整數個 24 小時，落在「現在」之後最近的那一個。
// 也就是 days 這個數字減一的那一刻。
//
// 用固定的 86400000ms 而不是曆法上的「日」，是因為 ticker 走的是真實時間：
// 這樣「餘量」與「螢幕上的 days」永遠是同一套單位，不會在日光節約時間那天
// 對不起來。台灣沒有 DST，但這個選擇讓它在有 DST 的時區也自洽 —— 代價是
// 換時區後界線不會剛好落在當地午夜。
const days = Math.floor((TARGET.getTime() - Date.now()) / DAY);
const dayBoundary = new Date(TARGET.getTime() - days * DAY);
const remaining = dayBoundary.getTime() - Date.now();   // R，落在 (0, 24h]

// 靜態的 days。一行排版時尾端要留冒號好接上 ticker；兩行排版時不留。
const HEAD = LAYOUT === "two-lines" ? `${days}` : `${days}:`;

// 見 PAD_FIELDS 的對照表。門檻由大到小排，第一個成立的就是答案。
const PAD_STEPS = [
  { at: 10 * HOUR, prefix: ""     },
  { at: 1  * HOUR, prefix: "0"    },
  { at: 10 * 60000, prefix: "00:"  },
  { at: 0,          prefix: "00:0" },
];
const step = PAD_STEPS.find((s) => remaining >= s.at);
const ZERO = PAD_FIELDS ? step.prefix : "";

const family = config.widgetFamily || "accessoryRectangular";
const w = new ListWidget();

// ── 字級 ────────────────────────────────────────────────────────────────────
// 為什麼不靠 minimumScaleFactor 自動縮：
// SwiftUI 的 autoshrink 是「每個 Text 各自」決定縮放比例的，沒有跨 view 同步
// 的機制。HEAD 是 6 個字元、ticker 是 8 個，同一個字級下後者超出版位更多，
// 就被縮得更狠 —— 結果一大一小。所以這裡反過來做：先算出整串塞得下的最大
// 字級，把同一個值套給每一段，並禁止各自縮放（minimumScaleFactor = 1）。

// 小工具的實際寬度沒有 API 可問，只能從螢幕寬度推。iPhone 主畫面上中／大
// 版位橫跨整個格線寬度，約為螢幕寬的 0.84；小版位約 0.40。這是近似值，
// 所以 ADVANCE_RATIO 那邊留了邊。
function boxWidth() {
  const sw = Device.screenSize().width;
  if (family === "systemSmall") return sw * 0.40;
  return sw * 0.86;   // systemMedium / systemLarge / accessory / StandBy
}

// 內容真正能用的寬高：版位尺寸扣掉系統邊界與自訂內縮。accessory 版位沒有
// 那圈系統邊界，所以只扣 PAD。
function inset() {
  return family.startsWith("accessory") ? PAD : SYSTEM_MARGIN + PAD;
}

// 小、中版位等高（都是一格高）；大版位約兩格半。
function boxHeight() {
  const sw = Device.screenSize().width;
  if (family === "systemLarge") return sw * 0.90;
  if (family.startsWith("accessory")) return 72;
  return sw * 0.40;
}

// 一行時 HEAD 與 ticker 共用一條寬度；兩行時各自獨佔，取兩者較長的那個即可。
//
// TICK_RESERVE 已經含了前綴那幾格（見它的註解：前綴與 ticker 互補，合起來恆為
// 8 個可見字元），所以這裡不再另外加 —— 否則會重複計算，字級平白縮一號。
const LONGEST = LAYOUT === "two-lines"
  ? Math.max(HEAD.length, TICK_RESERVE)
  : HEAD.length + TICK_RESERVE;

// 寬度和高度都要塞得下，取兩者的較小值。兩行排版只看寬度的話會算出 63pt，
// 疊起來直接超出版位高度。
function autoSize() {
  const lines = LAYOUT === "two-lines" ? 2 : 1;
  const byWidth  = (boxWidth()  - inset() * 2) / (LONGEST * ADVANCE_RATIO);
  const byHeight = (boxHeight() - inset() * 2) / (lines * LINE_HEIGHT_RATIO);
  const fits = Math.min(byWidth, byHeight);

  // MANUAL_SIZE 也要過這道夾擠。真的要強制溢出（例如想讓字衝出版位當設計），
  // 把下面改成 `const wanted = MANUAL_SIZE || MAX_SIZE; return wanted;`。
  const wanted = MANUAL_SIZE || MAX_SIZE;
  return Math.max(8, Math.floor(Math.min(wanted, fits)));
}

// 每一段共用同一個字級，且都禁止自動縮放 —— 放不下就讓它明顯溢出／截斷，
// 而不是無聲地縮成兩種大小。
function styled(el, size, color) {
  el.font = font(size);
  el.textColor = color;
  el.lineLimit = 1;
  el.minimumScaleFactor = 1;
  return el;
}

function chyron(container, size) {
  const box = container.addStack();
  box.spacing = 0;                   // 前綴要貼著 ticker，不能有間隙
  if (LAYOUT === "two-lines") box.layoutVertically();
  else box.centerAlignContent();

  styled(box.addText(HEAD), size, HEAD_C);

  // 前綴與 ticker 必須貼在一起，所以兩行排版時它們自成一個水平子 stack。
  const tickRow = LAYOUT === "two-lines" ? box.addStack() : box;
  if (LAYOUT === "two-lines") {
    tickRow.spacing = 0;
    tickRow.centerAlignContent();
  }

  if (ZERO) styled(tickRow.addText(ZERO), size, TICK_C);

  const tick = tickRow.addDate(dayBoundary);
  tick.applyTimerStyle();            // ← 每秒跳的來源，由系統渲染
  styled(tick, size, TICK_C);

  return box;
}

function subtitle(container, size) {
  if (!SHOW_SUBTITLE) return;
  const s = container.addText("→ 2068-09-29");
  s.font = Font.systemFont(size);
  s.textColor = TICK_C;
}

// 診斷用：把模型的輸入與輸出印出來，免得靠猜。同時也是「這份程式真的重跑了」
// 的證據 —— 小工具不會因為你編輯腳本就重新渲染。
function debugLine(container) {
  if (!SHOW_DEBUG) return;
  const sw = Math.round(Device.screenSize().width);
  const hrs = (remaining / HOUR).toFixed(2);
  const d = container.addText(
    `w=${sw} size=${autoSize()} n=${LONGEST} R=${hrs}h pad="${ZERO}"`);
  d.font = Font.systemFont(9);
  d.textColor = TICK_C;
}

if (family === "accessoryInline") {
  // inline 只吃單一元素、不能放 stack，也吃不到字體與顏色設定（系統統一渲染）。
  const tick = w.addDate(dayBoundary);
  tick.applyTimerStyle();

} else if (family === "accessoryCircular") {
  // 圓形版位塞不進 DD:HH:MM:SS，退成純跳秒。
  const tick = w.addDate(dayBoundary);
  tick.applyTimerStyle();
  tick.font = font(13);
  tick.centerAlignText();

} else if (family === "accessoryRectangular") {
  // 鎖定畫面：系統會把小工具染成單一色調，所以這裡的顏色設定多半無效。
  // 該版位只有約 72pt 高，字級另外壓上限。
  w.setPadding(0, 2, 0, 2);
  chyron(w, Math.min(autoSize(), LAYOUT === "two-lines" ? 24 : 20));
  subtitle(w, 11);

} else {
  // 主畫面／StandBy。
  w.backgroundColor = new Color(BG_COLOR, BG_ALPHA);
  w.setPadding(PAD, PAD, PAD, PAD);
  w.addSpacer();
  chyron(w, autoSize());
  subtitle(w, 10);
  debugLine(w);
  w.addSpacer();
}

// ── 刷新 ────────────────────────────────────────────────────────────────────
// 需要重畫的只有兩樣靜態文字：days，以及那個前綴。合起來一天最多 4 個門檻
// （R = 10h、1h、10min、0）。WidgetKit 的每日預算 Apple 沒有公布，一般觀察在
// 數十次這個量級 —— 4 次離上緣很遠。這是這一版最實際的好處：第一版要 48 次，
// 而 2026-09-29 那次證明了 48 次拿不到。
//
// 遲到的後果分兩級，差很多：
//   前三個門檻（前綴）遲到只是少幾位數，螢幕上的數字仍然是對的。
//   最後一個（R = 0，days 減一）遲到就嚴重：.timer 走過目標不會停，它會反過來
//   往上數，而 days 還沒減一 —— 看起來完全正常，其實是錯的。
// 判斷方法：拿 days 與 H 去對現在幾點，對不上就是那一次遲到了。
//
// 排在門檻過後 1 秒（最後一個過後 5 秒，多留一點給跨界線的重算）。
const nextThreshold = PAD_FIELDS
  ? PAD_STEPS.filter((s) => s.at < remaining).map((s) => s.at)[0]
  : 0;
w.refreshAfterDate = nextThreshold > 0
  ? new Date(dayBoundary.getTime() - nextThreshold + 1000)
  : new Date(dayBoundary.getTime() + 5000);

if (config.runsInWidget) Script.setWidget(w);
else w.presentMedium();
Script.complete();
