//+------------------------------------------------------------------+
//|                      VangExness_DCA_Hedge_EA_v2.24.mq5           |
//|                                  Copyright 2024, Mr JuNet        |
//|   🔥 v2.24: FIX 3 LỖI NGHIÊM TRỌNG - An Toàn Tối Đa            |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Mr JuNet"
#property link      ""
#property version   "2.24"
#property strict

#include <Trade\Trade.mqh>

//--- Khai báo đối tượng giao dịch
CTrade trade;

//+------------------------------------------------------------------+
//| ENUMS - Các kiểu dữ liệu tùy chỉnh                               |
//+------------------------------------------------------------------+

// Hệ tăng lot: Cộng hoặc Nhân
enum ENUM_LOT_PROGRESSION { 
   LOT_ADD,          // Hệ cộng (0.01, 0.02, 0.03...)
   LOT_MULTIPLY      // Hệ nhân (0.01, 0.011, 0.012...)
};

// Chế độ DCA
enum ENUM_DCA_MODE {
   MODE_NEGATIVE,    // DCA âm: Chỉ mở lệnh theo hướng thua lỗ
   MODE_POSITIVE,    // DCA dương: Mở lệnh theo hướng thắng (theo trend)
   MODE_PAIRS        // DCA cặp: Mở đồng thời Buy+Sell mỗi nến
};

// DCA Trigger Mode
enum ENUM_DCA_TRIGGER {
   TRIGGER_BAR_CLOSE,  // Theo nến đóng (chỉ mở khi nến đóng)
   TRIGGER_STEP,       // Theo step cố định (mở ngay khi đủ khoảng cách)
   TRIGGER_ATR         // Theo ATR động (khoảng cách thay đổi theo volatility)
};

// Cấp độ cảnh báo xu hướng
enum ENUM_TREND_LEVEL {
   TREND_NORMAL,     // 🟢 Bình thường
   TREND_WARNING,    // 🟡 Cảnh báo
   TREND_DANGER,     // 🔴 Nguy hiểm
   TREND_CRITICAL    // ⛔ Cực kỳ nguy hiểm
};

//+------------------------------------------------------------------+
//| INPUT PARAMETERS - Tham số đầu vào                               |
//+------------------------------------------------------------------+

//--- Cài đặt cơ bản
input group "===== CÀI ĐẶT CƠ BẢN ====="
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_M15;        // Khung thời gian giao dịch
input double InpInitialLot = 0.01;                      // Lot khởi đầu
input int InpMagicNumber = 888888;                      // Mã số EA (Magic Number)

//--- Cài đặt DCA
input group "===== CHẾ ĐỘ DCA ====="
input ENUM_DCA_MODE InpDCAMode = MODE_NEGATIVE;         // Chế độ: DCA âm hoặc DCA cặp
input ENUM_LOT_PROGRESSION InpLotProgression = LOT_ADD; // Hệ tăng lot: Cộng hoặc Nhân
input double InpAddValue = 1.0;                         // Giá trị cộng thêm (với hệ cộng)
input double InpMultiplyValue = 1.1;                    // Hệ số nhân (với hệ nhân)
input double InpDCADistance = 50;                       // Khoảng cách DCA (points)
input bool InpAllowRefill = false;                      // Cho phép nhồi lệnh khi giá hồi về
input int InpMaxPairs = 5;                              // Số cặp tối đa (chỉ cho DCA cặp)

//--- DCA Trigger
input group "===== DCA TRIGGER MODE ====="
input ENUM_DCA_TRIGGER InpDCATrigger = TRIGGER_BAR_CLOSE;  // Chế độ kích hoạt DCA
input int InpATRPeriod = 14;                            // ATR Period (cho TRIGGER_ATR)
input double InpATRMultiplier = 1.5;                    // ATR Multiplier (khoảng cách = ATR * multiplier)

//--- Quản lý rủi ro
input group "===== QUẢN LÝ RỦI RO ====="
input double InpMaxLot = 10.0;                          // Lot tối đa cho 1 lệnh
input int InpMaxOrders = 50;                            // Tổng số lệnh tối đa
input double InpTotalStopLoss = 5000;                   // Cắt lỗ tổng (USD) - 0 = tắt

//--- 🆕 v2.22: Cài đặt chốt lời PRO
input group "===== CHỐT LỜI PRO v2.22 ====="
input double InpTotalTP = 10.0;                         // TP tổng ban đầu (USD)
input bool InpEnableTrailing = true;                    // Bật Trailing TP Pro

// Breakeven Protection
input bool InpEnableBreakeven = true;                   // Bật Breakeven Protection
input double InpBreakevenMultiplier = 1.5;              // Breakeven khi profit = TP x multiplier

// Multi-Level Trailing
input bool InpEnableMultiLevel = true;                  // Bật Multi-Level Trailing
input double InpTrailingLevel1_Profit = 15.0;           // Level 1: Profit threshold (USD)
input double InpTrailingLevel1_Distance = 5.0;          // Level 1: Trailing distance (USD)
input double InpTrailingLevel2_Profit = 30.0;           // Level 2: Profit threshold (USD)
input double InpTrailingLevel2_Distance = 8.0;          // Level 2: Trailing distance (USD)
input double InpTrailingLevel3_Profit = 50.0;           // Level 3: Profit threshold (USD)
input double InpTrailingLevel3_Distance = 12.0;         // Level 3: Trailing distance (USD)

// Acceleration Trailing
input bool InpEnableAcceleration = true;                // Bật Acceleration Trailing
input double InpAccelMultiplier = 0.8;                  // Hệ số giảm distance (0.8 = giảm 20%)

// Emergency Protection
input double InpEmergencyFloor = 50.0;                  // Emergency floor (% of TP gốc)
input double InpMinimumProfit = 8.0;                    // Profit tối thiểu tuyệt đối (USD)

// Smart Recovery
input bool InpEnableSmartRecovery = true;               // Bật Smart Recovery
input int InpRecoveryBars = 3;                          // Số nến phục hồi để nới trailing

//--- Hedge Lock (độc lập hoàn toàn)
input group "===== HEDGE LOCK ĐỘC LẬP ====="
input bool InpEnableHedgeLock = true;                   // Bật Hedge Lock
input double InpHedgeLockMDD = 1500;                    // MDD kích hoạt Hedge Lock (cent)
input double InpHedgeLockRatio = 1.0;                   // Tỷ lệ Hedge Lock (1.0 = 100% imbalance)

//--- Cài đặt Hedge DCA (cũ - vẫn giữ)
input group "===== HỆ THỐNG HEDGE DCA ====="
input bool InpEnableHedge = true;                       // Bật chế độ Hedge DCA
input int InpHedgeTrigger = 10;                         // Số lệnh DCA kích hoạt Hedge
input double InpHedgeRatio = 0.5;                       // Tỷ lệ Hedge DCA (0.5 = 1/2 lot chính)

//--- Hệ thống cảnh báo xu hướng
input group "===== HỆ THỐNG CẢNH BÁO XU HƯỚNG ====="
input bool InpEnableTrendWarning = true;                // Bật cảnh báo xu hướng
input int InpTrendWarningOrders = 30;                   // Số lệnh kích hoạt Warning
input double InpTrendWarningMDD = 1000;                 // MDD kích hoạt Warning (cent)
input int InpTrendCheckInterval = 60;                   // Kiểm tra xu hướng (giây)

//--- Mục tiêu ngày
input group "===== MỤC TIÊU NGÀY ====="
input bool InpEnableDailyTarget = true;                 // Bật mục tiêu lợi nhuận ngày
input double InpDailyTarget = 500.0;                    // Mục tiêu lợi nhuận (USD/ngày)

//--- Telegram
input group "===== TELEGRAM (UTF-8 Fixed) ====="
input bool InpEnableTelegram = false;                   // Bật thông báo Telegram
input string InpTelegramToken = "";                     // Telegram Bot Token
input string InpTelegramChatID = "";                    // Telegram Chat ID
input int InpTelegramInterval = 30;                     // Khoảng thời gian báo cáo (phút)

//--- Panel
input group "===== BẢNG ĐIỀU KHIỂN (Panel v2.22) ====="
input bool InpShowPanel = true;                         // Hiển thị Panel
input int InpPanelX = 20;                               // Vị trí X
input int InpPanelY = 50;                               // Vị trí Y
input color InpPanelColor = clrNavy;                    // Màu nền Panel

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES - Biến toàn cục                                 |
//+------------------------------------------------------------------+

// Cấu trúc thông tin lệnh
struct OrderInfo {
   ulong ticket;
   int type;           // 0=Buy, 1=Sell
   double lots;
   double openPrice;
   datetime openTime;
   bool isHedge;       // Đánh dấu lệnh Hedge DCA
   bool isHedgeLock;   // Đánh dấu lệnh Hedge Lock
   int pairIndex;      // Chỉ số cặp (dùng cho Mode 2)
};

OrderInfo g_orders[];           // Mảng lưu thông tin lệnh
int g_orderCount = 0;           // Tổng số lệnh

// Trạng thái DCA Mode
ENUM_DCA_MODE g_currentMode = MODE_NEGATIVE;
int g_pairCount = 0;
bool g_modeSwitched = false;

// Trạng thái Hedge DCA (cũ)
bool g_isHedgeActive = false;
double g_lastHedgePrice = 0;
int g_hedgeDirection = -1;

// 🆕 v2.23: Hedge mới - One Hedge Per DCA
struct HedgeInfo {
   ulong dcaTicket;      // Ticket lệnh DCA chính
   ulong hedgeTicket;    // Ticket lệnh Hedge tương ứng
   bool isActive;        // Hedge này còn active không
};
HedgeInfo g_hedgeList[];  // Danh sách các cặp DCA-Hedge
int g_hedgeCount = 0;     // Số lượng hedge đang active
ulong g_lastDCATicket = 0; // Ticket lệnh DCA cuối cùng (để check lệnh mới)

// Trạng thái Hedge Lock (độc lập)
bool g_hedgeLockActive = false;
ulong g_hedgeLockTicket = 0;
double g_hedgeLockOpenPrice = 0;
int g_hedgeLockDirection = -1;  // 0=BUY, 1=SELL
double g_hedgeLockLot = 0;
datetime g_lastHedgeLockCheck = 0;

// Theo dõi DCA progression
double g_lastBuyLot = 0;
double g_lastSellLot = 0;
int g_buyDCACount = 0;
int g_sellDCACount = 0;

// 🆕 v2.22: Trailing TP Pro variables
double g_highestProfit = 0;
double g_breakevenLevel = 0;
bool g_breakevenActivated = false;
int g_currentTrailingLevel = 0;
double g_currentTrailingDistance = 0;
datetime g_lastProfitCheckTime = 0;
double g_lastProfitCheck = 0;
int g_recoveryBarsCount = 0;
bool g_emergencyMode = false;

// Theo dõi profit khác
double g_dailyStartBalance = 0;
datetime g_lastDayCheck = 0;
datetime g_lastTrailingCheckTime = 0;

// Trend Warning
ENUM_TREND_LEVEL g_trendLevel = TREND_NORMAL;
datetime g_lastTrendCheck = 0;
bool g_trendWarningShown = false;

// Telegram
datetime g_lastTelegramTime = 0;

// Panel objects
string g_panelPrefix = "VEPanel_";

// Giá lệnh đầu và cuối
double g_firstOrderPrice = 0;
double g_lastOrderPrice = 0;

