#include <WiFi.h>
#include <WebSocketsServer.h>
#include <ArduinoJson.h>

// Wi-Fi Access Point (AP) Ayarları
const char* ssid = "hik_airfrey";
const char* password = "12345678";

WebSocketsServer webSocket = WebSocketsServer(81);

// =============================================
// PIN TANIMLARI - ESP32 DevKit V1 (Şemaya Göre Güncellendi)
// =============================================
#define fanPin        23    // Fan Motoru (J1-3 CP) → GPIO23 (Doğrudan)
#define heaterPin     22    // Isıtıcı Rezistans (J1-2 B3) → GPIO22 (Doğrudan)
#define buzzerPin     21    // Buzzer (Güç kartından gelen 4. Pin) → GPIO21 (Doğrudan)
#define ntcPin        34    // NTC Sıcaklık Sensörü → GPIO34 (NTC GND'ye, 2.2k direnç 3.3V'a bağlı)
#define lidSwitchPin  19    // Kapak Anahtarı (Switch ucu) → GPIO19 (GND'ye bağlı, INPUT_PULLUP)
#define ledPin         2    // Durum LED (ESP32 dahili LED) → GPIO2

// NTC Termistör Sabitleri (Eski/Klasik Pull-up bağlantı: Sabit direnç VCC, NTC GND)
const float R_fixed = 1000.0;   // Sabit direnç (ohm) - 1k
const float R0 = 100000.0;      // NTC referans direnci (Genelde Airfryer için 100K NTC kullanılır)
const float T_ref = 298.15;      // Referans sıcaklık (25°C = 298.15K)
const float Beta = 3950.0;      // NTC Beta katsayısı
const float Vcc = 3.3;          // ESP32 besleme gerilimi

// Kontrol ayarları
float maxTemp = 200.0;           // Kullanıcının belirlediği hedef sıcaklık
bool heaterState = false;
bool systemReady = true;
bool lidClosed = true;

// Zamanlayıcı ayarları
unsigned long cookingTime = 0;   // Kullanıcıdan gelecek süre (milisaniye)
unsigned long startTime = 0;
bool timerActive = false;
bool systemFinished = false;

// Servis Test Modu
bool testMode = false;
bool testFanState = false;
bool testHeaterState = false;
bool testLedState = false;

// Zaman Takibi
unsigned long lastUpdate = 0;
unsigned long ntcErrorStartTime = 0;
bool ntcErrorActive = false;
unsigned long lastErrorBeep = 0;

void setup() {
  Serial.begin(115200);
  
  // Pin ayarları
  pinMode(fanPin, OUTPUT);
  pinMode(heaterPin, OUTPUT);
  pinMode(lidSwitchPin, INPUT_PULLUP);
  pinMode(ledPin, OUTPUT);
  
  // ESP32'de Tone kullanmak yerine basit bir LEDC PWM veya sadece dijital toggle kullanılabilir.
  // Yeni ESP32 core versiyonlarında tone() çalışmaktadır, ancak bazı eski sürümlerde çalışmaz.
  // Buzzer pinini standart OUTPUT olarak ayarlayalım.
  pinMode(buzzerPin, OUTPUT);
  
  digitalWrite(fanPin, LOW);
  digitalWrite(heaterPin, LOW);
  digitalWrite(ledPin, LOW);
  
  // Wi-Fi Access Point (AP) Yayını
  Serial.println("Wi-Fi Erisim Noktasi (AP) Basiyor...");
  WiFi.softAP(ssid, password);
  
  Serial.print("AP IP Adresi: ");
  Serial.println(WiFi.softAPIP());

  // WebSocket Başlatma
  webSocket.begin();
  webSocket.onEvent(webSocketEvent);
  
  Serial.println("WebSocket Sunucusu Baslatildi (Port: 81)");
  playBeep(1000, 500); // Açılış sesi
}

