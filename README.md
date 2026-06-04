# ESP32 Airfryer Kontrol Projesi

Bu çalışma **Karaca Air Procook Airfryer** için yapılmış olup, çalışma prensibi benzer olan **alternatif airfryer modellerine de uygulanabilir.**

## Projenin Amacı (Olayı)

Bu projenin temel amacı, standart bir airfryer cihazının donanım kontrolünü bir ESP32 mikrodenetleyicisi ile devralarak, cihaza uzaktan kontrol, hassas sıcaklık takibi ve akıllı telefon üzerinden yönetilebilirlik kazandırmaktır.

Projeyle birlikte cihazın kendi kontrol kartı yerine ESP32 kullanılarak:
- Isıtıcı rezistansların ve fanların doğrudan kontrolü
- NTC sensörler üzerinden hassas sıcaklık okuması
- Wi-Fi/WebSocket üzerinden Flutter tabanlı mobil uygulama ile eşzamanlı haberleşme
gibi yetenekler cihaza eklenmektedir.
