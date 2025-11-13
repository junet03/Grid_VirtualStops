//+------------------------------------------------------------------+
//|                      VangExness_v2.27_Preview_Demo.mq5          |
//|                                  Copyright 2024, Mr JuNet        |
//|   🔥 DEMO CODE - Tính năng mới v2.27                            |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Mr JuNet"
#property version   "2.27"
#property description "⚡ DEMO: Trailing TP PRO + Auto Mode Selection"

/*
═══════════════════════════════════════════════════════════════════
📌 FILE NÀY CHỈ LÀ DEMO CODE
   Không phải EA hoàn chỉnh, chỉ để xem trước logic tính năng mới

📌 2 TÍNH NĂNG DEMO:
   1. 🔥 Trailing TP PRO (từ v2.24)
      - Breakeven Protection
      - Multi-Level Trailing
      - Acceleration Trailing
      - Emergency Floor
      - Smart Recovery
      
   2. 🔥 Auto Mode Selection (mới)
      - Tự động chọn mode dựa trên ADX + MA Slope
      - Thích nghi với thị trường

📌 TÍCH HỢP VÀO v2.26:
   - Copy các function vào EA chính
   - Thêm input parameters
   - Gọi trong OnTick()
═══════════════════════════════════════════════════════════════════
*/

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| 1️⃣ TRAILING TP PRO - INPUT PARAMETERS                          |
//+------------------------------------------------------------------+

input group "===== TRAILING TP PRO v2.27 ====="
input double InpTotalTP = 100.0;                    // TP tổng ban đầu (USD)
input bool InpEnableTrailing = true;               // Bật Trailing TP Pro

// Breakeven Protection
input bool InpEnableBreakeven = true;              // Bật Breakeven Protection
input double InpBreakevenMultiplier = 1.5;         // Breakeven khi profit = TP x multiplier

// Multi-Level Trailing
input bool InpEnableMultiLevel = true;             // Bật Multi-Level Trailing
input double InpTrailingLevel1_Profit = 150.0;     // Level 1: Profit threshold (USD)
input double InpTrailingLevel1_Distance = 50.0;    // Level 1: Trailing distance (USD)
input double InpTrailingLevel2_Profit = 300.0;     // Level 2: Profit threshold (USD)
input double InpTrailingLevel2_Distance = 80.0;    // Level 2: Trailing distance (USD)
input double InpTrailingLevel3_Profit = 500.0;     // Level 3: Profit threshold (USD)
input double InpTrailingLevel3_Distance = 120.0;   // Level 3: Trailing distance (USD)

// Acceleration Trailing
input bool InpEnableAcceleration = true;           // Bật Acceleration Trailing
input double InpAccelMultiplier = 0.8;             // Hệ số giảm distance (0.8 = giảm 20%)
input double InpAccelStep = 100.0;                 // Mỗi $100 profit → giảm 1 lần

// Emergency Protection
input double InpEmergencyFloor = 50.0;             // Emergency floor (% of TP gốc)
input double InpMinimumProfit = 80.0;              // Profit tối thiểu tuyệt đối (USD)

// Smart Recovery
input bool InpEnableSmartRecovery = true;          // Bật Smart Recovery
input int InpRecoveryBars = 3;                     // Số nến phục hồi để nới trailing

//+------------------------------------------------------------------+
//| 2️⃣ AUTO MODE SELECTION - INPUT PARAMETERS                       |
//+------------------------------------------------------------------+

input group "===== AUTO MODE SELECTION v2.27 ====="
input bool InpEnableAutoMode = true;               // Bật Auto Mode Selection
input int InpAutoModeInterval = 300;               // Kiểm tra mode (giây)
input int InpADXPeriod = 14;                       // ADX Period
input int InpMAPeriod = 50;                        // MA Period để check slope

// Threshold
input double InpSidewaysADX = 20.0;                // ADX < 20 = Sideways
input double InpTrendingADX = 30.0;                // ADX > 30 = Strong Trend

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES - Trailing TP                                   |
//+------------------------------------------------------------------+

