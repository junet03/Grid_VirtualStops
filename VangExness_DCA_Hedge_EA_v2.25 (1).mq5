//+------------------------------------------------------------------+
//|                      VangExness_DCA_Hedge_EA_v2.25.mq5           |
//|                                  Copyright 2024, Mr JuNet        |
//|   🔥 v2.25: FIX 3 LỖI NGHIÊM TRỌNG - AN TOÀN TỐI ĐA            |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Mr JuNet"
#property link      ""
#property version   "2.25"
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
   LOT_MULTIPLY      // Hệ nhân (0.01, 0.02, 0.03... với làm tròn Exness)
};

// Chế độ DCA
enum ENUM_DCA_MODE {
   MODE_NEGATIVE,    // DCA âm: Chỉ mở lệnh theo hướng thua lỗ
   MODE_POSITIVE,    // DCA dương: Mở lệnh theo hướng thắng (theo trend)
   MODE_PAIRS        // DCA cặp: Mở đồng thời Buy+Sell theo hướng động
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

// 🆕 v2.25: Hướng DCA Cặp
enum ENUM_PAIR_DIRECTION {
   PAIR_DIR_NONE,    // Chưa xác định
   PAIR_DIR_UP,      // Hướng lên
   PAIR_DIR_DOWN     // Hướng xuống
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
input double InpDCADistance = 1000;                     // Khoảng cách DCA (points)
input bool InpAllowRefill = false;                      // Cho phép nhồi lệnh khi giá hồi về
input int InpMaxPairs = 10;                             // Số cặp tối đa (chỉ cho DCA cặp)

//--- DCA Trigger
input group "===== DCA TRIGGER MODE ====="
input ENUM_DCA_TRIGGER InpDCATrigger = TRIGGER_STEP;    // Chế độ kích hoạt DCA
input int InpATRPeriod = 14;                            // ATR Period (cho TRIGGER_ATR)
input double InpATRMultiplier = 1.5;                    // ATR Multiplier (khoảng cách = ATR * multiplier)

//--- Quản lý rủi ro
input group "===== QUẢN LÝ RỦI RO ====="
input double InpMaxLot = 10.0;                          // Lot tối đa cho 1 lệnh
input int InpMaxOrders = 50;                            // Tổng số lệnh tối đa
input double InpTotalStopLoss = 5000;                   // Cắt lỗ tổng (USD) - 0 = tắt

//--- Chốt lời
input group "===== CHỐT LỜI ====="
input double InpTotalTP = 100.0;                        // TP tổng (USD) cho DCA Cặp
input bool InpEnableTrailing = false;                   // Bật Trailing TP

//--- 🆕 v2.25: Hedge Lock với SL cố định
input group "===== HEDGE LOCK V2.25 - KHÓA MDD ====="
input bool InpEnableHedgeLock = true;                   // Bật Hedge Lock
input double InpHedgeLockMDD = 1500;                    // MDD kích hoạt Hedge Lock (cent)
input double InpHedgeLockRatio = 1.0;                   // Tỷ lệ Hedge Lock (1.0 = 100% imbalance)
input int InpHedgeLockSL = 1000;                        // SL cố định (points) - KHÔNG trailing

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
input group "===== BẢNG ĐIỀU KHIỂN (Panel v2.25) ====="
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
   bool isHedgeLock;   // Đánh dấu lệnh Hedge Lock
   int pairIndex;      // Chỉ số cặp (dùng cho Mode 2)
};

OrderInfo g_orders[];           // Mảng lưu thông tin lệnh
int g_orderCount = 0;           // Tổng số lệnh

// 🆕 v2.25: Trạng thái DCA Cặp mới
ENUM_DCA_MODE g_currentMode = MODE_NEGATIVE;
int g_pairCount = 0;
ENUM_PAIR_DIRECTION g_pairDirection = PAIR_DIR_NONE;   // Hướng hiện tại
double g_pair1Price = 0;                                 // Giá cặp 1 (để check đổi hướng)
double g_lastPairPrice = 0;                              // Giá cặp cuối (để check distance)

// Theo dõi DCA progression
double g_lastBuyLot = 0;
double g_lastSellLot = 0;
int g_buyDCACount = 0;
int g_sellDCACount = 0;

// 🆕 v2.25: Hedge Lock mới - Đơn giản với SL cố định
bool g_hedgeLockActive = false;
ulong g_hedgeLockTicket = 0;
double g_hedgeLockOpenPrice = 0;
int g_hedgeLockDirection = -1;  // 0=BUY, 1=SELL
double g_hedgeLockLot = 0;
double g_hedgeLockSL = 0;       // Giá SL

// Trailing TP
double g_highestProfit = 0;

// Theo dõi profit khác
double g_dailyStartBalance = 0;
datetime g_lastDayCheck = 0;

// Trend Warning
ENUM_TREND_LEVEL g_trendLevel = TREND_NORMAL;
datetime g_lastTrendCheck = 0;

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

//+------------------------------------------------------------------+
//| 🔥 FIX 1: Hàm làm tròn lot theo Exness (step = 0.01)            |
//+------------------------------------------------------------------+
double RoundLotExness(double lot) {
   double lotStep = 0.01;
   double rounded = MathRound(lot / lotStep) * lotStep;
   
   // Đảm bảo không nhỏ hơn lot tối thiểu
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(rounded < minLot) rounded = minLot;
   
   // Đảm bảo không lớn hơn lot tối đa
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(rounded > maxLot) rounded = maxLot;
   
   return NormalizeDouble(rounded, 2);
}

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
   Print("⚡ EA VangExness DCA Hedge v2.25 - 3 CRITICAL FIXES ⚡");
   Print("════════════════════════════════════════════════════════");
   Print("Symbol: ", _Symbol);
   Print("Timeframe: ", EnumToString(InpTimeframe));
   Print("DCA Mode: ", g_currentMode == MODE_NEGATIVE ? "DCA Âm" : 
                       g_currentMode == MODE_POSITIVE ? "DCA Dương" : "DCA Cặp");
   Print("Lot Progression: ", InpLotProgression == LOT_ADD ? "Hệ Cộng" : "Hệ Nhân");
   Print("DCA Trigger: ", InpDCATrigger == TRIGGER_BAR_CLOSE ? "Nến đóng" : 
                          InpDCATrigger == TRIGGER_STEP ? "Step cố định" : "ATR động");
   Print("════════════════════════════════════════════════════════");
   Print("🔥 v2.25 - 3 CRITICAL FIXES:");
   Print("   ✅ FIX 1: Lot làm tròn Exness (step 0.01)");
   Print("   ✅ FIX 2: DCA Cặp theo hướng động, lot tăng liên tục");
   Print("   ✅ FIX 3: Hedge Lock SL cố định ", InpHedgeLockSL, " points");
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
   