// Tracking last bar
datetime g_lastBarTime = 0;

// ATR Handle
int g_atrHandle = INVALID_HANDLE;

// 🆕 v2.22: Countdown & TP Line
datetime g_lastTPLineUpdate = 0;
string g_tpLineName = "VE_TPLine";

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
   // Thiết lập Magic Number
   trade.SetExpertMagicNumber(InpMagicNumber);
   
   // Khởi tạo mode
   g_currentMode = InpDCAMode;
   
   // Khởi tạo balance đầu ngày
   g_dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_lastDayCheck = TimeCurrent();
   
   // Khởi tạo last bar time
   g_lastBarTime = iTime(_Symbol, InpTimeframe, 0);
   g_lastTrailingCheckTime = g_lastBarTime;
   
   // Khởi tạo ATR indicator nếu dùng TRIGGER_ATR
   if(InpDCATrigger == TRIGGER_ATR) {
      g_atrHandle = iATR(_Symbol, InpTimeframe, InpATRPeriod);
      if(g_atrHandle == INVALID_HANDLE) {
         Print("❌ Lỗi khởi tạo ATR indicator!");
         return INIT_FAILED;
      }
   }
   
   // Tải lại thông tin lệnh đang mở
   LoadExistingOrders();
   
   // Tạo Panel UI
   if(InpShowPanel) {
      CreatePanel();
   }
   
   // Bật Chart Event
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
   ChartSetInteger(0, CHART_EVENT_OBJECT_CREATE, true);
   ChartSetInteger(0, CHART_EVENT_OBJECT_DELETE, true);
   
   Print("════════════════════════════════════════════════════════");
   Print("⚡ EA VangExness DCA Hedge v2.24 - CRITICAL FIXES ⚡");
   Print("════════════════════════════════════════════════════════");
   Print("Symbol: ", _Symbol);
   Print("Timeframe: ", EnumToString(InpTimeframe));
   Print("DCA Mode: ", g_currentMode == MODE_NEGATIVE ? "DCA Âm" : 
                       g_currentMode == MODE_POSITIVE ? "DCA Dương" : "DCA Cặp");
   Print("Lot Progression: ", InpLotProgression == LOT_ADD ? "Hệ Cộng" : "Hệ Nhân");
   Print("DCA Trigger: ", InpDCATrigger == TRIGGER_BAR_CLOSE ? "Nến đóng" : 
                          InpDCATrigger == TRIGGER_STEP ? "Step cố định" : "ATR động");
   Print("════════════════════════════════════════════════════════");
   Print("🔥 v2.24 - 3 CRITICAL FIXES:");
   Print("   ✅ FIX 1: Lot tracking - Tìm lot LỚN NHẤT, làm tròn 3 số");
   Print("   ✅ FIX 2: DCA Cặp - Áp dụng AllowRefill, check hướng giá");
   Print("   ✅ FIX 3: Hedge Lock - Tính drawdown thực, đóng an toàn");
   Print("   ⚠️  QUAN TRỌNG: Hạn chế lot hedge = 50% tổng lot");
   Print("   ⚠️  AN TOÀN: Không đóng hedge khi ÂM (tránh vòng lặp)");
   Print("════════════════════════════════════════════════════════");
   
   if(InpEnableTelegram && (InpTelegramToken == "" || InpTelegramChatID == "")) {
      Print("⚠️ WARNING: Telegram enabled but Token/ChatID empty!");
   }
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   // Giải phóng ATR handle
   if(g_atrHandle != INVALID_HANDLE) {
      IndicatorRelease(g_atrHandle);
   }
   
   // Xóa TP Line
   ObjectDelete(0, g_tpLineName);
   
   // Xóa Panel
   if(InpShowPanel) {
      DeletePanel();
   }
   
   Print("EA stopped. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick() {
   // 1. Kiểm tra Daily Target
   if(InpEnableDailyTarget) {
      if(CheckDailyTarget()) {
         Comment("✅ Đạt mục tiêu ngày! EA đã dừng.");
         ExpertRemove();
         return;
      }
   }
   
   // 2. Tải lại thông tin lệnh hiện tại
   LoadExistingOrders();
   
   // 3. Quản lý Hedge Lock (độc lập, ưu tiên cao nhất)
   if(InpEnableHedgeLock) {
      ManageHedgeLock();
   }
   
   // 4. Kiểm tra và cảnh báo xu hướng
   if(InpEnableTrendWarning) {
      CheckTrendWarning();
   }
   
   // 5. Kiểm tra và quản lý Trailing TP Pro
   if(InpEnableTrailing) {
      ManageTrailingTP();
   }
   
   // 6. Kiểm tra TP tổng (không trailing)
   if(!InpEnableTrailing && CheckTotalTP()) {
      CloseAllOrders();
      ResetEA();
      return;
   }
   
   // 7. Kiểm tra SL tổng
   if(InpTotalStopLoss > 0 && CheckTotalSL()) {
      CloseAllOrders();
      ResetEA();
      Print("❌ SL tổng chạm! Đóng tất cả lệnh.");
      return;
   }
   
   // 8. Logic mở lệnh theo DCA Trigger
   ManageOrdersByTrigger();
   
   // 9. Cập nhật TP Line
   UpdateTPLine();
   
   // 10. Cập nhật Panel
   if(InpShowPanel) {
      UpdatePanel();
   }
   
   // 11. Gửi Telegram report
   if(InpEnableTelegram) {
      SendTelegramReport();
   }
}

//+------------------------------------------------------------------+
//| Quản lý lệnh theo DCA Trigger Mode                               |
//+------------------------------------------------------------------+
void ManageOrdersByTrigger() {
   if(InpDCATrigger == TRIGGER_BAR_CLOSE) {
      // Chỉ mở lệnh khi nến đóng
      datetime currentBarTime = iTime(_Symbol, InpTimeframe, 0);
      
      if(currentBarTime != g_lastBarTime) {
         g_lastBarTime = currentBarTime;
         ManageOrders();
      }
   } 
   else {
      // TRIGGER_STEP hoặc TRIGGER_ATR: Mở ngay khi đủ điều kiện
      ManageOrders();
   }
}

//+------------------------------------------------------------------+
//| Chart Event - Xử lý click chuột vào nút                          |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam) {
   
   if(id == CHARTEVENT_OBJECT_CLICK) {
      
      // Nút Close All
      if(sparam == g_panelPrefix + "BtnCloseAll") {
         CloseAllOrdersManual();
         ObjectSetInteger(0, g_panelPrefix + "BtnCloseAll", OBJPROP_STATE, false);
      }
      
      // Nút Close Buy
      if(sparam == g_panelPrefix + "BtnCloseBuy") {
         CloseBuyOrders();
         ObjectSetInteger(0, g_panelPrefix + "BtnCloseBuy", OBJPROP_STATE, false);
      }
      
      // Nút Close Sell
      if(sparam == g_panelPrefix + "BtnCloseSell") {
         CloseSellOrders();
         ObjectSetInteger(0, g_panelPrefix + "BtnCloseSell", OBJPROP_STATE, false);
      }
      
      // Nút Trim Orders
      if(sparam == g_panelPrefix + "BtnTrim") {
         ShowTrimMenu();
         ObjectSetInteger(0, g_panelPrefix + "BtnTrim", OBJPROP_STATE, false);
      }
      
      // Nút Force Lock
      if(sparam == g_panelPrefix + "BtnForceLock") {
         ForceHedgeLock();
         ObjectSetInteger(0, g_panelPrefix + "BtnForceLock", OBJPROP_STATE, false);
      }
      
      // Nút Force Unlock
      if(sparam == g_panelPrefix + "BtnForceUnlock") {
         ForceUnlockHedge();
         ObjectSetInteger(0, g_panelPrefix + "BtnForceUnlock", OBJPROP_STATE, false);
      }
      
      ChartRedraw();
   }
}

