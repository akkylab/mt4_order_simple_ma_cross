//━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  order_ma_cross.mq4
//  移動平均線のゴールデンクロス・デッドクロスで売買するEA
//━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

//***********************************************************************
// 【1. プリプロセッサ部分】
// プログラムの設定を記述する「おまじない」部分
//***********************************************************************

#property version   "1.00"                  // プログラムのバージョン
#property strict                            // 厳密なコンパイルを有効化 (これを書くことで、潜在的なエラーを検出できる)


//***********************************************************************
// 【2. フィールド部分】
// プログラムで使う変数を宣言する部分
//***********************************************************************

// 【input変数】MT4の画面上で変更できる変数

input double TradeLots = 0.01;              // 取引ロット数
                                             // FXTF MT4の場合：
                                             // 0.01ロット = 1,000通貨（最小取引単位）
                                             // 0.1ロット  = 10,000通貨
                                             // 1.0ロット  = 100,000通貨
                                             // ※例：USDJPYが150円の場合、0.01ロット = 150,000円分の取引

input int ShortMAPeriod = 5;                 // 短期移動平均線の期間（5日線）
                                             // 過去5本のローソク足の終値平均を計算します
                                             // 数値が小さいほど、価格変動に敏感に反応します

input int LongMAPeriod = 20;                // 長期移動平均線の期間（20日線）
                                             // 過去20本のローソク足の終値平均を計算します
                                             // 数値が大きいほど、長期的なトレンドを表します

input int ProfitLossPips = 100;             // 利確・損切りの幅（pips）
                                             // FXTF MT4の場合：100pips = 1円
                                             // 例：USDJPY 150.000円でエントリーした場合
                                             //   利確: 151.000円（+100pips）
                                             //   損切: 149.000円（-100pips）
                                             // リスクリワード比 = 1:1（損失と利益が同じ幅）

// 【グローバル変数】プログラム内部で使う固定値・変数（inputなし）
string EA_NAME = "MovingAverage";           // オーダーコメントに使用するEA名
                                             // チャート上の注文に表示される識別名

double pipValue;                            // ブローカーの桁数に対応したPoint補正値
                                             // FXTF MT4は3桁/5桁表示なので Point × 10 が設定されます
                                             // USDJPY の場合: Point = 0.001 → pipValue = 0.01 = 1pip

datetime previousBarTime;                   // 前回のローソク足の時刻を記録（重複エントリー防止用）
                                             // 同じローソク足内で何度もエントリーしないための変数


//***********************************************************************
// 【3. 関数部分】
// 実際の処理を行う部分
//***********************************************************************

//━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  【関数1】OnInit() - 初期化関数
//  EAが起動した時に1回だけ実行される
//━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
int OnInit(){
   // ブローカーの桁数に応じて1pipの値を設定
   if (Digits == 3 || Digits == 5){
      pipValue = Point * 10;  // FXTF MT4はこちら（3桁または5桁表示）
   }else{
      pipValue = Point;       // 2桁または4桁表示のブローカー
   }
   return(INIT_SUCCEEDED);
}

//━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  【関数2】OnDeinit() - 終了関数
//  EAが停止した時に実行される
//━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
void OnDeinit(const int reason){
   // 現在は特に処理なし
}