void loop() {
  webSocket.loop();
  
  // Test modu aktifken normal pişirme mantığını atla
  if(testMode) {
    // Test modunda sadece WebSocket dinle, periyodik durum güncellemesi gönder
    if(millis() - lastUpdate > 1000) {
      lastUpdate = millis();
      sendTestStatus();
    }
    return;
  }
  
  // Kapak durumu
  lidClosed = (digitalRead(lidSwitchPin) == LOW); 
  
  // Zamanlayıcı kontrolü
  unsigned long remainingTime = 0;
  if (!testMode) {
    if(timerActive && !systemFinished) {
      unsigned long elapsedTime = millis() - startTime;
      if(elapsedTime >= cookingTime) {
        systemFinished = true;
        timerActive = false;
        digitalWrite(heaterPin, LOW);
        digitalWrite(fanPin, LOW);
        heaterState = false;
        
        Serial.println("SURE DOLDU - SISTEM KAPANDI!");
        for(int i = 0; i < 3; i++) { playBeep(1000, 500); delay(200); }
      } else {
        remainingTime = cookingTime - elapsedTime;
      }
    }
    
    // Kapak Koruması
    if(!lidClosed) {
      if(heaterState || digitalRead(fanPin) == HIGH) {
        digitalWrite(heaterPin, LOW);
        digitalWrite(fanPin, LOW);
        heaterState = false;
        Serial.println("KAPAK ACIK! Sistem Durdu.");
      }
    }
  }
  
  // NTC Ölçümü (Wi-Fi parazitini önlemek için ortalama alınıyor)
  int adcValue = readNTCAverage();
  float voltage = adcValue * (Vcc / 4095.0); // ESP32 12-bit ADC (0-4095)
  // Sabit direnç VCC'de, NTC GND tarafında olduğu için hesaplama (Klasik voltaj bölücü):
  float R_ntc = (Vcc - voltage > 0) ? (voltage * R_fixed / (Vcc - voltage)) : 999999.0;
  if (R_ntc < 1.0) R_ntc = 1.0; // log(0) koruması
  float tempK = 1.0 / (1.0 / T_ref + (1.0 / Beta) * log(R_ntc / R0));
  float tempC = tempK - 273.15;
  
  bool currentTempValid = !(tempC < -50.0 || tempC > 225.0 || isnan(tempC) || isinf(tempC));
  bool validTemp = true;
  
  if (!currentTempValid) {
    if (!ntcErrorActive) {
      ntcErrorActive = true;
      ntcErrorStartTime = millis();
    } else if (millis() - ntcErrorStartTime >= 3000) {
      // 3 saniye doldu, hatayı kesinleştir
      validTemp = false;
      
      // Çok hızlı dönen loop'u bloklamamak için saniyede bir kez alarm çal
      if (millis() - lastErrorBeep > 1000) {
        lastErrorBeep = millis();
        playBeep(2500, 100);
        delay(100);
        playBeep(2500, 100);
        Serial.println("HATA: NTC baglantisi 3 saniyedir kopuk/hatali! Isitici KAPALI");
      }
    }
  } else {
    // Okuma düzeldiyse hatayı temizle
    ntcErrorActive = false;
    validTemp = true;
  }
  
  // Sıcaklık Kontrolü (Sadece zamanlayıcı aktifse ve kapak kapalıysa)
  if (!testMode) {
    if(timerActive && !systemFinished && lidClosed && validTemp) {
      digitalWrite(fanPin, HIGH); // Çalışırken fan hep açık
      if(tempC >= maxTemp && heaterState) {
        digitalWrite(heaterPin, LOW);
        heaterState = false;
      } else if(tempC <= (maxTemp - 5.0) && !heaterState) {
        digitalWrite(heaterPin, HIGH);
        heaterState = true;
      }
    } else if (!timerActive || systemFinished || !validTemp) {
      digitalWrite(heaterPin, LOW);
      digitalWrite(fanPin, LOW);
      heaterState = false;
    }
  }
  
  // 1 Saniyede bir Mobil Uygulamaya Veri Gönder
  if(millis() - lastUpdate > 1000) {
    lastUpdate = millis();
    
    // JSON oluştur
    StaticJsonDocument<200> doc;
    doc["temp"] = validTemp ? tempC : -999;
    doc["heaterState"] = heaterState;
    doc["lidClosed"] = lidClosed;
    doc["timerActive"] = timerActive;
    doc["remainingSecs"] = remainingTime / 1000;
    doc["timerTotalSecs"] = cookingTime / 1000; // İlerleme çubuğu için toplam süre
    
    String jsonString;
    serializeJson(doc, jsonString);
    webSocket.broadcastTXT(jsonString); // Tüm bağlı istemcilere yolla
    
    Serial.print("Sicaklik: "); Serial.print(tempC);
    Serial.print(" R_NTC: "); Serial.print(R_ntc);
    Serial.print(" Hedef: "); Serial.print(maxTemp);
    Serial.print(" KalanSn: "); Serial.println(remainingTime / 1000);
  }
}