//+------------------------------------------------------------------+
//| 🆕 v2.22: TRAILING TP PRO - Quản lý chốt lời nâng cao            |
//+------------------------------------------------------------------+
void ManageTrailingTP() {
   double totalProfit = CalculateTotalProfit();
   
   // ═══════════════════════════════════════════════════════════════
   // BƯỚC 1: CẬP NHẬT PROFIT CAO NHẤT
   // ═══════════════════════════════════════════════════════════════
   if(totalProfit > g_highestProfit) {
      g_highestProfit = totalProfit;
      Print("📊 [TRAILING PRO] Profit đỉnh mới: $", g_highestProfit);
      
      // Reset recovery counter khi profit tăng
      g_recoveryBarsCount = 0;
      g_emergencyMode = false;
   }
   
   // ═══════════════════════════════════════════════════════════════
   // BƯỚC 2: CHỜ ĐỂ PROFIT ĐẠT TP GỐC
   // ═══════════════════════════════════════════════════════════════
   if(totalProfit < InpTotalTP) {
      return;
   }
   
   // ═══════════════════════════════════════════════════════════════
   // BƯỚC 3: 🆕 BREAKEVEN PROTECTION
   // ═══════════════════════════════════════════════════════════════
   if(InpEnableBreakeven && !g_breakevenActivated) {
      double breakevenThreshold = InpTotalTP * InpBreakevenMultiplier;
      
      if(totalProfit >= breakevenThreshold) {
         g_breakevenLevel = InpTotalTP;
         g_breakevenActivated = true;
         
         Print("════════════════════════════════════════");
         Print("🛡️ [BREAKEVEN] ACTIVATED!");
         Print("   Profit: $", totalProfit);
         Print("   Threshold: $", breakevenThreshold);
         Print("   Breakeven Level: $", g_breakevenLevel);
         Print("════════════════════════════════════════");
         
         // Gửi Telegram
         if(InpEnableTelegram) {
            string msg = "🛡️ BREAKEVEN ACTIVATED!\n\n";
            msg += "Profit: $" + DoubleToString(totalProfit, 2) + "\n";
            msg += "Protected Level: $" + DoubleToString(g_breakevenLevel, 2);
            SendTelegramMessage(msg);
         }
      }
   }
   
   // ═══════════════════════════════════════════════════════════════
   // BƯỚC 4: 🆕 EMERGENCY FLOOR PROTECTION
   // ═══════════════════════════════════════════════════════════════
   double emergencyFloorLevel = InpTotalTP * (InpEmergencyFloor / 100.0);
   
   if(totalProfit < emergencyFloorLevel) {
      Print("════════════════════════════════════════");
      Print("🚨 [EMERGENCY] FLOOR BREACHED!");
      Print("   Profit: $", totalProfit);
      Print("   Floor: $", emergencyFloorLevel);
      Print("   → ĐÓNG NGAY ĐỂ BẢO VỆ!");
      Print("════════════════════════════════════════");
      
      CloseAllOrders();
      ResetEA();
      
      if(InpEnableTelegram) {
         string msg = "🚨 EMERGENCY FLOOR!\n\n";
         msg += "Profit dropped to: $" + DoubleToString(totalProfit, 2) + "\n";
         msg += "Floor level: $" + DoubleToString(emergencyFloorLevel, 2) + "\n";
         msg += "All positions closed!";
         SendTelegramMessage(msg);
      }
      
      return;
   }
   
   // ═══════════════════════════════════════════════════════════════
   // BƯỚC 5: 🆕 MINIMUM PROFIT PROTECTION
   // ═══════════════════════════════════════════════════════════════
   if(totalProfit < InpMinimumProfit) {
      Print("════════════════════════════════════════");
      Print("⚠️ [MINIMUM PROFIT] PROTECTION!");
      Print("   Profit: $", totalProfit);
      Print("   Minimum: $", InpMinimumProfit);
      Print("   → ĐÓNG NGAY!");
      Print("════════════════════════════════════════");
      
      CloseAllOrders();
      ResetEA();
      return;
   }
   
   // ═══════════════════════════════════════════════════════════════
   // BƯỚC 6: 🆕 XÁC ĐỊNH TRAILING LEVEL (Multi-Level)
   // ═══════════════════════════════════════════════════════════════
   int newLevel = 0;
   double baseDistance = 0;
   
   if(InpEnableMultiLevel) {
      if(g_highestProfit >= InpTrailingLevel3_Profit) {
         newLevel = 3;
         baseDistance = InpTrailingLevel3_Distance;
      } else if(g_highestProfit >= InpTrailingLevel2_Profit) {
         newLevel = 2;
         baseDistance = InpTrailingLevel2_Distance;
      } else if(g_highestProfit >= InpTrailingLevel1_Profit) {
         newLevel = 1;
         baseDistance = InpTrailingLevel1_Distance;
      } else {
         baseDistance = InpTotalTP * 0.3;
      }
      
      // Thông báo khi chuyển level
      if(newLevel != g_currentTrailingLevel && newLevel > 0) {
         Print("════════════════════════════════════════");
         Print("📈 [TRAILING] LEVEL UP!");
         Print("   Level: ", g_currentTrailingLevel, " → ", newLevel);
         Print("   Distance: $", baseDistance);
         Print("════════════════════════════════════════");
         
         g_currentTrailingLevel = newLevel;
      }
   } else {
      baseDistance = InpTotalTP * 0.5;
   }
   
   // ═══════════════════════════════════════════════════════════════
   // BƯỚC 7: 🆕 ACCELERATION TRAILING
   // ═══════════════════════════════════════════════════════════════
   if(InpEnableAcceleration && g_highestProfit > InpTotalTP * 2) {
      int accelerationLevel = (int)((g_highestProfit / InpTotalTP) / 2);
      
      for(int i = 0; i < accelerationLevel && i < 3; i++) {
         baseDistance *= InpAccelMultiplier;
      }
      
      Print("🚀 [ACCELERATION] Active | Level: ", accelerationLevel, " | New Distance: $", baseDistance);
   }
   
   g_currentTrailingDistance = baseDistance;
   
   // ═══════════════════════════════════════════════════════════════
   // BƯỚC 8: 🆕 SMART RECOVERY MODE
   // ═══════════════════════════════════════════════════════════════
   if(InpEnableSmartRecovery) {
      datetime currentBarTime = iTime(_Symbol, InpTimeframe, 0);
      
      if(currentBarTime != g_lastProfitCheckTime) {
         g_lastProfitCheckTime = currentBarTime;
         
         if(totalProfit > g_lastProfitCheck && totalProfit < g_highestProfit) {
            g_recoveryBarsCount++;
            
            if(g_recoveryBarsCount >= InpRecoveryBars) {
               g_currentTrailingDistance *= 1.2;
               
               Print("════════════════════════════════════════");
               Print("🌱 [SMART RECOVERY] Nới trailing");
               Print("   Recovery bars: ", g_recoveryBarsCount);
               Print("   New distance: $", g_currentTrailingDistance);
               Print("════════════════════════════════════════");
               
               g_recoveryBarsCount = 0;
            }
         } else {
            g_recoveryBarsCount = 0;
         }
         
         g_lastProfitCheck = totalProfit;
      }
   }
   
   // ═══════════════════════════════════════════════════════════════
   // BƯỚC 9: TÍNH TRAILING STOP
   // ═══════════════════════════════════════════════════════════════
   double trailingStop = g_highestProfit - g_currentTrailingDistance;
   
   if(g_breakevenActivated && trailingStop < g_breakevenLevel) {
      trailingStop = g_breakevenLevel;
   }
   
   if(trailingStop < InpMinimumProfit) {
      trailingStop = InpMinimumProfit;
   }
   
   // ═══════════════════════════════════════════════════════════════
   // BƯỚC 10: KIỂM TRA VÀ ĐÓNG LỆNH
   // ═══════════════════════════════════════════════════════════════
   if(totalProfit <= trailingStop) {
      Print("════════════════════════════════════════");
      Print("📉 [TRAILING PRO] TP TRIGGERED!");
      Print("   Profit cao nhất: $", g_highestProfit);
      Print("   Profit hiện tại: $", totalProfit);
      Print("   Trailing stop: $", trailingStop);
      Print("   Trailing distance: $", g_currentTrailingDistance);
      Print("   Level: ", g_currentTrailingLevel);
      Print("════════════════════════════════════════");
      
      CloseAllOrders();
      ResetEA();
      
      if(InpEnableTelegram) {
         string msg = "✅ TRAILING TP CLOSED!\n\n";
         msg += "Peak Profit: $" + DoubleToString(g_highestProfit, 2) + "\n";
         msg += "Close Profit: $" + DoubleToString(totalProfit, 2) + "\n";
         msg += "Level: " + IntegerToString(g_currentTrailingLevel) + "\n";
         msg += "Distance: $" + DoubleToString(g_currentTrailingDistance, 2);
         SendTelegramMessage(msg);
      }
   }
   
   // ═══════════════════════════════════════════════════════════════
   // BƯỚC 11: LOG TRẠNG THÁI
   // ═══════════════════════════════════════════════════════════════
   static datetime lastLogTime = 0;
   if(TimeCurrent() - lastLogTime >= 10) {
      lastLogTime = TimeCurrent();
      
      double drawdown = g_highestProfit - totalProfit;
      double drawdownPercent = (g_highestProfit > 0) ? (drawdown / g_highestProfit * 100) : 0;
      
      Print("📊 [TRAILING STATUS] Profit: $", totalProfit, 
            " | Peak: $", g_highestProfit,
            " | Drawdown: ", DoubleToString(drawdownPercent, 1), "%",
            " | Stop: $", trailingStop,
            " | Level: ", g_currentTrailingLevel);
   }
}

//+------------------------------------------------------------------+
//| 🆕 v2.22: Tính thời gian còn lại đến khi nến đóng                |
//+------------------------------------------------------------------+
string GetBarCloseCountdown() {
   datetime currentTime = TimeCurrent();
   datetime barOpenTime = iTime(_Symbol, InpTimeframe, 0);
   int periodSeconds = PeriodSeconds(InpTimeframe);
   
   datetime barCloseTime = barOpenTime + periodSeconds;
   int remainingSeconds = (int)(barCloseTime - currentTime);
   
   if(remainingSeconds < 0) remainingSeconds = 0;
   
   int minutes = remainingSeconds / 60;
   int seconds = remainingSeconds % 60;
   
   return StringFormat("%02d:%02d", minutes, seconds);
}

//+------------------------------------------------------------------+
//| 🆕 v2.22: Vẽ và cập nhật đường TP tổng                           |
//+------------------------------------------------------------------+
void UpdateTPLine() {
   // Chỉ cập nhật mỗi 60 giây
   datetime currentTime = TimeCurrent();
   if(currentTime - g_lastTPLineUpdate < 60) {
      return;
   }
   g_lastTPLineUpdate = currentTime;
   
   // Nếu không có lệnh → xóa line
   if(g_orderCount == 0) {
      ObjectDelete(0, g_tpLineName);
      return;
   }
   
   // Tính giá TP tổng
   double totalProfit = CalculateTotalProfit();
   double totalLots = 0;
   double avgOpenPrice = 0;
   
   for(int i = 0; i < g_orderCount; i++) {
      totalLots += g_orders[i].lots;
      avgOpenPrice += g_orders[i].openPrice * g_orders[i].lots;
   }
   
   if(totalLots == 0) {
      ObjectDelete(0, g_tpLineName);
      return;
   }
   
   avgOpenPrice = avgOpenPrice / totalLots;
   
   // Tính giá TP
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double pointValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double profitInPoints = (InpTotalTP - totalProfit) / (totalLots * pointValue);
   double tpPrice = currentPrice + (profitInPoints * _Point);
   
   // Vẽ hoặc cập nhật line
   if(ObjectFind(0, g_tpLineName) < 0) {
      ObjectCreate(0, g_tpLineName, OBJ_TREND, 0, 0, 0);
      ObjectSetInteger(0, g_tpLineName, OBJPROP_COLOR, clrLime);
      ObjectSetInteger(0, g_tpLineName, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, g_tpLineName, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, g_tpLineName, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, g_tpLineName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, g_tpLineName, OBJPROP_SELECTED, false);
      ObjectSetInteger(0, g_tpLineName, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, g_tpLineName, OBJPROP_BACK, false);
   }
   
   // Cập nhật vị trí (ngắn: 50 nến)
   datetime timeNow = TimeCurrent();
   datetime timeEnd = timeNow + PeriodSeconds(InpTimeframe) * 50;
   
   ObjectSetInteger(0, g_tpLineName, OBJPROP_TIME, 0, timeNow);
   ObjectSetDouble(0, g_tpLineName, OBJPROP_PRICE, 0, tpPrice);
   ObjectSetInteger(0, g_tpLineName, OBJPROP_TIME, 1, timeEnd);
   ObjectSetDouble(0, g_tpLineName, OBJPROP_PRICE, 1, tpPrice);
   
   // Tooltip
   string tooltip = "TP: $" + DoubleToString(InpTotalTP, 2) + 
                    " | Current: $" + DoubleToString(totalProfit, 2) +
                    " | Need: $" + DoubleToString(InpTotalTP - totalProfit, 2);
   ObjectSetString(0, g_tpLineName, OBJPROP_TOOLTIP, tooltip);
}