double g_trailingFloor = 0;           // Floor hiện tại của trailing
double g_maxProfit = 0;               // Max profit đã đạt
double g_lastProfit = 0;              // Profit nến trước (cho Smart Recovery)
int g_recoveryBarCount = 0;           // Đếm số nến phục hồi

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES - Auto Mode                                     |
//+------------------------------------------------------------------+

enum ENUM_DCA_MODE {
   MODE_NEGATIVE,    // DCA âm
   MODE_POSITIVE,    // DCA dương
   MODE_PAIRS,       // DCA cặp Model 1
   MODE_PAIRS_V2     // DCA cặp Model 2
};

enum ENUM_MARKET_STATE {
   MARKET_SIDEWAYS,      // ADX < 20
   MARKET_TRENDING,      // ADX 20-30
   MARKET_STRONG_TREND   // ADX > 30
};

ENUM_DCA_MODE g_currentMode = MODE_NEGATIVE;
datetime g_lastModeCheck = 0;
int g_adxHandle = INVALID_HANDLE;
int g_maHandle = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
   // Tạo indicator handles
   g_adxHandle = iADX(_Symbol, PERIOD_CURRENT, InpADXPeriod);
   g_maHandle = iMA(_Symbol, PERIOD_CURRENT, InpMAPeriod, 0, MODE_SMA, PRICE_CLOSE);
   
   if(g_adxHandle == INVALID_HANDLE || g_maHandle == INVALID_HANDLE) {
      Print("❌ Lỗi tạo indicator handles!");
      return INIT_FAILED;
   }
   
   Print("═══════════════════════════════════════");
   Print("✅ VangExness v2.27 DEMO Initialized");
   Print("   Trailing TP PRO: ", InpEnableTrailing ? "ON" : "OFF");
   Print("   Auto Mode: ", InpEnableAutoMode ? "ON" : "OFF");
   Print("═══════════════════════════════════════");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   if(g_adxHandle != INVALID_HANDLE) IndicatorRelease(g_adxHandle);
   if(g_maHandle != INVALID_HANDLE) IndicatorRelease(g_maHandle);
}

//+------------------------------------------------------------------+
//| Expert tick function - DEMO                                      |
//+------------------------------------------------------------------+
void OnTick() {
   // 🔥 TÍNH NĂNG 1: Auto Mode Selection
   if(InpEnableAutoMode) {
      ManageAutoMode();
   }
   
   // 🔥 TÍNH NĂNG 2: Trailing TP PRO
   if(InpEnableTrailing) {
      ManageTrailingTP();
   }
   
   // Demo: Log mỗi 30 giây
   static datetime lastLog = 0;
   if(TimeCurrent() - lastLog >= 30) {
      lastLog = TimeCurrent();
      PrintStatus();
   }
}

//+------------------------------------------------------------------+
//| 🔥 TÍNH NĂNG 1: AUTO MODE SELECTION                             |
//+------------------------------------------------------------------+

void ManageAutoMode() {
   datetime currentTime = TimeCurrent();
   
   // Kiểm tra theo interval
   if(currentTime - g_lastModeCheck < InpAutoModeInterval) {
      return;
   }
   
   g_lastModeCheck = currentTime;
   
   // Phân tích thị trường
   ENUM_MARKET_STATE market = AnalyzeMarket();
   ENUM_DCA_MODE oldMode = g_currentMode;
   
   // Chọn mode phù hợp
   switch(market) {
      case MARKET_SIDEWAYS:
         // ADX thấp → Sideways → DCA Cặp an toàn
         g_currentMode = MODE_PAIRS;
         break;
         
      case MARKET_TRENDING:
         // ADX trung bình → Trending → DCA Dương
         g_currentMode = MODE_POSITIVE;
         break;
         
      case MARKET_STRONG_TREND:
         // ADX cao → Strong Trend → DCA Cặp V2
         g_currentMode = MODE_PAIRS_V2;
         break;
   }
   
   // Thông báo nếu đổi mode
   if(oldMode != g_currentMode) {
      Print("════════════════════════════════════════");
      Print("🔄 AUTO MODE SWITCHED!");
      Print("   Market: ", GetMarketStateName(market));
      Print("   Old Mode: ", GetModeName(oldMode));
      Print("   New Mode: ", GetModeName(g_currentMode));
      Print("════════════════════════════════════════");
   }
}

