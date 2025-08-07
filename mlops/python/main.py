import pandas as pd
import numpy as np
import requests
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report, accuracy_score
from sklearn.preprocessing import StandardScaler
import warnings
warnings.filterwarnings('ignore')

class CryptoPredictionModel:
    def __init__(self):
        self.model = RandomForestClassifier(n_estimators=100, random_state=42)
        self.scaler = StandardScaler()
        
    def get_exchange_rate(self):
        """현재 USD/KRW 환율 가져오기"""
        try:
            # ExchangeRate-API 사용 (무료)
            url = "https://api.exchangerate-api.com/v4/latest/USD"
            response = requests.get(url)
            data = response.json()
            return data['rates']['KRW']
        except:
            # 실패시 기본값 (대략적인 환율)
            return 1300
    
    def fetch_crypto_data(self, symbol='vechain', days=365, currency='krw'):
        """CoinGecko API로 암호화폐 데이터 가져오기"""
        url = f"https://api.coingecko.com/api/v3/coins/{symbol}/market_chart"
        params = {
            'vs_currency': currency,
            'days': days,
            'interval': 'daily'
        }
        
        try:
            response = requests.get(url, params=params)
            if response.status_code != 200:
                print(f"API 오류: {response.status_code}")
                return None
                
            data = response.json()
            
            # 데이터 정리
            prices = data['prices']
            volumes = data['total_volumes']
            
            df = pd.DataFrame({
                'timestamp': [p[0] for p in prices],
                'price': [p[1] for p in prices],
                'volume': [v[1] for v in volumes]
            })
            
            # 타임스탬프를 한국시간으로 변환
            df['date'] = pd.to_datetime(df['timestamp'], unit='ms', utc=True)
            df['date'] = df['date'].dt.tz_convert('Asia/Seoul')
            df = df.set_index('date').drop('timestamp', axis=1)
            
            # 최신 데이터 확인
            print(f"데이터 범위: {df.index[0].strftime('%Y-%m-%d')} ~ {df.index[-1].strftime('%Y-%m-%d')}")
            print(f"총 {len(df)}일 데이터")
            
            return df
            
        except Exception as e:
            print(f"데이터 가져오기 실패: {e}")
            return None
    
    def create_features(self, df):
        """기술적 지표 및 특징 생성"""
        # 가격 변화율
        df['price_change_1d'] = df['price'].pct_change(1)
        df['price_change_7d'] = df['price'].pct_change(7)
        df['price_change_30d'] = df['price'].pct_change(30)
        
        # 이동평균
        df['ma_7'] = df['price'].rolling(7).mean()
        df['ma_30'] = df['price'].rolling(30).mean()
        df['ma_ratio'] = df['price'] / df['ma_30']
        
        # RSI (상대강도지수)
        delta = df['price'].diff()
        gain = (delta.where(delta > 0, 0)).rolling(14).mean()
        loss = (-delta.where(delta < 0, 0)).rolling(14).mean()
        rs = gain / loss
        df['rsi'] = 100 - (100 / (1 + rs))
        
        # 볼린저 밴드
        rolling_mean = df['price'].rolling(20).mean()
        rolling_std = df['price'].rolling(20).std()
        df['bb_upper'] = rolling_mean + (rolling_std * 2)
        df['bb_lower'] = rolling_mean - (rolling_std * 2)
        df['bb_position'] = (df['price'] - df['bb_lower']) / (df['bb_upper'] - df['bb_lower'])
        
        # 거래량 지표
        df['volume_ma'] = df['volume'].rolling(7).mean()
        df['volume_ratio'] = df['volume'] / df['volume_ma']
        df['volume_change'] = df['volume'].pct_change(1)
        
        # 변동성
        df['volatility'] = df['price_change_1d'].rolling(7).std()
        
        return df
    
    def create_targets(self, df):
        """타겟 변수 생성"""
        # 다음날 가격 방향 (0: 하락, 1: 상승)
        df['next_price'] = df['price'].shift(-1)
        df['direction'] = (df['next_price'] > df['price']).astype(int)
        
        # 급등/급락 신호 (5% 이상 변동)
        df['next_change'] = df['next_price'].pct_change()
        df['signal'] = 0  # 0: 보통, 1: 급등, 2: 급락
        df.loc[df['next_change'] > 0.05, 'signal'] = 1  # 5% 이상 상승
        df.loc[df['next_change'] < -0.05, 'signal'] = 2  # 5% 이상 하락
        
        return df
    
    def prepare_data(self, df):
        """모델 학습용 데이터 준비"""
        feature_cols = [
            'price_change_1d', 'price_change_7d', 'price_change_30d',
            'ma_ratio', 'rsi', 'bb_position', 'volume_ratio', 
            'volume_change', 'volatility'
        ]
        
        # 결측값 제거
        df_clean = df[feature_cols + ['direction', 'signal']].dropna()
        
        X = df_clean[feature_cols]
        y_direction = df_clean['direction']
        y_signal = df_clean['signal']
        
        return X, y_direction, y_signal
    
    def train_direction_model(self, X, y):
        """가격 방향성 예측 모델 학습"""
        X_train, X_test, y_train, y_test = train_test_split(
            X, y, test_size=0.2, random_state=42, stratify=y
        )
        
        # 스케일링
        X_train_scaled = self.scaler.fit_transform(X_train)
        X_test_scaled = self.scaler.transform(X_test)
        
        # 모델 학습
        self.model.fit(X_train_scaled, y_train)
        
        # 예측 및 평가
        y_pred = self.model.predict(X_test_scaled)
        accuracy = accuracy_score(y_test, y_pred)
        
        print("=== 가격 방향성 예측 모델 ===")
        print(f"정확도: {accuracy:.4f}")
        print("\n분류 리포트:")
        print(classification_report(y_test, y_pred, 
                                  target_names=['하락', '상승']))
        
        # 특징 중요도
        feature_importance = pd.DataFrame({
            'feature': X.columns,
            'importance': self.model.feature_importances_
        }).sort_values('importance', ascending=False)
        
        print("\n특징 중요도:")
        print(feature_importance)
        
        return accuracy
    
    def predict_current(self, df):
        """현재 상황 예측"""
        feature_cols = [
            'price_change_1d', 'price_change_7d', 'price_change_30d',
            'ma_ratio', 'rsi', 'bb_position', 'volume_ratio', 
            'volume_change', 'volatility'
        ]
        
        # 최신 데이터로 예측
        latest_data = df[feature_cols].iloc[-1:].fillna(0)
        latest_scaled = self.scaler.transform(latest_data)
        
        direction_pred = self.model.predict(latest_scaled)[0]
        direction_prob = self.model.predict_proba(latest_scaled)[0]
        
        print("\n=== 현재 상황 예측 ===")
        print(f"내일 방향: {'상승' if direction_pred == 1 else '하락'}")
        print(f"상승 확률: {direction_prob[1]:.3f}")
        print(f"하락 확률: {direction_prob[0]:.3f}")
        
        # 현재 지표 상황
        current_indicators = df[feature_cols].iloc[-1]
        latest_price = df['price'].iloc[-1]
        
        print(f"\n=== 현재 상황 ===")
        print(f"현재 가격: ₩{latest_price:,.2f}")
        print(f"현재 RSI: {current_indicators['rsi']:.1f}")
        print(f"볼린저밴드 위치: {current_indicators['bb_position']:.3f}")
        print(f"거래량 비율: {current_indicators['volume_ratio']:.2f}")
        
        # RSI 해석 (0~100)
        rsi_val = current_indicators['rsi']
        if rsi_val > 70:
            print("🔴 RSI 해석: 과매수 구간 (70 이상) - 매도 압력 증가 가능성")
        elif rsi_val < 30:
            print("🟢 RSI 해석: 과매도 구간 (30 이하) - 매수 기회 가능성")
        else:
            print("🟡 RSI 해석: 중립 구간 (30~70) - 균형 상태")
        
        # 볼린저밴드 해석 (0~1)
        bb_pos = current_indicators['bb_position']
        if bb_pos > 0.8:
            print("🔴 볼린저밴드: 상단 근처 (0.8 이상) - 고점권, 조정 가능성")
        elif bb_pos < 0.2:
            print("🟢 볼린저밴드: 하단 근처 (0.2 이하) - 저점권, 반등 가능성")
        else:
            print("🟡 볼린저밴드: 중간 구간 - 정상 변동 범위")
        
        # 거래량 비율 해석
        vol_ratio = current_indicators['volume_ratio']
        if vol_ratio > 1.5:
            print("📈 거래량: 평균 대비 높음 (1.5배 이상) - 강한 관심, 변동성 증가")
        elif vol_ratio < 0.5:
            print("📉 거래량: 평균 대비 낮음 (0.5배 이하) - 관심 저조, 횡보 가능성")
        else:
            print("📊 거래량: 평균 수준 - 정상적인 거래 활동")