//+------------------------------------------------------------------+
//| HEDGE LOCK - Quản lý chính                                       |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| 🔥 FIX v2.24: HEDGE LOCK AN TOÀN - Logic hoàn toàn mới          |
//+------------------------------------------------------------------+
void ManageHedgeLock() {
   // ═══════════════════════════════════════════════════════════════
   // BƯỚC 1: TÍNH DRAWDOWN THỰC (không phải profit)
   // ═══════════════════════════════════════════════════════════════
   double drawdown = CalculateMaxDrawdown();
   
   // ═══════════════════════════════════════════════════════════════
   // BƯỚC 2: KÍCH HOẠT HEDGE LOCK khi drawdown > threshold
   // ═══════════════════════════════════════════════════════════════
   if(!g_hedgeLockActive && drawdown >= InpHedgeLockMDD) {
      
      // Tính tổng lot hiện tại
      double totalBuyLot = 0;
      double totalSellLot = 0;
      double totalLots = 0;
      
      for(int i = 0; i < g_orderCount; i++) {
         if(g_orders[i].isHedgeLock) continue;
         
         totalLots += g_orders[i].lots;
         
         if(g_orders[i].type == POSITION_TYPE_BUY) {
            totalBuyLot += g_orders[i].lots;
         } else {
            totalSellLot += g_orders[i].lots;
         }
      }
      
      double imbalance = totalBuyLot - totalSellLot;
      
      // Chỉ mở hedge nếu có imbalance đáng kể
      if(MathAbs(imbalance) > 0.01) {
         // Xác định hướng
         if(imbalance > 0) {
            g_hedgeLockDirection = POSITION_TYPE_SELL;
         } else {
            g_hedgeLockDirection = POSITION_TYPE_BUY;
         }
         
         // 🔥 FIX: Tính lot AN TOÀN
         // Không để hedge lot quá lớn → limit = 50% tổng lot hiện tại
         double maxSafeLot = totalLots * 0.5;
         g_hedgeLockLot = MathAbs(imbalance) * InpHedgeLockRatio;
         
         // Giới hạn an toàn
         if(g_hedgeLockLot > maxSafeLot) {
            g_hedgeLockLot = maxSafeLot;
            Print("⚠️ Hedge Lock lot giới hạn an toàn: ", g_hedgeLockLot, " (max: ", maxSafeLot, ")");
         }
         
         g_hedgeLockLot = NormalizeDouble(g_hedgeLockLot, 3);
         
         // Kiểm tra lot tối thiểu
         double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         if(g_hedgeLockLot < minLot) {
            Print("⚠️ Hedge Lock lot quá nhỏ: ", g_hedgeLockLot, " < ", minLot);
            return;
         }
         
         // Mở Hedge Lock
         if(OpenHedgeLock()) {
            g_hedgeLockActive = true;
            
            Print("════════════════════════════════════════");
            Print("🔒 HEDGE LOCK ACTIVATED!");
            Print("   Drawdown: $", drawdown, " (threshold: $", InpHedgeLockMDD, ")");
            Print("   Total Lot: ", totalLots);
            Print("   Imbalance: ", imbalance);
            Print("   Lock: ", g_hedgeLockDirection == POSITION_TYPE_BUY ? "BUY" : "SELL", " ", g_hedgeLockLot);
            Print("   Max Safe Lot: ", maxSafeLot);
            Print("════════════════════════════════════════");
            
            // Gửi Telegram
            if(InpEnableTelegram) {
               string msg = "🔒 HEDGE LOCK!\n\n";
               msg += "Drawdown: $" + DoubleToString(drawdown, 2) + "\n";
               msg += "Lock: " + DoubleToString(g_hedgeLockLot, 3) + " lot";
               SendTelegramMessage(msg);
            }
         }
      }
   }
   
   // ═══════════════════════════════════════════════════════════════
   // BƯỚC 3: QUẢN LÝ HEDGE LOCK ĐANG ACTIVE
   // ═══════════════════════════════════════════════════════════════
   if(g_hedgeLockActive && g_hedgeLockTicket > 0) {
      
      // Kiểm tra lệnh còn tồn tại không
      if(!PositionSelectByTicket(g_hedgeLockTicket)) {
         Print("⚠️ Hedge Lock ticket #", g_hedgeLockTicket, " không tồn tại!");
         g_hedgeLockActive = false;
         g_hedgeLockTicket = 0;
         return;
      }
      
      // Lấy thông tin lệnh
      double lockProfit = PositionGetDouble(POSITION_PROFIT);
      double lockSwap = PositionGetDouble(POSITION_SWAP);
      double lockTotalProfit = lockProfit + lockSwap;
      
      // Tính drawdown hiện tại
      double currentDrawdown = CalculateMaxDrawdown();
      
      // Tính recovery threshold = 50% drawdown ban đầu
      double recoveryThreshold = InpHedgeLockMDD * 0.5;
      
      // 🔥 FIX: ĐIỀU KIỆN ĐÓNG AN TOÀN
      // Chỉ đóng khi 1 trong 2 điều kiện:
      // 1. Drawdown giảm >= 50% (recovery)
      // 2. Hedge Lock lãi >= 30% của mdd threshold
      
      bool shouldClose = false;
      string closeReason = "";
      
      // Điều kiện 1: Drawdown đã giảm >= 50%
      if(currentDrawdown <= recoveryThreshold) {
         shouldClose = true;
         closeReason = "Drawdown recovery";
      }
      
      // Điều kiện 2: Hedge Lock lãi đủ lớn (>= 30% threshold)
      double profitThreshold = InpHedgeLockMDD * 0.3;
      if(lockTotalProfit >= profitThreshold) {
         shouldClose = true;
         closeReason = "Hedge profit target";
      }
      
      if(shouldClose) {
         Print("════════════════════════════════════════");
         Print("🔓 CLOSING HEDGE LOCK");
         Print("   Reason: ", closeReason);
         Print("   Lock Profit: $", lockTotalProfit);
         Print("   Current Drawdown: $", currentDrawdown);
         Print("   Recovery Threshold: $", recoveryThreshold);
         Print("════════════════════════════════════════");
         
         if(trade.PositionClose(g_hedgeLockTicket)) {
            Print("✅ Đã đóng Hedge Lock | Profit: $", lockTotalProfit);
            
            // Gửi Telegram
            if(InpEnableTelegram) {
               string msg = "🔓 HEDGE LOCK CLOSED!\n\n";
               msg += "Profit: $" + DoubleToString(lockTotalProfit, 2) + "\n";
               msg += "Reason: " + closeReason;
               SendTelegramMessage(msg);
            }
         } else {
            Print("❌ Lỗi đóng Hedge Lock: ", GetLastError());
         }
         
         // Reset
         g_hedgeLockActive = false;
         g_hedgeLockTicket = 0;
         g_hedgeLockOpenPrice = 0;
         g_hedgeLockDirection = -1;
         g_hedgeLockLot = 0;
      } else {
         // Chỉ log mỗi 30 giây
         static datetime lastHedgeLog = 0;
         if(TimeCurrent() - lastHedgeLog >= 30) {
            lastHedgeLog = TimeCurrent();
            
            Print("🔒 Hedge Lock Active:");
            Print("   Profit: $", lockTotalProfit);
            Print("   Drawdown: $", currentDrawdown, " / $", recoveryThreshold, " (", 
                  DoubleToString((recoveryThreshold - currentDrawdown) / recoveryThreshold * 100, 1), "% to recovery)");
         }
      }
   }
}

bool OpenHedgeLock() {
   string comment = "HEDGE_LOCK";
   double price = 0;
   
   if(g_hedgeLockDirection == POSITION_TYPE_BUY) {
      price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   } else {
      price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   }
   
   bool result = trade.PositionOpen(_Symbol, 
                                    (ENUM_ORDER_TYPE)g_hedgeLockDirection, 
                                    g_hedgeLockLot, 
                                    price, 
                                    0, 0, 
                                    comment);
   
   if(result) {
      g_hedgeLockTicket = trade.ResultOrder();
      g_hedgeLockOpenPrice = price;
      return true;
   }
   
   return false;
}

void ForceHedgeLock() {
   if(g_hedgeLockActive) {
      Print("⚠️ Hedge Lock đã active!");
      return;
   }
   
   Print("🔒 [MANUAL] Force Hedge Lock...");
   
   double totalBuyLot = 0;
   double totalSellLot = 0;
   
   for(int i = 0; i < g_orderCount; i++) {
      if(g_orders[i].isHedgeLock) continue;
      
      if(g_orders[i].type == POSITION_TYPE_BUY) {
         totalBuyLot += g_orders[i].lots;
      } else {
         totalSellLot += g_orders[i].lots;
      }
   }
   
   double imbalance = totalBuyLot - totalSellLot;
   
   if(MathAbs(imbalance) < 0.01) {
      Print("⚠️ Không có imbalance!");
      return;
   }
   
   if(imbalance > 0) {
      g_hedgeLockDirection = POSITION_TYPE_SELL;
   } else {
      g_hedgeLockDirection = POSITION_TYPE_BUY;
   }
   
   g_hedgeLockLot = MathAbs(imbalance) * InpHedgeLockRatio;
   g_hedgeLockLot = NormalizeDouble(g_hedgeLockLot, 2);
   
   if(OpenHedgeLock()) {
      g_hedgeLockActive = true;
      Print("✅ Force Hedge Lock thành công!");
   }
}

void ForceUnlockHedge() {
   if(!g_hedgeLockActive || g_hedgeLockTicket == 0) {
      Print("⚠️ Không có Hedge Lock!");
      return;
   }
   
   Print("🔓 [MANUAL] Force Unlock...");
   
   if(PositionSelectByTicket(g_hedgeLockTicket)) {
      if(trade.PositionClose(g_hedgeLockTicket)) {
         Print("✅ Đã đóng Hedge Lock");
         g_hedgeLockActive = false;
         g_hedgeLockTicket = 0;
      }
   }
}

//+------------------------------------------------------------------+
//| Kiểm tra và cảnh báo xu hướng                                    |
//+------------------------------------------------------------------+
void CheckTrendWarning() {
   datetime currentTime = TimeCurrent();
   
   if(currentTime - g_lastTrendCheck < InpTrendCheckInterval) {
      return;
   }
   
   g_lastTrendCheck = currentTime;
   
   double recovery = CalculateRecoveryPercent();
   double mdd = CalculateTotalProfit();
   int orderCount = g_orderCount;
   
   ENUM_TREND_LEVEL oldLevel = g_trendLevel;
   g_trendLevel = TREND_NORMAL;
   
   if(orderCount > 60 || mdd < -2000 || recovery < 10) {
      g_trendLevel = TREND_CRITICAL;
   }
   else if(orderCount > 40 || mdd < -InpTrendWarningMDD || recovery < 20) {
      g_trendLevel = TREND_DANGER;
   }
   else if(orderCount > InpTrendWarningOrders || mdd < -(InpTrendWarningMDD/2) || recovery < 40) {
      g_trendLevel = TREND_WARNING;
   }
   
   if(g_trendLevel != oldLevel && g_trendLevel != TREND_NORMAL) {
      string levelText = "";
      string emoji = "";
      
      switch(g_trendLevel) {
         case TREND_WARNING:
            levelText = "CẢNH BÁO";
            emoji = "🟡";
            break;
         case TREND_DANGER:
            levelText = "NGUY HIỂM";
            emoji = "🔴";
            break;
         case TREND_CRITICAL:
            levelText = "CỰC KỲ NGUY HIỂM";
            emoji = "⛔";
            break;
      }
      
      Print("════════════════════════════════════════");
      Print(emoji, " XU HƯỚNG: ", levelText);
      Print("   Số lệnh: ", orderCount);
      Print("   MDD: $", mdd);
      Print("   Recovery: ", DoubleToString(recovery, 1), "%");
      Print("════════════════════════════════════════");
   }
}

//+------------------------------------------------------------------+
//| Hiện menu Trim Orders                                            |
//+------------------------------------------------------------------+
void ShowTrimMenu() {
   int choice = MessageBox(
      "═══════════════════════════════\n"
      "        ✂️ TRIM ORDERS          \n"
      "═══════════════════════════════\n\n"
      "YES = Trim Profit (lệnh lãi nhỏ)\n"
      "NO = Trim Far (lệnh xa giá)\n"
      "CANCEL = Hủy\n",
      "✂️ TRIM ORDERS",
      MB_YESNOCANCEL | MB_ICONQUESTION
   );
   
   if(choice == IDYES) {
      TrimProfitOrders();
   } else if(choice == IDNO) {
      TrimFarOrders();
   }
}