   // 3. 🆕 v2.25: Quản lý Hedge Lock (độc lập, ưu tiên cao nhất)
   if(InpEnableHedgeLock) {
      ManageHedgeLock();
   }
   
   // 4. Kiểm tra và cảnh báo xu hướng
   if(InpEnableTrendWarning) {
      CheckTrendWarning();
   }
   
   // 5. Kiểm tra TP tổng
   if(CheckTotalTP()) {
      CloseAllOrders();
      ResetEA();
      return;
   }
   
   // 6. Kiểm tra SL tổng
   if(InpTotalStopLoss > 0 && CheckTotalSL()) {
      CloseAllOrders();
      ResetEA();
      Print("❌ SL tổng chạm! Đóng tất cả lệnh.");
      return;
   }
   
   // 7. Logic mở lệnh theo DCA Trigger
   ManageOrdersByTrigger();
   
   // 8. Cập nhật Panel
   if(InpShowPanel) {
      UpdatePanel();
   }
   
   // 9. Gửi Telegram report
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
//| 🔥 FIX 3: HEDGE LOCK V2.25 - Đơn giản với SL cố định            |
//+------------------------------------------------------------------+
void ManageHedgeLock() {
   // ═══════════════════════════════════════════════════════════════
   // BƯỚC 1: TÍNH MDD THỰC (Balance - Equity)
   // ═══════════════════════════════════════════════════════════════
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double mdd = balance - equity;  // Drawdown thực (số dương = đang lỗ)
   
   // ═══════════════════════════════════════════════════════════════
   // BƯỚC 2: KÍCH HOẠT HEDGE LOCK khi MDD >= threshold
   // ═══════════════════════════════════════════════════════════════
   if(!g_hedgeLockActive && mdd >= InpHedgeLockMDD) {
      
      // Tính imbalance
      double totalBuyLot = 0;
      double totalSellLot = 0;
      
      for(int i = 0; i < g_orderCount; i++) {
         if(g_orders[i].isHedgeLock) continue;  // Bỏ qua hedge lock cũ
         
         if(g_orders[i].type == POSITION_TYPE_BUY) {
            totalBuyLot += g_orders[i].lots;
         } else {
            totalSellLot += g_orders[i].lots;
         }
      }
      
      double imbalance = totalBuyLot - totalSellLot;
      
      // Chỉ mở nếu có imbalance đáng kể
      if(MathAbs(imbalance) < 0.01) {
         return;
      }
      
      // Xác định hướng hedge (ngược với imbalance)
      if(imbalance > 0) {
         g_hedgeLockDirection = POSITION_TYPE_SELL;  // Nhiều Buy → Hedge Sell
      } else {
         g_hedgeLockDirection = POSITION_TYPE_BUY;   // Nhiều Sell → Hedge Buy
      }
      
      // Tính lot hedge
      g_hedgeLockLot = MathAbs(imbalance) * InpHedgeLockRatio;
      g_hedgeLockLot = RoundLotExness(g_hedgeLockLot);
      
      // Kiểm tra lot tối thiểu
      double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      if(g_hedgeLockLot < minLot) {
         Print("⚠️ Hedge Lock lot quá nhỏ: ", g_hedgeLockLot);
         return;
      }
      
      // Mở Hedge Lock với SL
      if(OpenHedgeLockWithSL()) {
         g_hedgeLockActive = true;
         
         Print("════════════════════════════════════════════════════════");
         Print("🔒 HEDGE LOCK ACTIVATED!");
         Print("   MDD: ", DoubleToString(mdd, 2), " cent (threshold: ", InpHedgeLockMDD, ")");
         Print("   Imbalance: ", DoubleToString(imbalance, 2));
         Print("   Lock: ", g_hedgeLockDirection == POSITION_TYPE_BUY ? "BUY" : "SELL", 
               " ", g_hedgeLockLot, " lot");
         Print("   Open Price: ", DoubleToString(g_hedgeLockOpenPrice, _Digits));
         Print("   SL Price: ", DoubleToString(g_hedgeLockSL, _Digits));
         Print("   SL Distance: ", InpHedgeLockSL, " points");
         Print("════════════════════════════════════════════════════════");
         
         // Gửi Telegram
         if(InpEnableTelegram) {
            string msg = "🔒 HEDGE LOCK ACTIVATED!\n\n";
            msg += "MDD: " + DoubleToString(mdd, 2) + " cent\n";
            msg += "Lock: " + DoubleToString(g_hedgeLockLot, 2) + " lot\n";
            msg += "SL: " + IntegerToString(InpHedgeLockSL) + " points";
            SendTelegramMessage(msg);
         }
      }
   }
   
   // ═══════════════════════════════════════════════════════════════
   // BƯỚC 3: KIỂM TRA LỆNH HEDGE LOCK (tự động đóng bởi SL)
   // ═══════════════════════════════════════════════════════════════
   if(g_hedgeLockActive && g_hedgeLockTicket > 0) {
      
      // Kiểm tra lệnh còn tồn tại không
      if(!PositionSelectByTicket(g_hedgeLockTicket)) {
         // Lệnh đã bị đóng (chạm SL hoặc TP)
         Print("════════════════════════════════════════════════════════");
         Print("✅ HEDGE LOCK CLOSED (SL triggered)");
         Print("   Ticket: #", g_hedgeLockTicket);
         Print("   MDD đã được giới hạn!");
         Print("════════════════════════════════════════════════════════");
         
         // Reset trạng thái
         g_hedgeLockActive = false;
         g_hedgeLockTicket = 0;
         g_hedgeLockOpenPrice = 0;
         g_hedgeLockDirection = -1;
         g_hedgeLockLot = 0;
         g_hedgeLockSL = 0;
         
         // Gửi Telegram
         if(InpEnableTelegram) {
            SendTelegramMessage("✅ Hedge Lock đã đóng (SL triggered)");
         }
      } else {
         // Lệnh vẫn đang mở - Log thông tin
         static datetime lastLogTime = 0;
         if(TimeCurrent() - lastLogTime >= 30) {
            lastLogTime = TimeCurrent();
            
            double lockProfit = PositionGetDouble(POSITION_PROFIT);
            double currentPrice = g_hedgeLockDirection == POSITION_TYPE_BUY ? 
                                 SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                                 SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            
            double distanceToSL = MathAbs(currentPrice - g_hedgeLockSL) / _Point;
            
            Print("🔒 Hedge Lock Active:");
            Print("   Profit: $", DoubleToString(lockProfit, 2));
            Print("   Current: ", DoubleToString(currentPrice, _Digits));
            Print("   SL: ", DoubleToString(g_hedgeLockSL, _Digits));
            Print("   Distance to SL: ", DoubleToString(distanceToSL, 0), " points");
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Mở Hedge Lock với SL cố định                                     |
//+------------------------------------------------------------------+
bool OpenHedgeLockWithSL() {
   double price = 0;
   double sl = 0;
   
   if(g_hedgeLockDirection == POSITION_TYPE_BUY) {
      price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      // SL phía dưới cho BUY
      sl = price - (InpHedgeLockSL * _Point);
   } else {
      price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      // SL phía trên cho SELL
      sl = price + (InpHedgeLockSL * _Point);
   }
   
   sl = NormalizeDouble(sl, _Digits);
   
   string comment = "HEDGE_LOCK";
   
   bool result = trade.PositionOpen(_Symbol, 
                                    (ENUM_ORDER_TYPE)g_hedgeLockDirection, 
                                    g_hedgeLockLot, 
                                    price, 
                                    sl,    // SL cố định
                                    0,     // Không TP
                                    comment);
   
   if(result) {
      g_hedgeLockTicket = trade.ResultOrder();
      g_hedgeLockOpenPrice = price;
      g_hedgeLockSL = sl;
      return true;
   } else {
      Print("❌ Lỗi mở Hedge Lock: ", GetLastError());
      return false;
   }
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
      Print("⚠️ Không có imbalance đáng kể!");
      return;
   }
   
   if(imbalance > 0) {
      g_hedgeLockDirection = POSITION_TYPE_SELL;
   } else {
      g_hedgeLockDirection = POSITION_TYPE_BUY;
   }
   
   g_hedgeLockLot = MathAbs(imbalance) * InpHedgeLockRatio;
   g_hedgeLockLot = RoundLotExness(g_hedgeLockLot);
   
   if(OpenHedgeLockWithSL()) {
      g_hedgeLockActive = true;
      Print("✅ Force Hedge Lock thành công!");
   }
}

void ForceUnlockHedge() {
   if(!g_hedgeLockActive || g_hedgeLockTicket == 0) {
      Print("⚠️ Không có Hedge Lock active!");
      return;
   }
   
   Print("🔓 [MANUAL] Force Unlock...");
   
   if(PositionSelectByTicket(g_hedgeLockTicket)) {
      if(trade.PositionClose(g_hedgeLockTicket)) {
         Print("✅ Đã đóng Hedge Lock thủ công");
         g_hedgeLockActive = false;
         g_hedgeLockTicket = 0;
         g_hedgeLockOpenPrice = 0;
         g_hedgeLockDirection = -1;
         g_hedgeLockLot = 0;
         g_hedgeLockSL = 0;
      } else {
         Print("❌ Lỗi đóng Hedge Lock: ", GetLastError());
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
   
   double profit = CalculateTotalProfit();
   double mdd = -profit;  // MDD là số dương
   int orderCount = g_orderCount;
   
   ENUM_TREND_LEVEL oldLevel = g_trendLevel;
   g_trendLevel = TREND_NORMAL;
   
   if(orderCount > 60 || mdd > 2000) {
      g_trendLevel = TREND_CRITICAL;
   }
   else if(orderCount > 40 || mdd > InpTrendWarningMDD) {
      g_trendLevel = TREND_DANGER;
   }
   else if(orderCount > InpTrendWarningOrders || mdd > (InpTrendWarningMDD/2)) {
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
      Print("════════════════════════════════════════");
   }
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
   ResetEA();
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
      g_orders[size].isHedgeLock = (StringFind(comment, "HEDGE_LOCK") >= 0);
      
      g_orders[size].pairIndex = 0;
      if(StringFind(comment, "PAIR") >= 0) {
         string parts[];
         StringSplit(comment, '_', parts);
         if(ArraySize(parts) >= 2) {
            g_orders[size].pairIndex = (int)StringToInteger(parts[1]);
         }
      }
      
      // 🔥 FIX v2.25: Tìm lot LỚN NHẤT để tính progression đúng
      if(!g_orders[size].isHedgeLock) {
         if(g_orders[size].type == POSITION_TYPE_BUY) {
            if(g_orders[size].lots > g_lastBuyLot) {
               g_lastBuyLot = g_orders[size].lots;
            }
            g_buyDCACount++;
         } else {
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
      if(!g_orders[i].isHedgeLock) {
         g_lastOrderPrice = g_orders[i].openPrice;
         break;
      }
   }
}

void UpdatePairCount() {
   if(g_currentMode != MODE_PAIRS) return;
   
   g_pairCount = 0;
   for(int i = 0; i < g_orderCount; i++) {
      if(!g_orders[i].isHedgeLock && g_orders[i].pairIndex > g_pairCount) {
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
      ManageOrdersMode2_v25();  // 🔥 FIX 2: Logic mới
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
      
      // Lưu giá cặp 1 để check đổi hướng sau
      double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      g_pair1Price = currentPrice;
      g_lastPairPrice = currentPrice;
      g_pairDirection = PAIR_DIR_NONE;  // Chưa xác định hướng
      
      Print("   Cặp 1 @ ", DoubleToString(g_pair1Price, _Digits), " | Hướng: Chưa xác định");
   } else {
      OpenOrder(ORDER_TYPE_BUY, InpInitialLot, "INITIAL_BUY");
      OpenOrder(ORDER_TYPE_SELL, InpInitialLot, "INITIAL_SELL");
   }
}

//+------------------------------------------------------------------+
//| 🔥 FIX 2: DCA CẶP V2.25 - Theo hướng động, lot tăng liên tục    |
//+------------------------------------------------------------------+
void ManageOrdersMode2_v25() {
   // Kiểm tra số cặp tối đa
   if(g_pairCount >= InpMaxPairs) {
      // Đạt max cặp → Check TP 1 chiều
      if(CheckOneSidedProfit()) {
         CloseAllOrders();
         ResetEA();
         Print("💰 TP 1 chiều đạt! Đóng tất cả.");
      }
      return;
   }
   
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double dcaDistance = CalculateDCADistance();
   
   // ═══════════════════════════════════════════════════════════════
   // TRƯỜNG HỢP 1: Chưa có hướng (sau cặp 1)
   // ═══════════════════════════════════════════════════════════════
   if(g_pairDirection == PAIR_DIR_NONE && g_pairCount == 1) {
      
      bool shouldOpenPair2 = false;
      
      // Check giá đi lên
      if(currentPrice >= g_pair1Price + dcaDistance) {
         g_pairDirection = PAIR_DIR_UP;
         shouldOpenPair2 = true;
         Print("🔼 Xác định hướng: UP");
      }
      // Check giá đi xuống
      else if(currentPrice <= g_pair1Price - dcaDistance) {
         g_pairDirection = PAIR_DIR_DOWN;
         shouldOpenPair2 = true;
         Print("🔽 Xác định hướng: DOWN");
      }
      
      if(shouldOpenPair2) {
         OpenNewPair();
      }
      
      return;
   }
   
   // ═══════════════════════════════════════════════════════════════
   // TRƯỜNG HỢP 2: Đã có hướng - Check mở cặp mới
   // ═══════════════════════════════════════════════════════════════
   if(g_pairDirection != PAIR_DIR_NONE) {
      
      bool shouldOpenNewPair = false;
      bool shouldChangeDirection = false;
      
      // ───────────────────────────────────────────────────────────
      // A. CHECK ĐỔI HƯỚNG (khi giá vượt qua cặp 1)
      // ───────────────────────────────────────────────────────────
      if(g_pairDirection == PAIR_DIR_UP) {
         // Đang hướng lên, check giá có vượt xuống dưới cặp 1 không
         if(currentPrice <= g_pair1Price - dcaDistance) {
            g_pairDirection = PAIR_DIR_DOWN;
            shouldOpenNewPair = true;
            shouldChangeDirection = true;
            Print("════════════════════════════════════════");
            Print("🔄 ĐỔI HƯỚNG: UP → DOWN");
            Print("   Cặp 1: ", DoubleToString(g_pair1Price, _Digits));
            Print("   Hiện tại: ", DoubleToString(currentPrice, _Digits));
            Print("════════════════════════════════════════");
         }
      } 
      else if(g_pairDirection == PAIR_DIR_DOWN) {
         // Đang hướng xuống, check giá có vượt lên trên cặp 1 không
         if(currentPrice >= g_pair1Price + dcaDistance) {
            g_pairDirection = PAIR_DIR_UP;
            shouldOpenNewPair = true;
            shouldChangeDirection = true;
            Print("════════════════════════════════════════");
            Print("🔄 ĐỔI HƯỚNG: DOWN → UP");
            Print("   Cặp 1: ", DoubleToString(g_pair1Price, _Digits));
            Print("   Hiện tại: ", DoubleToString(currentPrice, _Digits));
            Print("════════════════════════════════════════");
         }
      }
      
      // ───────────────────────────────────────────────────────────
      // B. CHECK MỞ CẶP MỚI THEO HƯỚNG HIỆN TẠI (nếu chưa đổi hướng)
      // ───────────────────────────────────────────────────────────
      if(!shouldChangeDirection) {
         
         if(g_pairDirection == PAIR_DIR_UP) {
            // Hướng lên → Chỉ mở khi giá đi lên xa hơn
            
            if(InpAllowRefill) {
               // Cho phép nhồi: Mở khi giá >= lastPairPrice + distance
               if(currentPrice >= g_lastPairPrice + dcaDistance) {
                  shouldOpenNewPair = true;
               }
            } else {
               // Không nhồi: Phải xa hơn cặp cuối VÀ giá đang tăng
               if(currentPrice >= g_lastPairPrice + dcaDistance && 
                  currentPrice > g_lastPairPrice) {
                  shouldOpenNewPair = true;
               }
            }
         }
         else if(g_pairDirection == PAIR_DIR_DOWN) {
            // Hướng xuống → Chỉ mở khi giá đi xuống xa hơn
            
            if(InpAllowRefill) {
               // Cho phép nhồi: Mở khi giá <= lastPairPrice - distance
               if(currentPrice <= g_lastPairPrice - dcaDistance) {
                  shouldOpenNewPair = true;
               }
            } else {
               // Không nhồi: Phải xa hơn cặp cuối VÀ giá đang giảm
               if(currentPrice <= g_lastPairPrice - dcaDistance && 
                  currentPrice < g_lastPairPrice) {
                  shouldOpenNewPair = true;
               }
            }
         }
      }
      
      // ───────────────────────────────────────────────────────────
      // C. MỞ CẶP MỚI NẾU ĐỦ ĐIỀU KIỆN
      // ───────────────────────────────────────────────────────────
      if(shouldOpenNewPair) {
         OpenNewPair();
      }
   }
}

//+------------------------------------------------------------------+
//| Mở cặp mới với lot tăng dần                                      |
//+------------------------------------------------------------------+
void OpenNewPair() {
   g_pairCount++;
   
   // 🔥 FIX 1: Tính lot với làm tròn Exness
   double newLot;
   
   if(InpLotProgression == LOT_ADD) {
      // Hệ cộng: Lot tăng đều
      newLot = InpInitialLot + (g_pairCount - 1) * InpAddValue * InpInitialLot;
   } else {
      // Hệ nhân: Lot tăng theo lũy thừa
      newLot = InpInitialLot * MathPow(InpMultiplyValue, g_pairCount - 1);
   }
   
   // Làm tròn theo Exness
   newLot = RoundLotExness(newLot);
   
   // Kiểm tra lot tối đa
   if(newLot > InpMaxLot) {
      newLot = InpMaxLot;
   }
   
   // Mở cặp Buy + Sell
   string buyComment = "PAIR_" + IntegerToString(g_pairCount) + "_BUY";
   string sellComment = "PAIR_" + IntegerToString(g_pairCount) + "_SELL";
   
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   if(OpenOrder(ORDER_TYPE_BUY, newLot, buyComment) && 
      OpenOrder(ORDER_TYPE_SELL, newLot, sellComment)) {
      
      // Cập nhật giá cặp cuối
      g_lastPairPrice = currentPrice;
      
      string directionText = (g_pairDirection == PAIR_DIR_UP) ? "UP ⬆️" : "DOWN ⬇️";
      
      Print("════════════════════════════════════════════════════════");
      Print("✅ MỞ CẶP ", g_pairCount);
      Print("   Lot: ", DoubleToString(newLot, 2));
      Print("   Giá: ", DoubleToString(currentPrice, _Digits));
      Print("   Hướng: ", directionText);
      Print("   Cặp 1: ", DoubleToString(g_pair1Price, _Digits));
      Print("   Cặp cuối trước: ", DoubleToString(g_lastPairPrice, _Digits));
      Print("   Progression: ", InpLotProgression == LOT_ADD ? "Cộng" : "Nhân");
      Print("════════════════════════════════════════════════════════");
   }
}

//+------------------------------------------------------------------+
//| Kiểm tra TP 1 chiều (tất cả Buy lãi hoặc tất cả Sell lãi)       |
//+------------------------------------------------------------------+
bool CheckOneSidedProfit() {
   if(g_currentMode != MODE_PAIRS) return false;
   if(g_orderCount == 0) return false;
   
   double totalBuyProfit = 0;
   double totalSellProfit = 0;
   int buyCount = 0;
   int sellCount = 0;
   
   for(int i = 0; i < g_orderCount; i++) {
      if(g_orders[i].isHedgeLock) continue;
      
      if(PositionSelectByTicket(g_orders[i].ticket)) {
         double profit = PositionGetDouble(POSITION_PROFIT);
         
         if(g_orders[i].type == POSITION_TYPE_BUY) {
            totalBuyProfit += profit;
            buyCount++;
         } else {
            totalSellProfit += profit;
            sellCount++;
         }
      }
   }
   
   // Check 1 chiều đạt lãi
   bool buyProfitable = (buyCount > 0 && totalBuyProfit > 0);
   bool sellProfitable = (sellCount > 0 && totalSellProfit > 0);
   
   if(buyProfitable || sellProfitable) {
      Print("════════════════════════════════════════════════════════");
      Print("💰 TP 1 CHIỀU ĐẠT!");
      Print("   Buy: ", buyCount, " lệnh | Profit: $", DoubleToString(totalBuyProfit, 2));
      Print("   Sell: ", sellCount, " lệnh | Profit: $", DoubleToString(totalSellProfit, 2));
      Print("════════════════════════════════════════════════════════");
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Mode 1: DCA Âm/Dương (giữ nguyên)                               |
//+------------------------------------------------------------------+
void ManageOrdersMode1() {
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   // Tìm lệnh Buy và Sell cuối cùng
   double lastBuyPrice = 0, lastSellPrice = 0;
   
   for(int i = g_orderCount - 1; i >= 0; i--) {
      if(g_orders[i].isHedgeLock) continue;
      
      if(g_orders[i].type == POSITION_TYPE_BUY && lastBuyPrice == 0) {
         lastBuyPrice = g_orders[i].openPrice;
      }
      if(g_orders[i].type == POSITION_TYPE_SELL && lastSellPrice == 0) {
         lastSellPrice = g_orders[i].openPrice;
      }
      
      if(lastBuyPrice > 0 && lastSellPrice > 0) break;
   }
   
   double dcaDistance = CalculateDCADistance();
   
   // DCA BUY
   if(lastBuyPrice > 0) {
      bool shouldOpenBuy = false;
      
      if(g_currentMode == MODE_NEGATIVE) {
         if(InpAllowRefill) {
            shouldOpenBuy = (currentPrice < lastBuyPrice - dcaDistance);
         } else {
            shouldOpenBuy = (currentPrice < lastBuyPrice - dcaDistance) && (currentPrice < lastBuyPrice);
         }
      } 
      else if(g_currentMode == MODE_POSITIVE) {
         if(InpAllowRefill) {
            shouldOpenBuy = (currentPrice > lastBuyPrice + dcaDistance);
         } else {
            shouldOpenBuy = (currentPrice > lastBuyPrice + dcaDistance) && (currentPrice > lastBuyPrice);
         }
      }
      
      if(shouldOpenBuy) {
         double newLot = CalculateNextLot(g_lastBuyLot);
         
         if(newLot <= InpMaxLot) {
            if(OpenOrder(ORDER_TYPE_BUY, newLot, "DCA_BUY")) {
               g_lastBuyLot = newLot;
               g_buyDCACount++;
               Print("✅ DCA BUY #", g_buyDCACount, " | Lot: ", newLot);
            }
         }
      }
   }
   
   // DCA SELL
   if(lastSellPrice > 0) {
      bool shouldOpenSell = false;
      
      if(g_currentMode == MODE_NEGATIVE) {
         if(InpAllowRefill) {
            shouldOpenSell = (currentPrice > lastSellPrice + dcaDistance);
         } else {
            shouldOpenSell = (currentPrice > lastSellPrice + dcaDistance) && (currentPrice > lastSellPrice);
         }
      }
      else if(g_currentMode == MODE_POSITIVE) {
         if(InpAllowRefill) {
            shouldOpenSell = (currentPrice < lastSellPrice - dcaDistance);
         } else {
            shouldOpenSell = (currentPrice < lastSellPrice - dcaDistance) && (currentPrice < lastSellPrice);
         }
      }
      
      if(shouldOpenSell) {
         double newLot = CalculateNextLot(g_lastSellLot);
         
         if(newLot <= InpMaxLot) {
            if(OpenOrder(ORDER_TYPE_SELL, newLot, "DCA_SELL")) {
               g_lastSellLot = newLot;
               g_sellDCACount++;
               Print("✅ DCA SELL #", g_sellDCACount, " | Lot: ", newLot);
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
         return distance;
      } else {
         return InpDCADistance * _Point;
      }
   } else {
      return InpDCADistance * _Point;
   }
}

//+------------------------------------------------------------------+
//| 🔥 FIX 1: Tính lot tiếp theo với làm tròn Exness                |
//+------------------------------------------------------------------+
double CalculateNextLot(double currentLot) {
   double nextLot = 0;
   
   if(InpLotProgression == LOT_ADD) {
      nextLot = currentLot + (InpAddValue * InpInitialLot);
   } else {
      nextLot = currentLot * InpMultiplyValue;
   }
   
   // 🔥 FIX: Làm tròn theo Exness
   nextLot = RoundLotExness(nextLot);
   
   // Giới hạn lot
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
   
   // Validate lot
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   
   if(lots < minLot) lots = minLot;
   if(lots > maxLot) lots = maxLot;
   
   bool result = trade.PositionOpen(_Symbol, orderType, lots, price, 0, 0, comment);
   
   if(result) {
      Print("✅ Mở lệnh: ", comment, " | Lot: ", lots, " @ ", DoubleToString(price, _Digits));
   } else {
      Print("❌ Lỗi mở lệnh ", comment, ": ", GetLastError());
   }
   
   return result;
}

bool CheckTotalTP() {
   double totalProfit = CalculateTotalProfit();
   
   if(totalProfit >= InpTotalTP) {
      Print("💰 TP tổng đạt: $", totalProfit);
      return true;
   }
   
   return false;
}

bool CheckTotalSL() {
   double totalProfit = CalculateTotalProfit();
   
   if(totalProfit <= -InpTotalStopLoss) {
      Print("❌ SL tổng chạm: $", totalProfit);
      return true;
   }
   
   return false;
}

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
   g_highestProfit = 0;
   g_firstOrderPrice = 0;
   g_lastOrderPrice = 0;
   g_buyDCACount = 0;
   g_sellDCACount = 0;
   g_lastBuyLot = 0;
   g_lastSellLot = 0;
   g_pairCount = 0;
   g_currentMode = InpDCAMode;
   
   // Reset Hedge Lock
   g_hedgeLockActive = false;
   g_hedgeLockTicket = 0;
   g_hedgeLockOpenPrice = 0;
   g_hedgeLockDirection = -1;
   g_hedgeLockLot = 0;
   g_hedgeLockSL = 0;
   
   // 🆕 v2.25: Reset DCA Cặp
   g_pairDirection = PAIR_DIR_NONE;
   g_pair1Price = 0;
   g_lastPairPrice = 0;
   
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
      Print("🎯 Đạt mục tiêu ngày: $", dailyProfit);
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
   message += "⚡ VANG EXNESS v2.25\n";
   message += "━━━━━━━━━━━━━━━━━━━━\n\n";
   
   message += "💰 Balance: $" + DoubleToString(balance, 2) + "\n";
   message += "📈 Equity: $" + DoubleToString(equity, 2) + "\n";
   message += "💵 Profit: $" + DoubleToString(profit, 2) + "\n";
   message += "📅 Daily: $" + DoubleToString(dailyProfit, 2) + "\n\n";
   
   message += "📊 Orders: " + IntegerToString(g_orderCount) + "\n";
   message += "🔵 Buy: " + IntegerToString(buyCount) + "\n";
   message += "🔴 Sell: " + IntegerToString(sellCount) + "\n\n";
   
   if(g_currentMode == MODE_PAIRS) {
      string dir = (g_pairDirection == PAIR_DIR_UP) ? "UP ⬆️" : 
                   (g_pairDirection == PAIR_DIR_DOWN) ? "DOWN ⬇️" : "NONE";
      message += "🎯 Pairs: " + IntegerToString(g_pairCount) + " | Dir: " + dir + "\n";
   }
   
   if(g_hedgeLockActive) {
      message += "🔒 Hedge Lock: ACTIVE\n";
   }
   
   message += "\n⏰ " + TimeToString(currentTime, TIME_DATE|TIME_MINUTES);
   
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
//| TẠO PANEL UI - v2.25                                             |
//+------------------------------------------------------------------+
void CreatePanel() {
   int x = InpPanelX;
   int y = InpPanelY;
   int width = 320;
   int height = 580;
   
   // Background
   CreateLabel(g_panelPrefix + "BG", x, y, width, height, "", InpPanelColor, clrWhite);
   
   // Title
   CreateText(g_panelPrefix + "Title", x + 10, y + 10, "⚡ VANG EXNESS v2.25", clrYellow, 12, true);
   
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
   
   // 🆕 v2.25: DCA Cặp info
   CreateText(g_panelPrefix + "PairLabel", x + 10, y + 305, "Cặp:", clrWhite, 9, false);
   CreateText(g_panelPrefix + "PairValue", x + 80, y + 305, "0", clrCyan, 9, false);
   CreateText(g_panelPrefix + "DirLabel", x + 10, y + 325, "Hướng:", clrWhite, 9, false);
   CreateText(g_panelPrefix + "DirValue", x + 80, y + 325, "NONE", clrYellow, 9, false);
   
   CreateText(g_panelPrefix + "LockLabel", x + 10, y + 345, "Hedge Lock:", clrWhite, 9, false);
   CreateText(g_panelPrefix + "LockValue", x + 100, y + 345, "⚪ OFF", clrGray, 9, false);
   
   // Separator
   CreateRectangle(g_panelPrefix + "Sep4", x + 10, y + 370, 300, 1, clrGray);
   
   // Price Info
   CreateText(g_panelPrefix + "PriceLabel", x + 10, y + 380, "💹 GIÁ", clrWhite, 10, true);
   CreateText(g_panelPrefix + "CurrentLabel", x + 10, y + 400, "Hiện:", clrWhite, 9, false);
   CreateText(g_panelPrefix + "CurrentValue", x + 70, y + 400, "", clrYellow, 9, true);
   
   // Separator
   CreateRectangle(g_panelPrefix + "Sep5", x + 10, y + 425, 300, 1, clrGray);
   
   // Control Buttons
   CreateText(g_panelPrefix + "ButtonsLabel", x + 10, y + 435, "🎮 ĐIỀU KHIỂN", clrWhite, 10, true);
   
   CreateButton(g_panelPrefix + "BtnCloseAll", x + 10, y + 460, 95, 30, "Close All", clrDarkRed, clrWhite);
   CreateButton(g_panelPrefix + "BtnCloseBuy", x + 110, y + 460, 95, 30, "Close Buy", clrDodgerBlue, clrWhite);
   CreateButton(g_panelPrefix + "BtnCloseSell", x + 210, y + 460, 95, 30, "Close Sell", clrRed, clrWhite);
   
   CreateButton(g_panelPrefix + "BtnForceLock", x + 10, y + 495, 145, 30, "🔒 Lock", clrPurple, clrWhite);
   CreateButton(g_panelPrefix + "BtnForceUnlock", x + 160, y + 495, 145, 30, "🔓 Unlock", clrGreen, clrWhite);
   
   ChartRedraw();
}

void UpdatePanel() {
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double profit = CalculateTotalProfit();
   double dailyProfit = balance - g_dailyStartBalance;
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
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
   ObjectSetString(0, g_panelPrefix + "ModeValue", OBJPROP_TEXT, modeText);
   
   // 🆕 v2.25: DCA Cặp info
   if(g_currentMode == MODE_PAIRS) {
      ObjectSetString(0, g_panelPrefix + "PairValue", OBJPROP_TEXT, IntegerToString(g_pairCount) + "/" + IntegerToString(InpMaxPairs));
      
      string dirText = "NONE";
      color dirColor = clrGray;
      if(g_pairDirection == PAIR_DIR_UP) {
         dirText = "UP ⬆️";
         dirColor = clrLime;
      } else if(g_pairDirection == PAIR_DIR_DOWN) {
         dirText = "DOWN ⬇️";
         dirColor = clrRed;
      }
      ObjectSetString(0, g_panelPrefix + "DirValue", OBJPROP_TEXT, dirText);
      ObjectSetInteger(0, g_panelPrefix + "DirValue", OBJPROP_COLOR, dirColor);
   }
   
   // Hedge Lock
   if(g_hedgeLockActive) {
      ObjectSetString(0, g_panelPrefix + "LockValue", OBJPROP_TEXT, "🔒 LOCKED");
      ObjectSetInteger(0, g_panelPrefix + "LockValue", OBJPROP_COLOR, clrOrange);
   } else {
      ObjectSetString(0, g_panelPrefix + "LockValue", OBJPROP_TEXT, "⚪ OFF");
      ObjectSetInteger(0, g_panelPrefix + "LockValue", OBJPROP_COLOR, clrGray);
   }
   
   // Price
   ObjectSetString(0, g_panelPrefix + "CurrentValue", OBJPROP_TEXT, DoubleToString(currentPrice, _Digits));
   
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