# 실행 예제
if __name__ == "__main__":
    # 모델 초기화
    crypto_model = CryptoPredictionModel()
    
    print("비트코인 데이터 가져오는 중...")
    
    # 데이터 가져오기 (원화 기준)
    df = crypto_model.fetch_crypto_data('vechain', days=365, currency='krw')
    
    if df is not None:
        print(f"데이터 수집 완료: {len(df)}일")
        
        # 특징 생성
        df = crypto_model.create_features(df)
        df = crypto_model.create_targets(df)
        
        # 데이터 준비
        X, y_direction, y_signal = crypto_model.prepare_data(df)
        
        print(f"학습 데이터: {len(X)}개")
        
        # 모델 학습
        accuracy = crypto_model.train_direction_model(X, y_direction)
        
        # 현재 상황 예측
        crypto_model.predict_current(df)
        
        # 최근 가격 동향
        print(f"\n=== 최근 7일 가격 동향 ===")
        recent_prices = df['price'].tail(7)
        for i, (date, price) in enumerate(recent_prices.items()):
            date_str = date.strftime('%m-%d (%a)')
            if i == len(recent_prices) - 1:
                print(f"📅 {date_str}: ₩{price:,.2f} ← 최신")
            else:
                prev_price = recent_prices.iloc[i-1] if i > 0 else price
                change = ((price - prev_price) / prev_price * 100) if i > 0 else 0
                arrow = "📈" if change > 0 else "📉" if change < 0 else "➡️"
                print(f"📅 {date_str}: ₩{price:,.2f} {arrow} ({change:+.1f}%)")
        
        # 일주일 변화율
        week_change = ((recent_prices.iloc[-1] - recent_prices.iloc[0]) / recent_prices.iloc[0] * 100)
        print(f"\n7일 변화율: {week_change:+.1f}%")
        
        # 기술적 지표 가이드
        print(f"\n=== 기술적 지표 가이드 ===")
        print("📊 RSI (0~100): 30 이하 과매도, 70 이상 과매수")
        print("📊 볼린저밴드 (0~1): 0.2 이하 저점권, 0.8 이상 고점권") 
        print("📊 거래량 비율: 1.5 이상 관심 증가, 0.5 이하 관심 저조")
    
    else:
        print("데이터를 가져올 수 없습니다.")