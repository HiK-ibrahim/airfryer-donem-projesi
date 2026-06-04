import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  runApp(const AirfryerApp());
}

class AirfryerApp extends StatelessWidget {
  const AirfryerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Airfryer Kontrol',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF101010), // Derin Siyah
        primaryColor: const Color(0xFFD32F2F), // Koyu Kırmızı
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFD32F2F),
          secondary: Color(0xFFFF5252),
          surface: Color(0xFF1C1C1C), // Yüzey rengi
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF101010),
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
        useMaterial3: true,
      ),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // UI States
  int _targetTemperature = 180;
  int _targetTimeMinutes = 15;
  
  // ESP32 Status Variables
  double _currentTemp = 0.0;
  bool _timerActive = false;
  bool _heaterState = false;
  bool _lidClosed = true;
  int _remainingSecs = 0;
  int _totalSecs = 0;
  
  // Connection Variables
  final TextEditingController _ipController = TextEditingController(text: "192.168.4.1");
  WebSocketChannel? _channel;
  Stream<dynamic>? _broadcastStream;
  bool _isConnected = false;

  @override
  void dispose() {
    _channel?.sink.close();
    _ipController.dispose();
    super.dispose();
  }

  void _connect() {
    if (_isConnected) {
      _channel?.sink.close();
      setState(() => _isConnected = false);
      return;
    }
    
    final ip = _ipController.text.trim();
    if (ip.isEmpty) return;

    try {
      final wsUrl = Uri.parse('ws://$ip:81');
      _channel = WebSocketChannel.connect(wsUrl);
      _broadcastStream = _channel!.stream.asBroadcastStream();
      
      _broadcastStream!.listen(
        (message) {
          try {
            final data = jsonDecode(message);
            setState(() {
              _currentTemp = (data['temp'] ?? 0.0).toDouble();
              _heaterState = data['heaterState'] ?? false;
              _lidClosed = data['lidClosed'] ?? true;
              _timerActive = data['timerActive'] ?? false;
              _remainingSecs = data['remainingSecs'] ?? 0;
              _totalSecs = data['timerTotalSecs'] ?? 0;
            });
          } catch (e) {
            debugPrint("Parse error: $e");
          }
        },
        onDone: () {
          setState(() {
            _isConnected = false;
            _timerActive = false;
          });
          _showSnackBar("Bağlantı kesildi!");
        },
        onError: (error) {
          setState(() => _isConnected = false);
          _showSnackBar("Bağlantı hatası: ESP ağına (hik_airfrey) bağlı olduğunuzdan emin olun.");
        },
      );
      
      setState(() => _isConnected = true);
      _showSnackBar("Bağlanıyor...");
    } catch(e) {
      _showSnackBar("Hatalı IP veya Bağlantı Sorunu!");
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  void _togglePower() {
    if (!_isConnected) {
      _showSnackBar("Önce ESP32'ye bağlanın!");
      return;
    }

    if (_timerActive) {
      _channel?.sink.add(jsonEncode({"action": "stop"}));
    } else {
      if (!_lidClosed) {
        _showSnackBar("Lütfen önce kapağı kapatın!");
        return;
      }
      _channel?.sink.add(jsonEncode({
        "action": "start",
        "temp": _targetTemperature,
        "time": _targetTimeMinutes
      }));
    }
  }

  void _setPreset(int temp, int time) {
    if (_timerActive) return; 
    setState(() {
      _targetTemperature = temp;
      _targetTimeMinutes = time;
    });
  }

  String _formatTime(int totalSeconds) {
    int m = totalSeconds ~/ 60;
    int s = totalSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('HIK AIRFRYER'),
        actions: [
          IconButton(
            icon: const Icon(Icons.build_rounded, color: Colors.orangeAccent),
            tooltip: 'Servis Test Modu',
            onPressed: () {
              if (_timerActive) {
                _showSnackBar("Pişirme aktifken test moduna geçilemez!");
                return;
              }
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ServiceTestScreen(
                    channel: _channel,
                    stream: _broadcastStream,
                    isConnected: _isConnected,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
        child: Column(
          children: [
            _buildConnectionCard(),
            const SizedBox(height: 24),
            _buildProgressDisplay(),
            const SizedBox(height: 32),
            _buildElegantControls(),
            const SizedBox(height: 32),
            _buildPresetsPanel(),
            const SizedBox(height: 48), // Alt boşluk
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isConnected ? Colors.green.shade700 : Colors.grey.shade800,
          width: 1,
        )
      ),
      child: Row(
        children: [
          Icon(
            _isConnected ? Icons.wifi : Icons.wifi_off,
            color: _isConnected ? Colors.green : Colors.red,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Ağ: hik_airfrey",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
                Text(
                  _isConnected ? "Bağlı" : "Bağlantı Yok",
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                )
              ],
            ),
          ),
          ElevatedButton(
            onPressed: _connect,
            style: ElevatedButton.styleFrom(
              backgroundColor: _isConnected ? Colors.grey.shade800 : Theme.of(context).colorScheme.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: Text(_isConnected ? "Kes" : "Bağlan"),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressDisplay() {
    double progress = 0;
    if (_timerActive && _totalSecs > 0) {
      int passedSecs = _totalSecs - _remainingSecs;
      progress = passedSecs / _totalSecs;
    }

    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 250,
            height: 250,
            child: CircularProgressIndicator(
              value: _timerActive ? progress : 0,
              strokeWidth: 12,
              backgroundColor: Theme.of(context).colorScheme.surface,
              color: Theme.of(context).colorScheme.primary,
              strokeCap: StrokeCap.round,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                !_lidClosed ? Icons.lock_open : Icons.local_fire_department,
                color: !_lidClosed 
                    ? Colors.red 
                    : (_heaterState ? Theme.of(context).colorScheme.secondary : Colors.grey.shade700),
                size: 32,
              ),
              const SizedBox(height: 8),
              Text(
                _timerActive ? _formatTime(_remainingSecs) : _formatTime(_targetTimeMinutes * 60),
                style: const TextStyle(
                  fontSize: 56,
                  fontWeight: FontWeight.w300,
                  color: Colors.white,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                !_lidClosed 
                    ? "KAPAK AÇIK" 
                    : (_timerActive ? "${(_currentTemp < -50) ? "--" : _currentTemp.toStringAsFixed(1)} °C" : "BEKLİYOR"),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: !_lidClosed 
                      ? Colors.red 
                      : (_timerActive ? Theme.of(context).colorScheme.secondary : Colors.grey.shade500),
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildElegantControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildDialControl(
          label: "SICAKLIK",
          value: "$_targetTemperature",
          unit: "°C",
          onMinus: _timerActive ? null : () {
            if (_targetTemperature > 80) setState(() => _targetTemperature -= 5);
          },
          onPlus: _timerActive ? null : () {
            if (_targetTemperature < 220) setState(() => _targetTemperature += 5);
          },
        ),
        
        // Ortadaki Büyük Güç Butonu
        GestureDetector(
          onTap: _togglePower,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _timerActive
                  ? Theme.of(context).colorScheme.surface
                  : Theme.of(context).colorScheme.primary,
              boxShadow: [
                if (!_timerActive)
                  BoxShadow(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                    blurRadius: 15,
                    spreadRadius: 2,
                  ),
              ],
              border: Border.all(
                color: Theme.of(context).colorScheme.primary,
                width: 3,
              ),
            ),
            child: Icon(
              _timerActive ? Icons.stop_rounded : Icons.power_settings_new_rounded,
              size: 40,
              color: _timerActive ? Theme.of(context).colorScheme.primary : Colors.white,
            ),
          ),
        ),

        _buildDialControl(
          label: "SÜRE",
          value: "$_targetTimeMinutes",
          unit: "dk",
          onMinus: _timerActive ? null : () {
            if (_targetTimeMinutes > 1) setState(() => _targetTimeMinutes -= 1);
          },
          onPlus: _timerActive ? null : () {
            if (_targetTimeMinutes < 60) setState(() => _targetTimeMinutes += 1);
          },
        ),
      ],
    );
  }

  Widget _buildDialControl({
    required String label,
    required String value,
    required String unit,
    VoidCallback? onMinus,
    VoidCallback? onPlus,
  }) {
    bool disabled = onMinus == null;
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: disabled ? Colors.grey.shade700 : Colors.grey.shade400,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: 100,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              IconButton(
                icon: const Icon(Icons.add),
                color: disabled ? Colors.grey.shade800 : Colors.white,
                onPressed: onPlus,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: disabled ? Colors.grey.shade600 : Colors.white,
                    ),
                  ),
                  Text(
                    unit,
                    style: TextStyle(
                      fontSize: 12,
                      color: disabled ? Colors.grey.shade800 : Colors.white70,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.remove),
                color: disabled ? Colors.grey.shade800 : Colors.white,
                onPressed: onMinus,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPresetsPanel() {
    return Column(
      children: [
        const Text(
          "- HAZIR MODLAR -",
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: [
            _buildPresetButton(Icons.fastfood, "Patates", 200, 15),
            _buildPresetButton(Icons.set_meal, "Balık", 180, 20),
            _buildPresetButton(Icons.restaurant, "Tavuk", 190, 25),
            _buildPresetButton(Icons.local_pizza, "Pizza", 170, 10),
            _buildPresetButton(Icons.bakery_dining, "Kek", 160, 30),
          ],
        ),
      ],
    );
  }

  Widget _buildPresetButton(IconData icon, String label, int temp, int time) {
    bool isSelected = (_targetTemperature == temp && _targetTimeMinutes == time);
    return InkWell(
      onTap: () => _setPreset(temp, time),
      customBorder: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        width: 80,
        height: 100,
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary.withOpacity(0.15)
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 28,
              color: isSelected
                  ? Theme.of(context).colorScheme.secondary
                  : Colors.grey.shade400,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.white : Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "$temp°\n$time dk",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9,
                color: isSelected ? Colors.grey.shade300 : Colors.grey.shade600,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// SERVİS TEST MODU EKRANI
// ============================================================

class ServiceTestScreen extends StatefulWidget {
  final WebSocketChannel? channel;
  final Stream<dynamic>? stream;
  final bool isConnected;

  const ServiceTestScreen({
    super.key,
    this.channel,
    this.stream,
    required this.isConnected,
  });

  @override
  State<ServiceTestScreen> createState() => _ServiceTestScreenState();
}

class _ServiceTestScreenState extends State<ServiceTestScreen>
    with SingleTickerProviderStateMixin {
  // Bileşen durumları
  bool _fanOn = false;
  bool _heaterOn = false;
  bool _ledOn = false;
  bool _buzzerBusy = false;
  bool _testAllRunning = false;
  double _ntcTemp = -999;
  int _ntcRaw = 0;
  bool _ntcRead = false;
  String _lastResult = '';

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    // Test modunu aç
    if (widget.isConnected && widget.channel != null && widget.stream != null) {
      _sendCommand('test_mode_on');

      // WebSocket dinle
      widget.stream!.listen(_handleMessage, onError: (_) {}, onDone: () {});
    }
  }

  @override
  void dispose() {
    // Test modunu kapat
    if (widget.isConnected && widget.channel != null) {
      _sendCommand('test_mode_off');
    }
    _pulseController.dispose();
    super.dispose();
  }

  void _sendCommand(String action) {
    if (!widget.isConnected || widget.channel == null) return;
    try {
      widget.channel!.sink.add(jsonEncode({'action': action}));
    } catch (_) {}
  }

  void _handleMessage(dynamic message) {
    try {
      final data = jsonDecode(message);
      setState(() {
        // Periyodik test durum güncellemesi
        if (data['testMode'] == true) {
          _fanOn = data['testFan'] ?? false;
          _heaterOn = data['testHeater'] ?? false;
          _ledOn = data['testLed'] ?? false;
          if (data['temp'] != null && data['temp'] != -999) {
            _ntcTemp = (data['temp'] as num).toDouble();
          }
        }

        // Tek seferlik test yanıtları
        if (data['testResult'] != null) {
          _lastResult = data['testResult'];
          switch (_lastResult) {
            case 'fan_on':
              _fanOn = true;
              break;
            case 'fan_off':
              _fanOn = false;
              break;
            case 'heater_on':
              _heaterOn = true;
              break;
            case 'heater_off':
              _heaterOn = false;
              break;
            case 'led_on':
              _ledOn = true;
              break;
            case 'led_off':
              _ledOn = false;
              break;
            case 'buzzer_start':
              _buzzerBusy = true;
              break;
            case 'buzzer_done':
              _buzzerBusy = false;
              break;
            case 'test_all_start':
              _testAllRunning = true;
              break;
            case 'test_all_done':
              _testAllRunning = false;
              break;
          }
        }

        // NTC okuma
        if (data['testResult'] == 'ntc_read') {
          _ntcTemp = (data['ntcTemp'] as num?)?.toDouble() ?? -999;
          _ntcRaw = (data['ntcRaw'] as num?)?.toInt() ?? 0;
          _ntcRead = true;
        }
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SERVİS TEST MODU'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Uyarı başlığı
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.orange.withOpacity(0.15 + _pulseController.value * 0.1),
                        Colors.deepOrange.withOpacity(0.1 + _pulseController.value * 0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.orangeAccent.withOpacity(0.5),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.isConnected
                                  ? 'Servis Test Modu Aktif'
                                  : 'Bağlantı Yok / Bilgi Alınamıyor',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.orangeAccent,
                              ),
                            ),
                            Text(
                              widget.isConnected
                                  ? 'Her bileşeni ayrı ayrı kontrol edebilirsiniz.'
                                  : 'Lütfen bağlantı kablosunu ve ağı kontrol edin. Veriler alınamıyor.',
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 24),

            // Buton Grid
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 1.1,
              children: [
                _buildTestCard(
                  icon: Icons.air,
                  label: 'FAN',
                  subtitle: widget.isConnected ? (_fanOn ? 'AÇIK' : 'KAPALI') : 'BAĞLANTI YOK',
                  isActive: _fanOn,
                  activeColor: Colors.cyanAccent,
                  onTap: widget.isConnected ? () => _sendCommand('test_fan') : null,
                ),
                _buildTestCard(
                  icon: Icons.volume_up_rounded,
                  label: 'BUZZER',
                  subtitle: widget.isConnected ? (_buzzerBusy ? 'Çalıyor...' : 'Hazır') : 'BAĞLANTI YOK',
                  isActive: _buzzerBusy,
                  activeColor: Colors.amberAccent,
                  onTap: (widget.isConnected && !_buzzerBusy) ? () => _sendCommand('test_buzzer') : null,
                ),
                _buildTestCard(
                  icon: Icons.whatshot_rounded,
                  label: 'ISITICI',
                  subtitle: widget.isConnected ? (_heaterOn ? 'AÇIK' : 'KAPALI') : 'BAĞLANTI YOK',
                  isActive: _heaterOn,
                  activeColor: Colors.redAccent,
                  onTap: widget.isConnected ? () => _sendCommand('test_heater') : null,
                ),
                _buildTestCard(
                  icon: Icons.lightbulb_rounded,
                  label: 'LED',
                  subtitle: widget.isConnected ? (_ledOn ? 'AÇIK' : 'KAPALI') : 'BAĞLANTI YOK',
                  isActive: _ledOn,
                  activeColor: Colors.greenAccent,
                  onTap: widget.isConnected ? () => _sendCommand('test_led') : null,
                ),
                _buildTestCard(
                  icon: Icons.thermostat_rounded,
                  label: 'NTC SENSÖR',
                  subtitle: widget.isConnected
                      ? (_ntcRead
                          ? '${_ntcTemp > -50 ? _ntcTemp.toStringAsFixed(1) : "--"} °C (ADC: $_ntcRaw)'
                          : 'Oku →')
                      : 'BAĞLANTI YOK',
                  isActive: _ntcRead && _ntcTemp > -50,
                  activeColor: Colors.purpleAccent,
                  onTap: widget.isConnected
                      ? () {
                          setState(() => _ntcRead = false);
                          _sendCommand('test_ntc');
                        }
                      : null,
                ),
                _buildTestCard(
                  icon: Icons.play_circle_filled_rounded,
                  label: 'TÜMÜNÜ TEST ET',
                  subtitle: widget.isConnected
                      ? (_testAllRunning ? 'Çalışıyor...' : 'Sıralı Test')
                      : 'BAĞLANTI YOK',
                  isActive: _testAllRunning,
                  activeColor: Colors.tealAccent,
                  onTap: (widget.isConnected && !_testAllRunning)
                      ? () => _sendCommand('test_all')
                      : null,
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Son durum bilgisi
            if (_lastResult.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C1C),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.terminal, size: 18, color: Colors.green),
                    const SizedBox(width: 10),
                    Text(
                      'Son Yanıt: $_lastResult',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTestCard({
    required IconData icon,
    required String label,
    required String subtitle,
    required bool isActive,
    required Color activeColor,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          color: isActive
              ? activeColor.withOpacity(0.12)
              : const Color(0xFF1C1C1C),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? activeColor.withOpacity(0.6) : Colors.grey.shade800,
            width: isActive ? 2 : 1,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: activeColor.withOpacity(0.2),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ]
              : [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive
                    ? activeColor.withOpacity(0.2)
                    : Colors.grey.shade900,
              ),
              child: Icon(
                icon,
                size: 32,
                color: isActive ? activeColor : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isActive ? Colors.white : Colors.grey.shade400,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: isActive ? activeColor : Colors.grey.shade600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
