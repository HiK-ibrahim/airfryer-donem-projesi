# 🍳 Akıllı Airfryer (Smart Airfryer) IoT Projesi

![ESP32](https://img.shields.io/badge/ESP32-Hardware-black?style=flat&logo=espressif)
![Flutter](https://img.shields.io/badge/Flutter-Mobile_App-02569B?style=flat&logo=flutter)
![C++](https://img.shields.io/badge/C++-Firmware-00599C?style=flat&logo=c%2B%2B)
![WebSocket](https://img.shields.io/badge/WebSocket-Communication-green?style=flat)

Bu proje, geleneksel bir fritözü (Airfryer) **ESP32 mikrodenetleyicisi** ve modern IoT teknolojileri kullanarak tamamen akıllı, uzaktan kontrol edilebilir ve programlanabilir bir cihaza dönüştürmeyi amaçlamaktadır. 

> **Not:** Bu çalışma donanım tabanı olarak **Karaca Air Procook Airfryer** modeli üzerinde gerçekleştirilmiş ve optimize edilmiştir. Ancak, sistem mimarisi gereği röle ve sıcaklık sensörü kullanan **alternatif diğer tüm Airfryer modellerine de kolaylıkla uyarlanabilir.**

---

## 📖 Proje Hakkında (Projenin Olayı)

Geleneksel Airfryer cihazları, üreticinin sunduğu kapalı kaynaklı ve limitli kontrol kartları ile çalışır. Bu projenin temel çıkış noktası, cihazın orijinal beynini devre dışı bırakıp yerine Wi-Fi yetenekli bir **ESP32** yerleştirerek donanım sınırlarını ortadan kaldırmaktır.

Bu sayede cihaza; **uzaktan erişim, gerçek zamanlı sıcaklık izleme, daha hassas ısı kontrol algoritmaları ve mobil uygulama üzerinden dinamik pişirme senaryoları oluşturma** gibi üst düzey teknolojik yetenekler kazandırılmıştır.

## ✨ Temel Özellikler

- 📱 **Mobil Uygulama Entegrasyonu:** Flutter ile geliştirilen özel arayüz sayesinde cihaza anlık komut gönderme ve durumu takip etme.
- ⚡ **Gecikmesiz Haberleşme:** ESP32 üzerinde koşan WebSocket sunucusu sayesinde mobil cihaz ile mili-saniyeler içinde çift yönlü veri akışı.
- 🌡️ **Hassas ve Temiz Sıcaklık Verisi:** NTC sensörler üzerinden alınan verilerin, ESP32'nin Wi-Fi sinyallerinden kaynaklanan parazitlerini sönümleyen **özel ADC gürültü filtreleme fonksiyonları** ile işlenmesi.
- 🛡️ **Gelişmiş Failsafe (Güvenlik) Algoritmaları:** 
  - Olası sensör kopmalarında anında kapanmayı engelleyen **3 saniyelik hata tolerans (error tolerance) mantığı**.
  - İstenmeyen aşırı ısınma durumlarında sistemi otomatik ve güvenli şekilde kapatan acil durum protokolleri.
- ⚙️ **Broadcast Stream Yönetimi:** Birden fazla WebSocket istemcisinin çakışmadan aynı anda verileri sorunsuz dinleyebilmesini sağlayan kararlı altyapı.

## 🛠️ Kullanılan Teknolojiler

### Yazılım (Software)
- **Gömülü Sistem:** C/C++ (Arduino Framework)
- **Mobil Uygulama:** Flutter & Dart
- **Ağ İletişimi:** WebSocket & Wi-Fi (IEEE 802.11 b/g/n)

### Donanım (Hardware)
- **Mikrodenetleyici:** ESP32 (Wi-Fi ve Bluetooth entegre işlemci)
- **Sensör:** NTC Termistör (100K)
- **Kontrolcüler:** Yüksek akımlı Röle Modülleri (Isıtıcı rezistans ve fan tetiklemesi için)
- **Cihaz:** Karaca Air Procook Airfryer (Hedef Donanım)

## 🏗️ Sistem Mimarisi

Sistem iki ana koldan eşgüdümlü olarak çalışır:
1. **ESP32 Donanım Katmanı:** İlgili GPIO pinleri (örn. GPIO 21, 22, 23, 19, 34) üzerinden röleleri sürerek ısıtıcı ve fanı yönetir. NTC sensöründen elde ettiği ham analog sıcaklık verisini işler, filtreler ve JSON formatında WebSocket üzerinden yayınlar (Broadcast Stream).
2. **Flutter İstemci Katmanı:** Mobil uygulama, yerel ağ (LAN) üzerinden ESP32'ye bağlanır. Kullanıcının arayüzde yaptığı ayarları (Sıcaklık artırma, süreyi başlatma vb.) komut dizileri olarak cihaza iletirken, fritözden gelen güncel sıcaklık değerlerini canlı animasyonlarla ekrana çizer.

---
*Bu çalışma, Nesnelerin İnterneti (IoT), gömülü donanım tasarımı ve mobil programlama disiplinlerinin bir araya getirilerek gerçek bir mutfak aletinin nasıl "akıllandırıldığını" gösteren bir mühendislik projesidir.*