void TrimProfitOrders() {
   Print("✂️ [MANUAL] Trim Profit...");
   
   int closed = 0;
   double totalProfit = 0;
   
   for(int i = g_orderCount - 1; i >= 0; i--) {
      if(g_orders[i].isHedgeLock) continue;
      
      if(PositionSelectByTicket(g_orders[i].ticket)) {
         double profit = PositionGetDouble(POSITION_PROFIT);
         
         if(profit > 0 && profit < 2.0) {
            if(trade.PositionClose(g_orders[i].ticket)) {
               closed++;
               totalProfit += profit;
            }
         }
      }
   }
   
   Print("✅ Trim Profit: Đóng ", closed, " lệnh | Total: $", totalProfit);
   LoadExistingOrders();
}

void TrimFarOrders() {
   Print("✂️ [MANUAL] Trim Far...");
   
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   double totalDistance = 0;
   int count = 0;
   
   for(int i = 0; i < g_orderCount; i++) {
      if(g_orders[i].isHedgeLock) continue;
      totalDistance += MathAbs(currentPrice - g_orders[i].openPrice);
      count++;
   }
   
   if(count == 0) return;
   
   double avgDistance = totalDistance / count;
   double farThreshold = avgDistance * 1.5;
   
   int closed = 0;
   
   for(int i = g_orderCount - 1; i >= 0; i--) {
      if(g_orders[i].isHedgeLock) continue;
      
      double distance = MathAbs(currentPrice - g_orders[i].openPrice);
      
      if(distance > farThreshold) {
         if(PositionSelectByTicket(g_orders[i].ticket)) {
            if(trade.PositionClose(g_orders[i].ticket)) {
               closed++;
            }
         }
      }
   }
   
   Print("✅ Trim Far: Đóng ", closed, " lệnh");
   LoadExistingOrders();
}

//+------------------------------------------------------------------+
//| Đóng lệnh thủ công                                               |
//+------------------------------------------------------------------+
void CloseAllOrdersManual() {
   Print("🔴 [MANUAL] Đóng tất cả lệnh...");
   
   int closed = 0;
   for(int i = g_orderCount - 1; i >= 0; i--) {
      if(PositionSelectByTicket(g_orders[i].ticket)) {
         if(trade.PositionClose(g_orders[i].ticket)) {
            closed++;
         }
      }
   }
   
   Print("✅ Đã đóng ", closed, " lệnh");
   LoadExistingOrders();
}

void CloseBuyOrders() {
   Print("🔵 [MANUAL] Đóng BUY...");
   
   int closed = 0;
   for(int i = g_orderCount - 1; i >= 0; i--) {
      if(g_orders[i].type == POSITION_TYPE_BUY) {
         if(PositionSelectByTicket(g_orders[i].ticket)) {
            if(trade.PositionClose(g_orders[i].ticket)) {
               closed++;
            }
         }
      }
   }
   
   Print("✅ Đã đóng ", closed, " lệnh BUY");
   LoadExistingOrders();
}

void CloseSellOrders() {
   Print("🔴 [MANUAL] Đóng SELL...");
   
   int closed = 0;
   for(int i = g_orderCount - 1; i >= 0; i--) {
      if(g_orders[i].type == POSITION_TYPE_SELL) {
         if(PositionSelectByTicket(g_orders[i].ticket)) {
            if(trade.PositionClose(g_orders[i].ticket)) {
               closed++;
            }
         }
      }
   }
   
   Print("✅ Đã đóng ", closed, " lệnh SELL");
   LoadExistingOrders();
}

//+------------------------------------------------------------------+
//| Tải thông tin các lệnh đang mở                                   |
//+------------------------------------------------------------------+
void LoadExistingOrders() {
   ArrayResize(g_orders, 0);
   g_orderCount = 0;
   
   g_buyDCACount = 0;
   g_sellDCACount = 0;
   g_lastBuyLot = 0;
   g_lastSellLot = 0;
   
   int total = PositionsTotal();
   for(int i = 0; i < total; i++) {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      
      int size = ArraySize(g_orders);
      ArrayResize(g_orders, size + 1);
      
      g_orders[size].ticket = ticket;
      g_orders[size].type = (int)PositionGetInteger(POSITION_TYPE);
      g_orders[size].lots = PositionGetDouble(POSITION_VOLUME);
      g_orders[size].openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      g_orders[size].openTime = (datetime)PositionGetInteger(POSITION_TIME);
      
      string comment = PositionGetString(POSITION_COMMENT);
      g_orders[size].isHedge = (StringFind(comment, "HEDGE") >= 0 && StringFind(comment, "HEDGE_LOCK") < 0);
      g_orders[size].isHedgeLock = (StringFind(comment, "HEDGE_LOCK") >= 0);
      
      g_orders[size].pairIndex = 0;
      if(StringFind(comment, "PAIR") >= 0) {
         string parts[];
         StringSplit(comment, '_', parts);
         if(ArraySize(parts) >= 2) {
            g_orders[size].pairIndex = (int)StringToInteger(parts[1]);
         }
      }
      
      // 🔥 FIX v2.24: Tìm lot LỚN NHẤT thay vì cuối cùng
      if(!g_orders[size].isHedge && !g_orders[size].isHedgeLock) {
         if(g_orders[size].type == POSITION_TYPE_BUY) {
            // Tìm lot LỚN NHẤT trong tất cả lệnh BUY
            if(g_orders[size].lots > g_lastBuyLot) {
               g_lastBuyLot = g_orders[size].lots;
            }
            g_buyDCACount++;
         } else {
            // Tìm lot LỚN NHẤT trong tất cả lệnh SELL
            if(g_orders[size].lots > g_lastSellLot) {
               g_lastSellLot = g_orders[size].lots;
            }
            g_sellDCACount++;
         }
      }
      
      g_orderCount++;
   }
   
   SortOrdersByTime();
   UpdateFirstLastPrice();
   UpdatePairCount();
}

void SortOrdersByTime() {
   if(g_orderCount <= 1) return;
   
   for(int i = 0; i < g_orderCount - 1; i++) {
      for(int j = 0; j < g_orderCount - i - 1; j++) {
         if(g_orders[j].openTime > g_orders[j+1].openTime) {
            OrderInfo temp = g_orders[j];
            g_orders[j] = g_orders[j+1];
            g_orders[j+1] = temp;
         }
      }
   }
}

void UpdateFirstLastPrice() {
   if(g_orderCount == 0) {
      g_firstOrderPrice = 0;
      g_lastOrderPrice = 0;
      return;
   }
   
   for(int i = 0; i < g_orderCount; i++) {
      if(!g_orders[i].isHedgeLock) {
         g_firstOrderPrice = g_orders[i].openPrice;
         break;
      }
   }
   
   for(int i = g_orderCount - 1; i >= 0; i--) {
      if(!g_orders[i].isHedge && !g_orders[i].isHedgeLock) {
         g_lastOrderPrice = g_orders[i].openPrice;
         break;
      }
   }
}

void UpdatePairCount() {
   if(g_currentMode != MODE_PAIRS) return;
   
   g_pairCount = 0;
   for(int i = 0; i < g_orderCount; i++) {
      if(!g_orders[i].isHedge && !g_orders[i].isHedgeLock && g_orders[i].pairIndex > g_pairCount) {
         g_pairCount = g_orders[i].pairIndex;
      }
   }
}

//+------------------------------------------------------------------+
//| Quản lý việc mở lệnh                                             |
//+------------------------------------------------------------------+
void ManageOrders() {
   if(g_orderCount == 0) {
      OpenInitialOrders();
      return;
   }
   
   if(g_orderCount >= InpMaxOrders) {
      return;
   }
   
   if(g_currentMode == MODE_PAIRS) {
      ManageOrdersMode2();
   } else {
      ManageOrdersMode1();
   }
}

void OpenInitialOrders() {
   Print("📌 Mở lệnh khởi đầu...");
   
   if(g_currentMode == MODE_PAIRS) {
      OpenOrder(ORDER_TYPE_BUY, InpInitialLot, "PAIR_1_BUY");
      OpenOrder(ORDER_TYPE_SELL, InpInitialLot, "PAIR_1_SELL");
      g_pairCount = 1;
   } else {
      OpenOrder(ORDER_TYPE_BUY, InpInitialLot, "INITIAL_BUY");
      OpenOrder(ORDER_TYPE_SELL, InpInitialLot, "INITIAL_SELL");
   }
}

void ManageOrdersMode1() {
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   // Tìm lệnh Buy và Sell cuối cùng (không tính Hedge)
   double lastBuyPrice = 0, lastSellPrice = 0;
   ulong lastBuyTicket = 0, lastSellTicket = 0;
   
   for(int i = g_orderCount - 1; i >= 0; i--) {
      if(g_orders[i].isHedge || g_orders[i].isHedgeLock) continue;
      
      if(g_orders[i].type == POSITION_TYPE_BUY && lastBuyPrice == 0) {
         lastBuyPrice = g_orders[i].openPrice;
         lastBuyTicket = g_orders[i].ticket;
      }
      if(g_orders[i].type == POSITION_TYPE_SELL && lastSellPrice == 0) {
         lastSellPrice = g_orders[i].openPrice;
         lastSellTicket = g_orders[i].ticket;
      }
      
      if(lastBuyPrice > 0 && lastSellPrice > 0) break;
   }
   
   double dcaDistance = CalculateDCADistance();
   
   // ═══════════════════════════════════════════════════════════════
   // LOGIC DCA BUY
   // ═══════════════════════════════════════════════════════════════
   if(lastBuyPrice > 0) {
      bool shouldOpenBuy = false;
      
      if(g_currentMode == MODE_NEGATIVE) {
         // DCA ÂM: Giá GIẢM → Mở BUY thêm
         if(InpAllowRefill) {
            shouldOpenBuy = (currentPrice < lastBuyPrice - dcaDistance);
         } else {
            shouldOpenBuy = (currentPrice < lastBuyPrice - dcaDistance) && (currentPrice < lastBuyPrice);
         }
      } 
      else if(g_currentMode == MODE_POSITIVE) {
         // DCA DƯƠNG: Giá TĂNG → Mở BUY thêm
         if(InpAllowRefill) {
            shouldOpenBuy = (currentPrice > lastBuyPrice + dcaDistance);
         } else {
            shouldOpenBuy = (currentPrice > lastBuyPrice + dcaDistance) && (currentPrice > lastBuyPrice);
         }
      }
      
      if(shouldOpenBuy) {
         // 🔥 FIX: Tính lot mới CHÍNH XÁC theo hệ nhân/cộng
         double newLot = CalculateNextLot(g_lastBuyLot);
         
         if(newLot <= InpMaxLot) {
            if(OpenOrder(ORDER_TYPE_BUY, newLot, "DCA_BUY")) {
               g_lastBuyLot = newLot;  // ✅ Lưu lot mới
               g_buyDCACount++;
               
               // Lưu ticket để track hedge
               g_lastDCATicket = trade.ResultOrder();
               
               Print("✅ DCA BUY #", g_buyDCACount, " | Lot: ", newLot, " | Ticket: #", g_lastDCATicket);
               
               // 🆕 v2.23: Check và mở Hedge theo logic mới
               CheckAndOpenHedge(g_lastDCATicket, POSITION_TYPE_BUY);
            }
         }
      }
   }
   
   // ═══════════════════════════════════════════════════════════════
   // LOGIC DCA SELL
   // ═══════════════════════════════════════════════════════════════
   if(lastSellPrice > 0) {
      bool shouldOpenSell = false;
      
      if(g_currentMode == MODE_NEGATIVE) {
         // DCA ÂM: Giá TĂNG → Mở SELL thêm
         if(InpAllowRefill) {
            shouldOpenSell = (currentPrice > lastSellPrice + dcaDistance);
         } else {
            shouldOpenSell = (currentPrice > lastSellPrice + dcaDistance) && (currentPrice > lastSellPrice);
         }
      }
      else if(g_currentMode == MODE_POSITIVE) {
         // DCA DƯƠNG: Giá GIẢM → Mở SELL thêm
         if(InpAllowRefill) {
            shouldOpenSell = (currentPrice < lastSellPrice - dcaDistance);
         } else {
            shouldOpenSell = (currentPrice < lastSellPrice - dcaDistance) && (currentPrice < lastSellPrice);
         }
      }
      
      if(shouldOpenSell) {
         // 🔥 FIX: Tính lot mới CHÍNH XÁC theo hệ nhân/cộng
         double newLot = CalculateNextLot(g_lastSellLot);
         
         if(newLot <= InpMaxLot) {
            if(OpenOrder(ORDER_TYPE_SELL, newLot, "DCA_SELL")) {
               g_lastSellLot = newLot;  // ✅ Lưu lot mới
               g_sellDCACount++;
               
               // Lưu ticket để track hedge
               g_lastDCATicket = trade.ResultOrder();
               
               Print("✅ DCA SELL #", g_sellDCACount, " | Lot: ", newLot, " | Ticket: #", g_lastDCATicket);
               
               // 🆕 v2.23: Check và mở Hedge theo logic mới
               CheckAndOpenHedge(g_lastDCATicket, POSITION_TYPE_SELL);
            }
         }
      }
   }
}