ENUM_MARKET_STATE AnalyzeMarket() {
   // Lấy giá trị ADX
   double adxBuffer[];
   ArraySetAsSeries(adxBuffer, true);
   
   if(CopyBuffer(g_adxHandle, 0, 0, 1, adxBuffer) <= 0) {
      Print("❌ Lỗi đọc ADX buffer");
      return MARKET_SIDEWAYS;  // Default
   }
   
   double adxValue = adxBuffer[0];
   
   // Lấy giá trị MA để check slope
   double maBuffer[];
   ArraySetAsSeries(maBuffer, true);
   
   if(CopyBuffer(g_maHandle, 0, 0, 3, maBuffer) < 3) {
      Print("❌ Lỗi đọc MA buffer");
      return MARKET_SIDEWAYS;  // Default
   }
   
   // Tính MA slope
   double maSlope = (maBuffer[0] - maBuffer[2]) / 2.0;
   double maSlopeAbs = MathAbs(maSlope);
   
   // Log
   static datetime lastMarketLog = 0;
   if(TimeCurrent() - lastMarketLog >= 300) {  // Mỗi 5 phút
      lastMarketLog = TimeCurrent();
      Print("📊 Market Analysis:");
      Print("   ADX: ", DoubleToString(adxValue, 2));
      Print("   MA Slope: ", DoubleToString(maSlope, 5));
   }
   
   // Phân loại market
   if(adxValue < InpSidewaysADX) {
      return MARKET_SIDEWAYS;
   }
   else if(adxValue < InpTrendingADX) {
      // ADX trung bình → Check slope
      if(maSlopeAbs > 0.0001) {  // Có slope đáng kể
         return MARKET_TRENDING;
      } else {
         return MARKET_SIDEWAYS;
      }
   }
   else {
      // ADX cao
      return MARKET_STRONG_TREND;
   }
}

string GetMarketStateName(ENUM_MARKET_STATE state) {
   switch(state) {
      case MARKET_SIDEWAYS: return "Sideways";
      case MARKET_TRENDING: return "Trending";
      case MARKET_STRONG_TREND: return "Strong Trend";
   }
   return "Unknown";
}

string GetModeName(ENUM_DCA_MODE mode) {
   switch(mode) {
      case MODE_NEGATIVE: return "DCA Âm";
      case MODE_POSITIVE: return "DCA Dương";
      case MODE_PAIRS: return "DCA Cặp M1";
      case MODE_PAIRS_V2: return "DCA Cặp M2";
   }
   return "Unknown";
}

//+------------------------------------------------------------------+
//| 🔥 TÍNH NĂNG 2: TRAILING TP PRO                                 |
//+------------------------------------------------------------------+