// Test modu durum bilgisi gönder
void sendTestStatus() {
  // NTC Ölçümü
  int adcValue = readNTCAverage();
  float voltage = adcValue * (Vcc / 4095.0);
  // Sabit direnç VCC'de, NTC GND tarafında olduğu için hesaplama (Klasik voltaj bölücü):
  float R_ntc = (Vcc - voltage > 0) ? (voltage * R_fixed / (Vcc - voltage)) : 999999.0;
  if (R_ntc < 1.0) R_ntc = 1.0; // log(0) koruması
  float tempK = 1.0 / (1.0 / T_ref + (1.0 / Beta) * log(R_ntc / R0));
  float tempC = tempK - 273.15;
  
  StaticJsonDocument<256> doc;
  doc["testMode"] = true;
  doc["testFan"] = testFanState;
  doc["testHeater"] = testHeaterState;
  doc["testLed"] = testLedState;
  doc["temp"] = (tempC > -50 && tempC < 225 && !isnan(tempC) && !isinf(tempC)) ? tempC : -999;
  doc["lidClosed"] = (digitalRead(lidSwitchPin) == LOW);
  
  String jsonString;
  serializeJson(doc, jsonString);
  webSocket.broadcastTXT(jsonString);
}

// Tek bir test yanıtı gönder
void sendTestResult(String result) {
  StaticJsonDocument<128> doc;
  doc["testResult"] = result;
  String jsonString;
  serializeJson(doc, jsonString);
  webSocket.broadcastTXT(jsonString);
}