double CalculateDCADistance() {
   if(InpDCATrigger == TRIGGER_ATR) {
      double atr[];
      ArraySetAsSeries(atr, true);
      
      if(CopyBuffer(g_atrHandle, 0, 0, 1, atr) > 0) {
         double atrValue = atr[0];
         double distance = atrValue * InpATRMultiplier;
         return distance / _Point;
      } else {
         return InpDCADistance * _Point;
      }
   } else {
      return InpDCADistance * _Point;
   }
}

void ManageOrdersMode2() {
   if(g_pairCount >= InpMaxPairs) {
      ClosePositiveOrders();
      g_currentMode = MODE_NEGATIVE;
      g_modeSwitched = true;
      Print("🔄 Chuyển Mode 2 → Mode 1");
      return;
   }
   
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double dcaDistance = CalculateDCADistance();
   
   // 🔥 FIX v2.24: Tìm giá CAO NHẤT và THẤP NHẤT của cặp hiện tại
   double highestPrice = 0;
   double lowestPrice = 999999;
   double lastPairPrice = 0;
   bool hasPairs = false;
   
   for(int i = 0; i < g_orderCount; i++) {
      if(!g_orders[i].isHedge && !g_orders[i].isHedgeLock && g_orders[i].pairIndex == g_pairCount) {
         hasPairs = true;
         double orderPrice = g_orders[i].openPrice;
         
         if(orderPrice > highestPrice) highestPrice = orderPrice;
         if(orderPrice < lowestPrice) lowestPrice = orderPrice;
         
         // Lưu giá 1 lệnh bất kỳ để làm reference
         if(lastPairPrice == 0) lastPairPrice = orderPrice;
      }
   }
   
   // 🔥 FIX v2.24: Kiểm tra điều kiện mở cặp mới
   bool shouldOpenNewPair = false;
   
   if(!hasPairs) {
      // Chưa có cặp nào → mở cặp đầu tiên
      shouldOpenNewPair = true;
   } else {
      // Đã có cặp → kiểm tra theo InpAllowRefill
      if(InpAllowRefill) {
         // Cho phép nhồi: mở nếu ĐỦ KHOẢNG CÁCH từ HIGH hoặc LOW
         shouldOpenNewPair = (currentPrice > highestPrice + dcaDistance) || 
                            (currentPrice < lowestPrice - dcaDistance);
      } else {
         // Không nhồi: phải VƯỢT QUA lệnh cuối
         bool aboveHigh = (currentPrice > highestPrice + dcaDistance) && (currentPrice > lastPairPrice);
         bool belowLow = (currentPrice < lowestPrice - dcaDistance) && (currentPrice < lastPairPrice);
         shouldOpenNewPair = aboveHigh || belowLow;
      }
   }
   
   if(!shouldOpenNewPair) {
      return;
   }
   
   // Mở cặp mới
   g_pairCount++;
   
   // 🔥 FIX v2.24: Tính lot với làm tròn 3 số thập phân
   double newLot;
   
   if(InpLotProgression == LOT_ADD) {
      newLot = InpInitialLot + (g_pairCount - 1) * InpAddValue * InpInitialLot;
   } else {
      newLot = InpInitialLot * MathPow(InpMultiplyValue, g_pairCount - 1);
   }
   
   newLot = NormalizeDouble(newLot, 3);  // 🔥 FIX: 3 số thập phân
   
   if(newLot <= InpMaxLot) {
      string buyComment = "PAIR_" + IntegerToString(g_pairCount) + "_BUY";
      string sellComment = "PAIR_" + IntegerToString(g_pairCount) + "_SELL";
      
      if(OpenOrder(ORDER_TYPE_BUY, newLot, buyComment) && 
         OpenOrder(ORDER_TYPE_SELL, newLot, sellComment)) {
         Print("════════════════════════════════════════");
         Print("✅ Mở cặp ", g_pairCount, " | Lot: ", newLot);
         Print("   Highest: ", highestPrice);
         Print("   Lowest: ", lowestPrice);
         Print("   Current: ", currentPrice);
         Print("   Allow Refill: ", InpAllowRefill ? "Yes" : "No");
         Print("════════════════════════════════════════");
      }
   }
}

void ClosePositiveOrders() {
   Print("💰 Đóng lệnh dương...");
   
   for(int i = g_orderCount - 1; i >= 0; i--) {
      if(g_orders[i].isHedgeLock) continue;
      
      if(PositionSelectByTicket(g_orders[i].ticket)) {
         double profit = PositionGetDouble(POSITION_PROFIT);
         if(profit > 0) {
            trade.PositionClose(g_orders[i].ticket);
         }
      }
   }
}

double CalculateNextLot(double currentLot) {
   double nextLot = 0;
   
   if(InpLotProgression == LOT_ADD) {
      nextLot = currentLot + (InpAddValue * InpInitialLot);
   } else {
      nextLot = currentLot * InpMultiplyValue;
   }
   
   // 🔥 FIX v2.24: Làm tròn 3 số thập phân để hệ nhân hoạt động chính xác
   nextLot = NormalizeDouble(nextLot, 3);
   
   if(nextLot > InpMaxLot) nextLot = InpMaxLot;
   if(nextLot < InpInitialLot) nextLot = InpInitialLot;
   
   return nextLot;
}

bool OpenOrder(ENUM_ORDER_TYPE orderType, double lots, string comment) {
   double price = 0;
   
   if(orderType == ORDER_TYPE_BUY) {
      price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   } else {
      price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   }
   
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   
   if(lots < minLot) lots = minLot;
   if(lots > maxLot) lots = maxLot;
   
   bool result = trade.PositionOpen(_Symbol, orderType, lots, price, 0, 0, comment);
   
   if(result) {
      Print("✅ Mở lệnh: ", comment, " | Lot: ", lots);
   }
   
   return result;
}

//+------------------------------------------------------------------+
//| 🆕 v2.23: Check và mở Hedge theo logic mới                       |
//| Logic: Sau lệnh thứ 10, mỗi lệnh DCA mới = 1 lệnh Hedge riêng  |
//| Định nghĩa "hồi về": Giá quay ngược về phía lệnh DCA cuối       |
//+------------------------------------------------------------------+
void CheckAndOpenHedge(ulong dcaTicket, int dcaType) {
   if(!InpEnableHedge) return;
   
   // Kiểm tra xem đã đủ số lệnh kích hoạt Hedge chưa
   int dcaCount = (dcaType == POSITION_TYPE_BUY) ? g_buyDCACount : g_sellDCACount;
   
   if(dcaCount < InpHedgeTrigger) {
      return;  // Chưa đủ số lệnh → không hedge
   }
   
   // ═══════════════════════════════════════════════════════════════
   // ĐÃ ĐỦ SỐ LỆNH → Kích hoạt Hedge mode (nếu chưa active)
   // ═══════════════════════════════════════════════════════════════
   
   if(!g_isHedgeActive) {
      g_isHedgeActive = true;
      g_hedgeDirection = (dcaType == POSITION_TYPE_BUY) ? POSITION_TYPE_SELL : POSITION_TYPE_BUY;
      
      Print("════════════════════════════════════════");
      Print("🛡️ HEDGE MODE ACTIVATED!");
      Print("   DCA Count: ", dcaCount);
      Print("   DCA Type: ", dcaType == POSITION_TYPE_BUY ? "BUY" : "SELL");
      Print("   Hedge Direction: ", g_hedgeDirection == POSITION_TYPE_BUY ? "BUY" : "SELL");
      Print("════════════════════════════════════════");
   }
   
   // ═══════════════════════════════════════════════════════════════
   // MỞ HEDGE CHO LỆNH DCA NÀY
   // ═══════════════════════════════════════════════════════════════
   
   // Kiểm tra xem lệnh DCA này đã có hedge chưa
   for(int i = 0; i < g_hedgeCount; i++) {
      if(g_hedgeList[i].dcaTicket == dcaTicket && g_hedgeList[i].isActive) {
         Print("⚠️ Lệnh DCA #", dcaTicket, " đã có hedge!");
         return;
      }
   }
   
   // Lấy thông tin lệnh DCA
   if(!PositionSelectByTicket(dcaTicket)) {
      Print("❌ Không tìm thấy lệnh DCA #", dcaTicket);
      return;
   }
   
   double dcaLot = PositionGetDouble(POSITION_VOLUME);
   double hedgeLot = dcaLot * InpHedgeRatio;
   hedgeLot = NormalizeDouble(hedgeLot, 2);
   
   // Kiểm tra lot hợp lệ
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(hedgeLot < minLot) {
      Print("⚠️ Hedge lot quá nhỏ: ", hedgeLot, " < ", minLot);
      return;
   }
   
   if(hedgeLot > InpMaxLot) {
      hedgeLot = InpMaxLot;
   }
   
   // Mở lệnh Hedge
   string hedgeComment = "HEDGE_" + IntegerToString(dcaCount) + "_" + 
                         (g_hedgeDirection == POSITION_TYPE_BUY ? "BUY" : "SELL");
   
   if(OpenOrder((ENUM_ORDER_TYPE)g_hedgeDirection, hedgeLot, hedgeComment)) {
      ulong hedgeTicket = trade.ResultOrder();
      
      // Lưu vào danh sách Hedge
      int size = ArraySize(g_hedgeList);
      ArrayResize(g_hedgeList, size + 1);
      
      g_hedgeList[size].dcaTicket = dcaTicket;
      g_hedgeList[size].hedgeTicket = hedgeTicket;
      g_hedgeList[size].isActive = true;
      
      g_hedgeCount++;
      
      Print("════════════════════════════════════════");
      Print("🛡️ HEDGE OPENED!");
      Print("   DCA Ticket: #", dcaTicket);
      Print("   DCA Lot: ", dcaLot);
      Print("   Hedge Ticket: #", hedgeTicket);
      Print("   Hedge Lot: ", hedgeLot, " (", InpHedgeRatio*100, "%)");
      Print("   Total Hedges: ", g_hedgeCount);
      Print("════════════════════════════════════════");
   }
}