void ManageTrailingTP() {
   // Giả lập total profit (trong EA thực sẽ tính từ orders)
   double totalProfit = CalculateTotalProfit();
   
   // Update max profit
   if(totalProfit > g_maxProfit) {
      g_maxProfit = totalProfit;
   }
   
   // ═══════════════════════════════════════════════════════════════
   // BƯỚC 1: BREAKEVEN PROTECTION
   // ═══════════════════════════════════════════════════════════════
   if(InpEnableBreakeven) {
      ManageBreakeven(totalProfit);
   }
   
   // ═══════════════════════════════════════════════════════════════
   // BƯỚC 2: MULTI-LEVEL TRAILING
   // ═══════════════════════════════════════════════════════════════
   if(InpEnableMultiLevel) {
      double trailingDistance = GetTrailingDistance(totalProfit);
      
      // Áp dụng acceleration nếu bật
      if(InpEnableAcceleration && trailingDistance > 0) {
         trailingDistance = GetAcceleratedDistance(trailingDistance, totalProfit);
      }
      
      // Tính trailing floor mới
      double newFloor = g_maxProfit - trailingDistance;
      
      // Chỉ update nếu floor mới cao hơn
      if(newFloor > g_trailingFloor) {
         double oldFloor = g_trailingFloor;
         g_trailingFloor = newFloor;
         
         Print("📈 Trailing Updated:");
         Print("   Max Profit: $", g_maxProfit);
         Print("   Distance: $", trailingDistance);
         Print("   Old Floor: $", oldFloor);
         Print("   New Floor: $", g_trailingFloor);
      }
   }
   
   // ═══════════════════════════════════════════════════════════════
   // BƯỚC 3: EMERGENCY FLOOR PROTECTION
   // ═══════════════════════════════════════════════════════════════
   CheckEmergencyFloor();
   
   // ═══════════════════════════════════════════════════════════════
   // BƯỚC 4: SMART RECOVERY
   // ═══════════════════════════════════════════════════════════════
   if(InpEnableSmartRecovery) {
      ManageSmartRecovery(totalProfit);
   }
   
   // ═══════════════════════════════════════════════════════════════
   // BƯỚC 5: CHECK TRAILING CLOSE
   // ═══════════════════════════════════════════════════════════════
   if(totalProfit < g_trailingFloor && g_trailingFloor > 0) {
      Print("════════════════════════════════════════");
      Print("💰 TRAILING TP HIT!");
      Print("   Profit: $", totalProfit);
      Print("   Floor: $", g_trailingFloor);
      Print("   Distance: $", DoubleToString(g_trailingFloor - totalProfit, 2));
      Print("════════════════════════════════════════");
      
      // Trong EA thực: CloseAllOrders();
      // Demo: Reset trailing
      ResetTrailing();
   }
   
   g_lastProfit = totalProfit;
}

// 🔥 Breakeven Protection
void ManageBreakeven(double totalProfit) {
   // Đạt breakeven threshold
   if(totalProfit >= InpTotalTP * InpBreakevenMultiplier && g_trailingFloor < 0.01) {
      g_trailingFloor = 0;
      
      Print("════════════════════════════════════════");
      Print("🛡️ BREAKEVEN ACTIVATED!");
      Print("   Profit: $", totalProfit);
      Print("   Threshold: $", InpTotalTP * InpBreakevenMultiplier);
      Print("   Trailing Floor: $0 (Breakeven)");
      Print("════════════════════════════════════════");
   }
}

// 🔥 Multi-Level Trailing
double GetTrailingDistance(double profit) {
   if(profit >= InpTrailingLevel3_Profit) {
      return InpTrailingLevel3_Distance;
   }
   else if(profit >= InpTrailingLevel2_Profit) {
      return InpTrailingLevel2_Distance;
   }
   else if(profit >= InpTrailingLevel1_Profit) {
      return InpTrailingLevel1_Distance;
   }
   
   return 0;  // Chưa đủ threshold
}

// 🔥 Acceleration Trailing
double GetAcceleratedDistance(double distance, double profit) {
   // Cứ mỗi $100 profit, giảm distance 20%
   int accelerationLevels = (int)(profit / InpAccelStep);
   
   for(int i = 0; i < accelerationLevels; i++) {
      distance *= InpAccelMultiplier;  // 0.8 = giảm 20%
   }
   
   // Log khi acceleration kick in
   static int lastAccelLevel = 0;
   if(accelerationLevels > lastAccelLevel) {
      lastAccelLevel = accelerationLevels;
      Print("🚀 Acceleration Level ", accelerationLevels, ": Distance = $", distance);
   }
   
   return distance;
}