//━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  【関数3】OnTick() - ティック関数（メイン処理）
//  新しい価格データが来るたびに実行される
//━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
void OnTick(){
   // MT4の「自動売買」ボタンがOFFの時、この関数をスキップする
   if(!IsTradeAllowed()){
      return;
   }
   
   // 変数の初期化
   int positionCount = OrdersTotal();       // 現在保有しているポジション数
   int orderType = -1;                      // 注文タイプ (0:買い, 1:売り, -1:未設定)
   double stopLossPrice = 0;                // 損切り価格
   double takeProfitPrice = 0;              // 利確価格

   // 新しいローソク足ができた時だけ処理を実行（重複エントリー防止）
   if(Time[0] != previousBarTime){
      previousBarTime = Time[0];
   }else{
      return;
   }

   // 短期移動平均線の値を取得
   double shortMA_Current = iMA(NULL, 0, ShortMAPeriod, 0, MODE_SMA, PRICE_CLOSE, 1);   // 1本前
   double shortMA_Previous = iMA(NULL, 0, ShortMAPeriod, 0, MODE_SMA, PRICE_CLOSE, 2);  // 2本前
       
   // 長期移動平均線の値を取得
   double longMA_Current = iMA(NULL, 0, LongMAPeriod, 0, MODE_SMA, PRICE_CLOSE, 1);     // 1本前
   double longMA_Previous = iMA(NULL, 0, LongMAPeriod, 0, MODE_SMA, PRICE_CLOSE, 2);    // 2本前

   // ゴールデンクロスの判定（買いシグナル）
   // 条件：短期MAが長期MAを下から上に突き抜けた
   bool isGoldenCross = false;
   if(shortMA_Current > longMA_Current && 
      shortMA_Previous < longMA_Previous && 
      shortMA_Current > shortMA_Previous){
      isGoldenCross = true;
   }
   
   // デッドクロスの判定（売りシグナル）
   // 条件：短期MAが長期MAを上から下に突き抜けた
   bool isDeadCross = false;
   if(shortMA_Current < longMA_Current && 
      shortMA_Previous > longMA_Previous && 
      shortMA_Current < shortMA_Previous){
      isDeadCross = true;
   }

   // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   // 【パターン1】ポジションがない場合：エントリー判定
   // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   if(positionCount == 0){
      // フラグ変数の初期化
      bool shouldBuy  = false;              // 買いエントリーフラグ
      bool shouldSell = false;              // 売りエントリーフラグ

      // エントリーフラグの設定
      if(isGoldenCross){
         shouldBuy = true;
         orderType = OP_BUY;
      }else if(isDeadCross){
         shouldSell = true;
         orderType = OP_SELL;
      }

      // 利確・損切り価格の計算
      double profitLossDistance = ProfitLossPips * pipValue;
      
      if(shouldBuy){
         stopLossPrice = Ask - profitLossDistance;    // 損切り: エントリー価格から100pips下
         takeProfitPrice = Ask + profitLossDistance;  // 利確: エントリー価格から100pips上
      }
      else if(shouldSell){
         stopLossPrice = Bid + profitLossDistance;    // 損切り: エントリー価格から100pips上
         takeProfitPrice = Bid - profitLossDistance;  // 利確: エントリー価格から100pips下
      }

      // 注文を実行
      if(orderType > -1){
         ExecuteOrder(orderType, stopLossPrice, takeProfitPrice, TradeLots, EA_NAME, 777);
      }
   }
   // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   // 【パターン2】ポジションがある場合：エグジット判定
   // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   else if(positionCount > 0){
      // すべてのポジションをチェック
      for(int i = positionCount - 1; i >= 0; i--){
         // ポジション情報を取得
         if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)){
            // このEAが発注したポジションかチェック（マジックナンバーで判定）
            if(OrderMagicNumber() == 777 && OrderSymbol() == Symbol()){
               int currentOrderType = OrderType();
               
               // 買いポジション保有中にデッドクロスが発生 → 決済
               if(currentOrderType == OP_BUY && isDeadCross){
                  CloseOrder(OrderTicket());
               }
               // 売りポジション保有中にゴールデンクロスが発生 → 決済
               else if(currentOrderType == OP_SELL && isGoldenCross){
                  CloseOrder(OrderTicket());
               }
            }
         }
      }
   }

   return;
}


//━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  【関数4】ExecuteOrder() - 新規注文実行関数
//  指定された条件で新規注文を発注する（最大3回リトライ）
//━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
bool ExecuteOrder(int orderType, double stopLoss, double takeProfit, double lots,
                  string comment, int magicNumber){
   
   int    ticketNumber = -1;     // 注文チケット番号
   double entryPrice = 0;        // エントリー価格
   color  arrowColor = clrNONE;  // チャート上の矢印の色

   // 最大3回まで注文を試行
   for(int retryCount = 0; retryCount < 3; retryCount++)
   {
      RefreshRates();  // 最新の価格情報を取得

      // エントリー価格と矢印の色を設定
      if(orderType == OP_BUY){
         entryPrice = Ask;
         arrowColor = clrBlue;
      }else if(orderType == OP_SELL){
         entryPrice = Bid;
         arrowColor = clrRed;
      }

      // 注文を発注
      ticketNumber = OrderSend(Symbol(), orderType, lots, entryPrice,
                               20, stopLoss, takeProfit, comment, magicNumber, 0, arrowColor);

      if(ticketNumber > 0){
         // 注文成功
         Print("新規注文成功! チケットNo=", ticketNumber,
               " レート=", entryPrice, " Lots=", lots);
         return true;
      }else{
         // 注文失敗
         int errorCode = GetLastError();
         Print("新規注文失敗 エラーNo=", errorCode,
               " リトライ回数=", retryCount + 1);
         Sleep(2000);  // 2秒待機してから再試行
      }
   }

   // 3回リトライしても失敗した場合
   return false;
}

//━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  【関数5】CloseOrder() - ポジション決済関数
//  指定されたチケット番号のポジションを決済する（最大3回リトライ）
//━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
bool CloseOrder(int ticketNumber){
   bool closeResult = false;
   
   // 最大3回まで決済を試行
   for(int retryCount = 0; retryCount < 3; retryCount++){
      RefreshRates();  // 最新の価格情報を取得
      
      // ポジション情報を取得
      if(OrderSelect(ticketNumber, SELECT_BY_TICKET)){
         double closePrice = 0;
         color arrowColor = clrNONE;
         
         // 決済価格と矢印の色を設定
         if(OrderType() == OP_BUY){
            closePrice = Bid;      // 買いポジションはBidで決済
            arrowColor = clrRed;
         }else if(OrderType() == OP_SELL){
            closePrice = Ask;      // 売りポジションはAskで決済
            arrowColor = clrBlue;
         }
         
         // ポジションを決済
         closeResult = OrderClose(ticketNumber, OrderLots(), closePrice, 20, arrowColor);
         
         if(closeResult){
            // 決済成功
            Print("ポジション決済成功! チケットNo=", ticketNumber,
                  " 決済レート=", closePrice);
            return true;
         }else{
            // 決済失敗
            int errorCode = GetLastError();
            Print("ポジション決済失敗 エラーNo=", errorCode,
                  " リトライ回数=", retryCount + 1);
            Sleep(2000);  // 2秒待機してから再試行
         }
      }
   }
   
   // 3回リトライしても失敗した場合
   return false;
}