bool CheckTotalTP() {
   double totalProfit = CalculateTotalProfit();
   
   if(totalProfit >= InpTotalTP) {
      Print("💰 TP tổng: $", totalProfit);
      return true;
   }
   
   return false;
}

bool CheckTotalSL() {
   double totalProfit = CalculateTotalProfit();
   
   if(totalProfit <= -InpTotalStopLoss) {
      Print("❌ SL tổng: $", totalProfit);
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| 🔥 FIX v2.24: Tính Drawdown THỰC (không phải profit)            |
//+------------------------------------------------------------------+
double CalculateMaxDrawdown() {
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   // Drawdown thực = Balance - Equity (số dương = đang lỗ)
   double drawdown = balance - equity;
   
   return drawdown;
}

//+------------------------------------------------------------------+
//| Tính tổng profit - GIỮ NGUYÊN                                   |
//+------------------------------------------------------------------+
double CalculateTotalProfit() {
   double totalProfit = 0;
   
   for(int i = 0; i < g_orderCount; i++) {
      if(PositionSelectByTicket(g_orders[i].ticket)) {
         totalProfit += PositionGetDouble(POSITION_PROFIT);
         totalProfit += PositionGetDouble(POSITION_SWAP);
      }
   }
   
   return totalProfit;
}

double CalculateRecoveryPercent() {
   if(g_firstOrderPrice == 0 || g_lastOrderPrice == 0) return 0;
   
   double priceRange = MathAbs(g_lastOrderPrice - g_firstOrderPrice);
   if(priceRange == 0) return 100;
   
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double currentDistance = MathAbs(currentPrice - g_firstOrderPrice);
   
   double recovery = (currentDistance / priceRange) * 100;
   if(recovery > 100) recovery = 100;
   
   return recovery;
}

void CloseAllOrders() {
   Print("🔴 Đóng tất cả lệnh...");
   
   for(int i = g_orderCount - 1; i >= 0; i--) {
      if(PositionSelectByTicket(g_orders[i].ticket)) {
         trade.PositionClose(g_orders[i].ticket);
      }
   }
   
   ArrayResize(g_orders, 0);
   g_orderCount = 0;
}

void ResetEA() {
   g_isHedgeActive = false;
   g_lastHedgePrice = 0;
   g_hedgeDirection = -1;
   g_highestProfit = 0;
   g_firstOrderPrice = 0;
   g_lastOrderPrice = 0;
   g_buyDCACount = 0;
   g_sellDCACount = 0;
   g_lastBuyLot = 0;
   g_lastSellLot = 0;
   g_pairCount = 0;
   g_modeSwitched = false;
   g_currentMode = InpDCAMode;
   
   // Reset Hedge Lock
   g_hedgeLockActive = false;
   g_hedgeLockTicket = 0;
   g_hedgeLockOpenPrice = 0;
   g_hedgeLockDirection = -1;
   g_hedgeLockLot = 0;
   
   // Reset Trailing Pro
   g_breakevenLevel = 0;
   g_breakevenActivated = false;
   g_currentTrailingLevel = 0;
   g_currentTrailingDistance = 0;
   g_lastProfitCheckTime = 0;
   g_lastProfitCheck = 0;
   g_recoveryBarsCount = 0;
   g_emergencyMode = false;
   
   // 🆕 v2.23: Reset Hedge mới
   ArrayResize(g_hedgeList, 0);
   g_hedgeCount = 0;
   g_lastDCATicket = 0;
   
   Print("🔄 EA reset hoàn tất");
}

bool CheckDailyTarget() {
   datetime currentTime = TimeCurrent();
   MqlDateTime dt1, dt2;
   TimeToStruct(currentTime, dt1);
   TimeToStruct(g_lastDayCheck, dt2);
   
   if(dt1.day != dt2.day) {
      g_dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      g_lastDayCheck = currentTime;
      Print("🌅 Ngày mới. Balance: $", g_dailyStartBalance);
   }
   
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double dailyProfit = currentBalance - g_dailyStartBalance;
   
   if(dailyProfit >= InpDailyTarget) {
      Print("🎯 Mục tiêu ngày: $", dailyProfit);
      return true;
   }
   
   return false;
}

void SendTelegramReport() {
   if(!InpEnableTelegram) return;
   if(InpTelegramToken == "" || InpTelegramChatID == "") return;
   
   datetime currentTime = TimeCurrent();
   if(currentTime - g_lastTelegramTime < InpTelegramInterval * 60) return;
   
   g_lastTelegramTime = currentTime;
   
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double profit = CalculateTotalProfit();
   double dailyProfit = balance - g_dailyStartBalance;
   
   int buyCount = 0, sellCount = 0;
   for(int i = 0; i < g_orderCount; i++) {
      if(g_orders[i].isHedgeLock) continue;
      if(g_orders[i].type == POSITION_TYPE_BUY) buyCount++;
      else sellCount++;
   }
   
   string message = "━━━━━━━━━━━━━━━━━━━━\n";
   message += "⚡ VANG EXNESS v2.23\n";
   message += "━━━━━━━━━━━━━━━━━━━━\n\n";
   
   message += "💰 Balance: $" + DoubleToString(balance, 2) + "\n";
   message += "📈 Equity: $" + DoubleToString(equity, 2) + "\n";
   message += "💵 Profit: $" + DoubleToString(profit, 2) + "\n";
   message += "📅 Daily: $" + DoubleToString(dailyProfit, 2) + "\n\n";
   
   message += "📊 Orders: " + IntegerToString(g_orderCount) + "\n";
   message += "🔵 Buy: " + IntegerToString(buyCount) + "\n";
   message += "🔴 Sell: " + IntegerToString(sellCount) + "\n\n";
   
   message += "⏰ " + TimeToString(currentTime, TIME_DATE|TIME_MINUTES);
   
   SendTelegramMessage(message);
}

void SendTelegramMessage(string message) {
   string encodedMessage = UrlEncodeUTF8(message);
   string url = "https://api.telegram.org/bot" + InpTelegramToken + "/sendMessage";
   string postData = "chat_id=" + InpTelegramChatID + "&text=" + encodedMessage;
   
   char data[];
   char result[];
   string headers = "Content-Type: application/x-www-form-urlencoded\r\n";
   
   ArrayResize(data, StringToCharArray(postData, data, 0, WHOLE_ARRAY) - 1);
   
   int res = WebRequest("POST", url, headers, 5000, data, result, headers);
   
   if(res == 200) {
      Print("✅ Telegram sent");
   }
}

string UrlEncodeUTF8(string str) {
   char utf8[];
   int len = StringToCharArray(str, utf8, 0, WHOLE_ARRAY, CP_UTF8);
   
   string result = "";
   
   for(int i = 0; i < len - 1; i++) {
      uchar ch = (uchar)utf8[i];
      
      if((ch >= 48 && ch <= 57) ||
         (ch >= 65 && ch <= 90) ||
         (ch >= 97 && ch <= 122) ||
         ch == 45 || ch == 46 || ch == 95 || ch == 126) {
         result += CharToString(ch);
      }
      else if(ch == 32) {
         result += "+";
      }
      else if(ch == 10) {
         result += "%0A";
      }
      else {
         result += StringFormat("%%%02X", ch);
      }
   }
   
   return result;
}

//+------------------------------------------------------------------+
//| TẠO PANEL UI - v2.22 FINAL                                       |
//+------------------------------------------------------------------+
void CreatePanel() {
   int x = InpPanelX;
   int y = InpPanelY;
   int width = 320;
   int height = 740;
   
   // Background
   CreateLabel(g_panelPrefix + "BG", x, y, width, height, "", InpPanelColor, clrWhite);
   
   // Title
   CreateText(g_panelPrefix + "Title", x + 10, y + 10, "⚡ VANG EXNESS v2.23", clrYellow, 12, true);
   
   // Balance Section
   CreateText(g_panelPrefix + "BalanceLabel", x + 10, y + 40, "💰 Balance:", clrWhite, 10, false);
   CreateText(g_panelPrefix + "BalanceValue", x + 110, y + 40, "", clrLime, 10, true);
   
   CreateText(g_panelPrefix + "EquityLabel", x + 10, y + 60, "📈 Equity:", clrWhite, 10, false);
   CreateText(g_panelPrefix + "EquityValue", x + 110, y + 60, "", clrLime, 10, true);
   
   CreateText(g_panelPrefix + "ProfitLabel", x + 10, y + 80, "💵 Profit:", clrWhite, 10, false);
   CreateText(g_panelPrefix + "ProfitValue", x + 110, y + 80, "", clrLime, 10, true);
   
   CreateText(g_panelPrefix + "DailyLabel", x + 10, y + 100, "📅 Daily:", clrWhite, 10, false);
   CreateText(g_panelPrefix + "DailyValue", x + 110, y + 100, "", clrLime, 10, true);
   
   // Separator
   CreateRectangle(g_panelPrefix + "Sep1", x + 10, y + 125, 300, 1, clrGray);
   
   // Orders Section
   CreateText(g_panelPrefix + "OrdersLabel", x + 10, y + 135, "📊 LỆNH ĐANG MỞ", clrWhite, 10, true);
   CreateText(g_panelPrefix + "BuyLabel", x + 10, y + 155, "🔵 Buy:", clrDodgerBlue, 10, false);
   CreateText(g_panelPrefix + "BuyValue", x + 80, y + 155, "", clrWhite, 10, false);
   CreateText(g_panelPrefix + "SellLabel", x + 10, y + 175, "🔴 Sell:", clrRed, 10, false);
   CreateText(g_panelPrefix + "SellValue", x + 80, y + 175, "", clrWhite, 10, false);
   
   // Separator
   CreateRectangle(g_panelPrefix + "Sep2", x + 10, y + 200, 300, 1, clrGray);
   
   // Trend Warning
   CreateText(g_panelPrefix + "TrendLabel", x + 10, y + 210, "🚨 XU HƯỚNG", clrWhite, 10, true);
   CreateText(g_panelPrefix + "TrendStatus", x + 10, y + 230, "🟢 Bình thường", clrLime, 9, false);
   
   // Separator
   CreateRectangle(g_panelPrefix + "Sep3", x + 10, y + 255, 300, 1, clrGray);
   
   // Status Section
   CreateText(g_panelPrefix + "StatusLabel", x + 10, y + 265, "🎯 TRẠNG THÁI", clrWhite, 10, true);
   CreateText(g_panelPrefix + "ModeLabel", x + 10, y + 285, "Mode:", clrWhite, 9, false);
   CreateText(g_panelPrefix + "ModeValue", x + 80, y + 285, "", clrCyan, 9, false);
   CreateText(g_panelPrefix + "HedgeLabel", x + 10, y + 305, "Hedge DCA:", clrWhite, 9, false);
   CreateText(g_panelPrefix + "HedgeValue", x + 100, y + 305, "OFF", clrGray, 9, false);
   CreateText(g_panelPrefix + "LockLabel", x + 10, y + 325, "Hedge Lock:", clrWhite, 9, false);
   CreateText(g_panelPrefix + "LockValue", x + 100, y + 325, "⚪ OFF", clrGray, 9, false);
   
   // 🆕 Trailing Level
   CreateText(g_panelPrefix + "TrailingLabel", x + 10, y + 345, "🎯 Trailing:", clrWhite, 9, false);
   CreateText(g_panelPrefix + "TrailingValue", x + 100, y + 345, "Level 0", clrAqua, 9, false);
   
   // Separator
   CreateRectangle(g_panelPrefix + "Sep4", x + 10, y + 370, 300, 1, clrGray);
   
   // Price Scale
   CreateText(g_panelPrefix + "ScaleLabel", x + 10, y + 380, "📏 THANG ĐO GIÁ", clrWhite, 10, true);
   CreateText(g_panelPrefix + "FirstLabel", x + 10, y + 400, "Đầu:", clrWhite, 9, false);
   CreateText(g_panelPrefix + "FirstValue", x + 70, y + 400, "", clrCyan, 9, false);
   CreateText(g_panelPrefix + "LastLabel", x + 10, y + 420, "Cuối:", clrWhite, 9, false);
   CreateText(g_panelPrefix + "LastValue", x + 70, y + 420, "", clrCyan, 9, false);
   CreateText(g_panelPrefix + "CurrentLabel", x + 10, y + 440, "Hiện:", clrWhite, 9, false);
   CreateText(g_panelPrefix + "CurrentValue", x + 70, y + 440, "", clrYellow, 9, true);
   CreateText(g_panelPrefix + "ArrowLabel", x + 10, y + 460, "Hướng:", clrWhite, 9, false);
   CreateText(g_panelPrefix + "ArrowValue", x + 90, y + 460, "", clrYellow, 12, false);
   
   // Separator
   CreateRectangle(g_panelPrefix + "Sep5", x + 10, y + 485, 300, 1, clrGray);
   
   // Recovery Bar
   CreateText(g_panelPrefix + "RecoveryLabel", x + 10, y + 495, "🔄 HỒI GIÁ", clrWhite, 10, true);
   CreateRectangle(g_panelPrefix + "RecoveryBG", x + 10, y + 515, 300, 20, clrDarkGray);
   CreateRectangle(g_panelPrefix + "RecoveryBar", x + 10, y + 515, 0, 20, clrLime);
   CreateText(g_panelPrefix + "RecoveryPercent", x + 150, y + 518, "0%", clrWhite, 9, false);
   
   // Separator
   CreateRectangle(g_panelPrefix + "Sep6", x + 10, y + 545, 300, 1, clrGray);
   
   // 🆕 Countdown Timer
   CreateText(g_panelPrefix + "CountdownLabel", x + 10, y + 555, "⏰ NẾN ĐÓNG TRONG", clrWhite, 10, true);
   CreateText(g_panelPrefix + "CountdownValue", x + 110, y + 580, "00:00", clrYellow, 16, true);
   
   // Separator
   CreateRectangle(g_panelPrefix + "Sep7", x + 10, y + 610, 300, 1, clrGray);
   
   // Control Buttons
   CreateText(g_panelPrefix + "ButtonsLabel", x + 10, y + 620, "🎮 ĐIỀU KHIỂN", clrWhite, 10, true);
   
   CreateButton(g_panelPrefix + "BtnCloseAll", x + 10, y + 640, 95, 30, "Close All", clrDarkRed, clrWhite);
   CreateButton(g_panelPrefix + "BtnCloseBuy", x + 110, y + 640, 95, 30, "Close Buy", clrDodgerBlue, clrWhite);
   CreateButton(g_panelPrefix + "BtnCloseSell", x + 210, y + 640, 95, 30, "Close Sell", clrRed, clrWhite);
   
   CreateButton(g_panelPrefix + "BtnTrim", x + 10, y + 675, 145, 30, "✂️ Trim", clrOrange, clrWhite);
   CreateButton(g_panelPrefix + "BtnForceLock", x + 160, y + 675, 145, 30, "🔒 Lock", clrPurple, clrWhite);
   
   CreateButton(g_panelPrefix + "BtnForceUnlock", x + 10, y + 710, 295, 30, "🔓 Unlock", clrGreen, clrWhite);
   
   ChartRedraw();
}

void UpdatePanel() {
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double profit = CalculateTotalProfit();
   double dailyProfit = balance - g_dailyStartBalance;
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double recovery = CalculateRecoveryPercent();
   
   int buyCount = 0, sellCount = 0;
   for(int i = 0; i < g_orderCount; i++) {
      if(g_orders[i].isHedgeLock) continue;
      if(g_orders[i].type == POSITION_TYPE_BUY) buyCount++;
      else sellCount++;
   }
   
   ObjectSetString(0, g_panelPrefix + "BalanceValue", OBJPROP_TEXT, "$" + DoubleToString(balance, 2));
   ObjectSetString(0, g_panelPrefix + "EquityValue", OBJPROP_TEXT, "$" + DoubleToString(equity, 2));
   
   color profitColor = (profit >= 0) ? clrLime : clrRed;
   ObjectSetString(0, g_panelPrefix + "ProfitValue", OBJPROP_TEXT, "$" + DoubleToString(profit, 2));
   ObjectSetInteger(0, g_panelPrefix + "ProfitValue", OBJPROP_COLOR, profitColor);
   
   color dailyColor = (dailyProfit >= 0) ? clrLime : clrRed;
   ObjectSetString(0, g_panelPrefix + "DailyValue", OBJPROP_TEXT, "$" + DoubleToString(dailyProfit, 2));
   ObjectSetInteger(0, g_panelPrefix + "DailyValue", OBJPROP_COLOR, dailyColor);
   
   ObjectSetString(0, g_panelPrefix + "BuyValue", OBJPROP_TEXT, IntegerToString(buyCount));
   ObjectSetString(0, g_panelPrefix + "SellValue", OBJPROP_TEXT, IntegerToString(sellCount));
   
   // Trend
   string trendText = "";
   color trendColor = clrLime;
   switch(g_trendLevel) {
      case TREND_NORMAL:
         trendText = "🟢 Bình thường";
         trendColor = clrLime;
         break;
      case TREND_WARNING:
         trendText = "🟡 Cảnh báo";
         trendColor = clrYellow;
         break;
      case TREND_DANGER:
         trendText = "🔴 Nguy hiểm";
         trendColor = clrOrange;
         break;
      case TREND_CRITICAL:
         trendText = "⛔ Cực nguy hiểm";
         trendColor = clrRed;
         break;
   }
   ObjectSetString(0, g_panelPrefix + "TrendStatus", OBJPROP_TEXT, trendText);
   ObjectSetInteger(0, g_panelPrefix + "TrendStatus", OBJPROP_COLOR, trendColor);
   
   // Mode
   string modeText = "";
   if(g_currentMode == MODE_NEGATIVE) {
      modeText = "DCA Âm";
   } else if(g_currentMode == MODE_POSITIVE) {
      modeText = "DCA Dương";
   } else {
      modeText = "DCA Cặp";
   }
   if(g_modeSwitched) modeText += " (Chuyển)";
   ObjectSetString(0, g_panelPrefix + "ModeValue", OBJPROP_TEXT, modeText);
   
   // Hedge DCA
   if(g_isHedgeActive) {
      ObjectSetString(0, g_panelPrefix + "HedgeValue", OBJPROP_TEXT, "🟢 ACTIVE");
      ObjectSetInteger(0, g_panelPrefix + "HedgeValue", OBJPROP_COLOR, clrLime);
   } else {
      ObjectSetString(0, g_panelPrefix + "HedgeValue", OBJPROP_TEXT, "⚪ OFF");
      ObjectSetInteger(0, g_panelPrefix + "HedgeValue", OBJPROP_COLOR, clrGray);
   }
   
   // Hedge Lock
   if(g_hedgeLockActive) {
      ObjectSetString(0, g_panelPrefix + "LockValue", OBJPROP_TEXT, "🔒 LOCKED");
      ObjectSetInteger(0, g_panelPrefix + "LockValue", OBJPROP_COLOR, clrOrange);
   } else {
      ObjectSetString(0, g_panelPrefix + "LockValue", OBJPROP_TEXT, "⚪ OFF");
      ObjectSetInteger(0, g_panelPrefix + "LockValue", OBJPROP_COLOR, clrGray);
   }
   
   // 🆕 Trailing Level
   if(g_breakevenActivated) {
      string trailingText = "Level " + IntegerToString(g_currentTrailingLevel);
      ObjectSetString(0, g_panelPrefix + "TrailingValue", OBJPROP_TEXT, trailingText);
   } else {
      ObjectSetString(0, g_panelPrefix + "TrailingValue", OBJPROP_TEXT, "Waiting");
   }
   
   // Price
   ObjectSetString(0, g_panelPrefix + "FirstValue", OBJPROP_TEXT, DoubleToString(g_firstOrderPrice, _Digits));
   ObjectSetString(0, g_panelPrefix + "LastValue", OBJPROP_TEXT, DoubleToString(g_lastOrderPrice, _Digits));
   ObjectSetString(0, g_panelPrefix + "CurrentValue", OBJPROP_TEXT, DoubleToString(currentPrice, _Digits));
   
   // Arrow
   string arrow = "→";
   color arrowColor = clrYellow;
   if(g_firstOrderPrice > 0 && g_lastOrderPrice > 0) {
      if(currentPrice > g_lastOrderPrice) {
         arrow = "↑";
         arrowColor = clrLime;
      } else if(currentPrice < g_lastOrderPrice) {
         arrow = "↓";
         arrowColor = clrRed;
      }
   }
   ObjectSetString(0, g_panelPrefix + "ArrowValue", OBJPROP_TEXT, arrow);
   ObjectSetInteger(0, g_panelPrefix + "ArrowValue", OBJPROP_COLOR, arrowColor);
   
   // Recovery
   if(recovery > 0) {
      int barWidth = (int)(300 * recovery / 100);
      ObjectSetInteger(0, g_panelPrefix + "RecoveryBar", OBJPROP_XSIZE, barWidth);
      
      color barColor = clrRed;
      if(recovery > 80) barColor = clrLime;
      else if(recovery > 40) barColor = clrYellow;
      
      ObjectSetInteger(0, g_panelPrefix + "RecoveryBar", OBJPROP_BGCOLOR, barColor);
      ObjectSetString(0, g_panelPrefix + "RecoveryPercent", OBJPROP_TEXT, DoubleToString(recovery, 1) + "%");
   } else {
      ObjectSetInteger(0, g_panelPrefix + "RecoveryBar", OBJPROP_XSIZE, 0);
      ObjectSetString(0, g_panelPrefix + "RecoveryPercent", OBJPROP_TEXT, "0%");
   }
   
   // 🆕 Countdown
   string countdown = GetBarCloseCountdown();
   ObjectSetString(0, g_panelPrefix + "CountdownValue", OBJPROP_TEXT, countdown);
   
   ChartRedraw();
}

void CreateLabel(string name, int x, int y, int width, int height, string text, color bgColor, color txtColor) {
   ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgColor);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

void CreateText(string name, int x, int y, string text, color txtColor, int fontSize, bool bold) {
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, txtColor);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, name, OBJPROP_FONT, bold ? "Arial Bold" : "Arial");
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

void CreateRectangle(string name, int x, int y, int width, int height, color fillColor) {
   ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, fillColor);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

void CreateButton(string name, int x, int y, int width, int height, string text, color bgColor, color txtColor) {
   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgColor);
   ObjectSetInteger(0, name, OBJPROP_COLOR, txtColor);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

void DeletePanel() {
   ObjectsDeleteAll(0, g_panelPrefix);
   ChartRedraw();
}

//+------------------------------------------------------------------+