// WebSocket Gelen Mesajları Yakalama
void webSocketEvent(uint8_t num, WStype_t type, uint8_t * payload, size_t length) {
  if(type == WStype_TEXT) {
    String msg = String((char*)payload);
    Serial.println("Gelen Mesaj: " + msg);
    
    StaticJsonDocument<200> doc;
    DeserializationError error = deserializeJson(doc, msg);
    if(error) return;
    
    String action = doc["action"]; // "start", "stop", veya test komutları
    
    // === NORMAL MODLAR ===
    if(action == "start") {
      if(testMode) return; // Test modundayken pişirme başlatma
      float t = doc["temp"];
      int minutes = doc["time"];
      if(t > 0 && minutes > 0) {
        maxTemp = t;
        cookingTime = minutes * 60000;
        startTime = millis();
        timerActive = true;
        systemFinished = false;
        playBeep(1500, 300);
      }
    } 
    else if(action == "stop") {
      timerActive = false;
      systemFinished = true;
      digitalWrite(heaterPin, LOW);
      digitalWrite(fanPin, LOW);
      heaterState = false;
      playBeep(800, 500);
    }
    
    // === SERVİS TEST MODU ===
    else if(action == "test_mode_on") {
      testMode = true;
      // Pişirme durdur
      timerActive = false;
      systemFinished = true;
      // Tüm çıkışları kapat
      digitalWrite(fanPin, LOW);
      digitalWrite(heaterPin, LOW);
      digitalWrite(ledPin, LOW);
      heaterState = false;
      testFanState = false;
      testHeaterState = false;
      testLedState = false;
      Serial.println(">>> SERVIS TEST MODU AKTIF <<<");
      playBeep(2000, 200);
      sendTestResult("test_mode_active");
    }
    else if(action == "test_mode_off") {
      testMode = false;
      // Tüm test çıkışlarını kapat
      digitalWrite(fanPin, LOW);
      digitalWrite(heaterPin, LOW);
      digitalWrite(ledPin, LOW);
      testFanState = false;
      testHeaterState = false;
      testLedState = false;
      Serial.println(">>> SERVIS TEST MODU KAPANDI <<<");
      playBeep(1000, 200);
      sendTestResult("test_mode_off");
    }
    else if(action == "test_fan") {
      if(!testMode) return;
      testFanState = !testFanState;
      digitalWrite(fanPin, testFanState ? HIGH : LOW);
      Serial.println(testFanState ? "TEST: Fan ACIK" : "TEST: Fan KAPALI");
      sendTestResult(testFanState ? "fan_on" : "fan_off");
    }
    else if(action == "test_heater") {
      if(!testMode) return;
      testHeaterState = !testHeaterState;
      digitalWrite(heaterPin, testHeaterState ? HIGH : LOW);
      Serial.println(testHeaterState ? "TEST: Isitici ACIK" : "TEST: Isitici KAPALI");
      sendTestResult(testHeaterState ? "heater_on" : "heater_off");
    }
    else if(action == "test_buzzer") {
      if(!testMode) return;
      Serial.println("TEST: Buzzer Caliniyor...");
      sendTestResult("buzzer_start");
      playBeep(1500, 500);
      sendTestResult("buzzer_done");
    }
    else if(action == "test_led") {
      if(!testMode) return;
      testLedState = !testLedState;
      digitalWrite(ledPin, testLedState ? HIGH : LOW);
      Serial.println(testLedState ? "TEST: LED ACIK" : "TEST: LED KAPALI");
      sendTestResult(testLedState ? "led_on" : "led_off");
    }
    else if(action == "test_ntc") {
      if(!testMode) return;
      // Anlık NTC okuma
      int adcVal = readNTCAverage();
      float v = adcVal * (Vcc / 4095.0);
      // Sabit direnç VCC'de, NTC GND tarafında olduğu için hesaplama (Klasik voltaj bölücü):
      float rNtc = (Vcc - v > 0) ? (v * R_fixed / (Vcc - v)) : 999999.0;
      if (rNtc < 1.0) rNtc = 1.0; // log(0) koruması
      float tK = 1.0 / (1.0 / T_ref + (1.0 / Beta) * log(rNtc / R0));
      float tC = tK - 273.15;
      
      StaticJsonDocument<128> ntcDoc;
      ntcDoc["testResult"] = "ntc_read";
      ntcDoc["ntcTemp"] = (tC > -50 && tC < 225 && !isnan(tC) && !isinf(tC)) ? tC : -999;
      ntcDoc["ntcRaw"] = adcVal;
      String ntcJson;
      serializeJson(ntcDoc, ntcJson);
      webSocket.broadcastTXT(ntcJson);
      Serial.print("TEST NTC: "); Serial.println(tC);
    }
    else if(action == "test_all") {
      if(!testMode) return;
      Serial.println("TEST: Tum Bilesenleri Test Ediliyor...");
      sendTestResult("test_all_start");
      
      // 1) Fan testi
      digitalWrite(fanPin, HIGH); testFanState = true;
      sendTestResult("fan_on");
      delay(1000);
      digitalWrite(fanPin, LOW); testFanState = false;
      sendTestResult("fan_off");
      delay(300);
      
      // 2) Buzzer testi
      sendTestResult("buzzer_start");
      playBeep(1500, 500);
      sendTestResult("buzzer_done");
      delay(300);
      
      // 3) Isıtıcı testi
      digitalWrite(heaterPin, HIGH); testHeaterState = true;
      sendTestResult("heater_on");
      delay(1000);
      digitalWrite(heaterPin, LOW); testHeaterState = false;
      sendTestResult("heater_off");
      delay(300);
      
      // 4) LED testi
      digitalWrite(ledPin, HIGH); testLedState = true;
      sendTestResult("led_on");
      delay(1000);
      digitalWrite(ledPin, LOW); testLedState = false;
      sendTestResult("led_off");
      delay(300);
      
      // 5) NTC okuma
      int adcVal = readNTCAverage();
      float v = adcVal * (Vcc / 4095.0);
      // Sabit direnç VCC'de, NTC GND tarafında olduğu için hesaplama (Klasik voltaj bölücü):
      float rNtc = (Vcc - v > 0) ? (v * R_fixed / (Vcc - v)) : 999999.0;
      if (rNtc < 1.0) rNtc = 1.0; // log(0) koruması
      float tK = 1.0 / (1.0 / T_ref + (1.0 / Beta) * log(rNtc / R0));
      float tC = tK - 273.15;
      
      StaticJsonDocument<128> ntcDoc;
      ntcDoc["testResult"] = "ntc_read";
      ntcDoc["ntcTemp"] = (tC > -50 && tC < 225 && !isnan(tC) && !isinf(tC)) ? tC : -999;
      ntcDoc["ntcRaw"] = adcVal;
      String ntcJson;
      serializeJson(ntcDoc, ntcJson);
      webSocket.broadcastTXT(ntcJson);
      
      sendTestResult("test_all_done");
      Serial.println("TEST: Tum Testler Tamamlandi!");
    }
  }
}