// 🔥 Emergency Floor Protection
void CheckEmergencyFloor() {
   // Floor tối thiểu = % của TP gốc
   double minFloor1 = InpTotalTP * (InpEmergencyFloor / 100.0);
   
   // Floor tối thiểu tuyệt đối
   double minFloor2 = InpMinimumProfit;
   
   // Chọn floor cao hơn
   double minFloor = MathMax(minFloor1, minFloor2);
   
   // Update nếu floor hiện tại thấp hơn
   if(g_trailingFloor < minFloor) {
      g_trailingFloor = minFloor;
      
      Print("⚠️ Emergency Floor Applied: $", minFloor);
   }
}

// 🔥 Smart Recovery
void ManageSmartRecovery(double totalProfit) {
   // Giá đang phục hồi (profit tăng)
   if(totalProfit > g_lastProfit) {
      g_recoveryBarCount++;
      
      // Đủ số nến recovery
      if(g_recoveryBarCount >= InpRecoveryBars) {
         // Nới trailing distance 20%
         double currentDistance = GetTrailingDistance(totalProfit);
         if(currentDistance > 0) {
            double newDistance = currentDistance * 1.2;
            
            // Tính lại floor
            double newFloor = g_maxProfit - newDistance;
            
            if(newFloor < g_trailingFloor) {
               g_trailingFloor = newFloor;
               
               Print("════════════════════════════════════════");
               Print("📈 SMART RECOVERY ACTIVATED!");
               Print("   Recovery Bars: ", g_recoveryBarCount);
               Print("   Old Distance: $", currentDistance);
               Print("   New Distance: $", newDistance, " (+20%)");
               Print("   New Floor: $", g_trailingFloor);
               Print("════════════════════════════════════════");
            }
         }
         
         g_recoveryBarCount = 0;
      }
   } else {
      // Giá không tăng → Reset counter
      g_recoveryBarCount = 0;
   }
}

void ResetTrailing() {
   g_trailingFloor = 0;
   g_maxProfit = 0;
   g_lastProfit = 0;
   g_recoveryBarCount = 0;
   
   Print("🔄 Trailing Reset");
}

//+------------------------------------------------------------------+
//| HELPER FUNCTIONS                                                 |
//+------------------------------------------------------------------+

// Giả lập total profit (demo)
double CalculateTotalProfit() {
   // Trong EA thực: Tính từ positions
   // Demo: Tạo profit giả lập
   static double demoProfit = 0;
   static datetime lastUpdate = 0;
   
   if(TimeCurrent() - lastUpdate >= 60) {  // Update mỗi phút
      lastUpdate = TimeCurrent();
      
      // Giả lập profit tăng/giảm ngẫu nhiên
      double change = (MathRand() % 100 - 30) / 10.0;  // -3 đến +7
      demoProfit += change;
      
      // Giới hạn range
      if(demoProfit < 0) demoProfit = 0;
      if(demoProfit > 600) demoProfit = 600;
   }
   
   return demoProfit;
}

void PrintStatus() {
   Print("════════════════════════════════════════");
   Print("📊 STATUS UPDATE");
   Print("───────────────────────────────────────");
   Print("⚡ Auto Mode: ", InpEnableAutoMode ? "ON" : "OFF");
   if(InpEnableAutoMode) {
      Print("   Current Mode: ", GetModeName(g_currentMode));
   }
   Print("───────────────────────────────────────");
   Print("📈 Trailing TP: ", InpEnableTrailing ? "ON" : "OFF");
   if(InpEnableTrailing) {
      double profit = CalculateTotalProfit();
      Print("   Profit: $", DoubleToString(profit, 2));
      Print("   Max Profit: $", DoubleToString(g_maxProfit, 2));
      Print("   Floor: $", DoubleToString(g_trailingFloor, 2));
      
      if(g_trailingFloor > 0) {
         double distance = g_maxProfit - g_trailingFloor;
         Print("   Distance: $", DoubleToString(distance, 2));
      }
   }
   Print("════════════════════════════════════════");
}

//+------------------------------------------------------------------+