// Wi-Fi parazitini azaltmak için ortalama okuma fonksiyonu
int readNTCAverage() {
  long sum = 0;
  int validCount = 0;
  for(int i = 0; i < 20; i++) {
    int adcVal = analogRead(ntcPin);
    
    // Okunan ham değerin sıcaklık karşılığını hesapla
    float v = adcVal * (Vcc / 4095.0);
    float rNtc = (Vcc - v > 0) ? (v * R_fixed / (Vcc - v)) : 999999.0;
    if (rNtc < 1.0) rNtc = 1.0;
    float tK = 1.0 / (1.0 / T_ref + (1.0 / Beta) * log(rNtc / R0));
    float tC = tK - 273.15;
    
    // Sadece mantıklı değerleri ortalamaya dahil et (parazit sıçramalarını filtrele)
    if(tC >= -50.0 && tC <= 225.0 && !isnan(tC) && !isinf(tC)) {
      sum += adcVal;
      validCount++;
    }
    delay(2);
  }
  
  // Eğer parazitten dolayı tüm okumalar saçma geldiyse son değeri yolla, ana döngü hatayı verip sistemi durdursun
  if(validCount == 0) {
    return analogRead(ntcPin);
  }
  
  return sum / validCount;
}

// Güvenli Buzzer Fonksiyonu
void playBeep(unsigned int freq, unsigned long duration) {
  #ifdef ESP32
    // ESP32 Arduino Core 3.x Donanımsal PWM (ledc) API'si
    ledcAttach(buzzerPin, freq, 8); // Pin, İstenen Frekans, 8-bit çözünürlük
    ledcWrite(buzzerPin, 128);      // %50 duty cycle (ses seviyesi)
    
    // İşlemciyi kilitlemeyen, Wi-Fi'a nefes aldıran standart gecikme
    delay(duration);
    
    ledcWrite(buzzerPin, 0); // Sesi kapat
    ledcDetach(buzzerPin);
  #else
    tone(buzzerPin, freq, duration);
    delay(duration);
  #endif
}
