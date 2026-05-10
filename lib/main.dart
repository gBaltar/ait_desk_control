import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
//import 'package:flutter_blue_plus_windows/flutter_blue_plus_windows.dart';

class _ControlItem {
  final String label;
  final List<int> value;
  final String commandName;

  const _ControlItem(this.label, this.value, this.commandName);
}

class _ControlPlane {
  final String label;
  final List<_ControlItem> controls;

  const _ControlPlane(this.label, this.controls);
}

void main() => runApp(MaterialApp(home: ScanScreen()));

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  _ScanScreenState createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  List<ScanResult> scanResults = [];
  bool _isScanning = false;
  BuildContext? _context;

  void _startScan() async {
    print("Starting BLE scan...");
    if (!kIsWeb) {
      await FlutterBluePlus.startScan(timeout: Duration(seconds: 60), continuousUpdates: true, removeIfGone: Duration(seconds: 60));
    }
    else {
      await FlutterBluePlus.startScan(timeout: Duration(seconds: 60), continuousUpdates: true, removeIfGone: Duration(seconds: 60), webOptionalServices: [Guid.fromString("49535343-fe7d-4ae5-8fa9-9fafd205e455")]);
    }
  }

  void _openDevice(BluetoothDevice device) async {
    if (_isScanning) {
      await FlutterBluePlus.stopScan();
    }
    Navigator.push(
      _context!, 
      MaterialPageRoute(builder: (c) => AITScreen(device: device!))
    );
  }

  @override
  void initState() {
    super.initState();
      
    FlutterBluePlus.scanResults.listen((results) {
      setState(() => scanResults = results);
      for (var r in results) {
        debugPrint("Scan result: ${r.device.platformName} (${r.device.remoteId}) RSSI: ${r.rssi}");
        if (r.device.platformName.contains("AiT")) {
          _openDevice(r.device);
        }
      }
    });
  
    // Set up listener to handle timeout
    FlutterBluePlus.isScanning.listen((scanning) {
      setState(() => _isScanning = scanning );
    });

    if (!kIsWeb) {
      print("Starting BLE scan...");
      _startScan();
    }
    else {
      print("BLE scanning is must be trigggered manually on this platform.");
    }
  }

  @override
  void dispose() {
    print("Stopping BLE scan");
    FlutterBluePlus.stopScan(); // Safety net
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _context = context;
    return Scaffold(
      appBar: AppBar(title: _isScanning ? Text("Scanning for BLE devices") : Text("BLE devices") , actions: [
        IconButton(icon: Icon(Icons.refresh), onPressed: _startScan)
      ]),
      body: ListView.builder(
        itemCount: scanResults.length,
        itemBuilder: (c, i) => ListTile(
          title: Text(scanResults[i].device.platformName.isNotEmpty 
            ? scanResults[i].device.platformName
            : "Unknown Device"),
          subtitle: Text(scanResults[i].device.remoteId.toString()),
          onTap: () async {
            _openDevice(scanResults[i].device);
          }
        ),
      ),
    );
  }
}

class AITScreen extends StatefulWidget {
  final BluetoothDevice device;
  const AITScreen({super.key, required this.device});

  @override
  State<AITScreen> createState() => _AITScreenState();
}

class _AITScreenState extends State<AITScreen> {
  BluetoothCharacteristic? char_notify;
  BluetoothCharacteristic? char_write;
  late StreamSubscription<BluetoothConnectionState> _connectionSubscription;
  StreamSubscription? _lastValueSubscription;
  final TextEditingController _controller = TextEditingController();
  List<String> _logs = [];
  late ScrollController _logScroller;

  List<int> _volume = [50, 0, 100];
  List<int> _treble = [0, -6, 6];
  List<int> _mid = [0, -6, 6];
  List<int> _bass = [0, -6, 6];
  List<int> _mute = [0, 0, 1];

  List<int> _rgb_r = [0, 0, 100];
  List<int> _rgb_g = [0, 0, 100];
  List<int> _rgb_b = [0, 0, 100];
  
  List<int> _drawer = [0, 0, 1];
  List<int> _move = [0, -1, 1];
  List<int> _preset_1 = [0, 0, 547];
  List<int> _preset_2 = [0, 0, 547];
  List<int> _preset_3 = [0, 0, 547];
  List<int> _height = [0, 0, 547];
  
  List<int> _airlim = [500, 0, 1000];
  List<int> _air = [500, 0, 1000];
  List<int> _current = [0, -1000, 1000];

  int _selectedPlaneIndex = 0;
  late final List<_ControlPlane> _planes = [
    _ControlPlane('Audio', [
      _ControlItem('Volume', _volume, 'set_vol'),
      _ControlItem('Bass', _bass, 'set_bass'),
      _ControlItem('Mid', _mid, 'set_mid'),
      _ControlItem('Treble', _treble, 'set_treb'),
      _ControlItem('Mute', _mute, 'set_Mute'),
    ]),
    _ControlPlane('Lights', [
      _ControlItem('R', _rgb_r, 'set_rgb_r'),
      _ControlItem('G', _rgb_g, 'set_rgb_g'),
      _ControlItem('B', _rgb_b, 'set_rgb_b'),
    ]),
    _ControlPlane('Motion', [
      _ControlItem('Drawer', _drawer, 'set_drawer'),
      _ControlItem('Height', _height, 'set_height'),
      _ControlItem('Move', _move, 'set_move'),
      _ControlItem('Preset 1', _preset_1, 'set_preset_1'),
      _ControlItem('Preset 2', _preset_2, 'set_preset_2'),
      _ControlItem('Preset 3', _preset_3, 'set_preset_3'),
    ]),
    _ControlPlane('Sensors', [
      _ControlItem('Air Limit', _airlim, 'set_airlim'),
      _ControlItem('Air', _air, 'get_air'),
      _ControlItem('Current', _current, 'get_current'),
    ]),
  ];

  @override
  void initState() {
    super.initState();
    _logScroller = ScrollController();
    
    _connectionSubscription = widget.device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.connected) {
        _onDiscoverServices();
      }
    });

    if (widget.device.isDisconnected) {
      debugPrint("Attempting to connect to device...");
      widget.device.connect(timeout: const Duration(seconds: 5), license: License.free).catchError((e) {
        debugPrint("Initial connection failed: $e");
      });
    }
    else {
      _onDiscoverServices();
    }
  }

  @override
  void dispose() {
    debugPrint("Disconnecting from device...");
    _logScroller.dispose();
    _connectionSubscription.cancel();
    _lastValueSubscription?.cancel();
    widget.device.disconnect();
    super.dispose();
  }

  void _addLog(String message) {
    setState(() => _logs.add(message));
    _logScroller.animateTo(
      _logScroller.position.maxScrollExtent,
      duration: Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Future<void> _onDiscoverServices() async {
    try {      
      List<BluetoothService> services = await widget.device.discoverServices();
      for (var s in services) {
        debugPrint("Discovered service: ${s.serviceUuid.str} ${s.uuid}");
        for (var c in s.characteristics) {
          debugPrint("  Char: ${c.uuid.str} Props: ${c.properties.toString()}");
          if (c.characteristicUuid.str == "49535343-1e4d-4bd9-ba61-23c647249616") {
            debugPrint("    -> Found notify characteristic!");
            char_notify = c;
          }  else if (c.characteristicUuid.str == "49535343-8841-43f4-a8d4-ecbe34729bb3") {
            debugPrint("    -> Found write characteristic!");
            char_write = c;
          }
        }
      }
    } catch (e) {
      // This catches the 'device is not connected' error specifically
      debugPrint("Discovery Error: $e");
    }

    if (char_notify != null && char_write != null) {
      try {
        await char_notify!.setNotifyValue(true);
        
        _lastValueSubscription = char_notify!.onValueReceived.listen((value) {
          final String hex = value.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
          final String text = utf8.decode(value, allowMalformed: true).trim();
          _parseNotifyResponse(text);
          _addLog("RX: $text ($hex)");
        });

        sendCommand('get_Mute|#');
        sendCommand('get_vol|#');
        sendCommand('get_treb|#');
        sendCommand('get_mid|#');
        sendCommand('get_bass|#');
        sendCommand('get_rgb|#');
        sendCommand('get_airlim|#');
        sendCommand('get_height|#');
        sendCommand('get_preset|#');
        //sendCommand('get_drawer|#'); always returns 0, so we can skip this one
        sendCommand('get_air|#');
        sendCommand('get_current|#');
      } catch (e) {
        _addLog("Error setting notifications: $e");
      }
    }
    else {
      debugPrint("Required characteristics not found. This device may not be compatible.");
    }
  }

  void sendCommand(String input) async {
    input = input.replaceAll("\\n", "\n").replaceAll("\\r", "\r");
    
    try {
      List<int> bytes = utf8.encode(input);
      
      // Determine write type automatically or pick one
      await char_write!.write(bytes, withoutResponse: char_write!.properties.writeWithoutResponse);
      _addLog("TX: $input");
    } catch (e) {
      _addLog("Send Error: $e");
    }
  }

  void _sendControlCommand(String name, int value) async {
    String command = '$name|$value#';
    if (name == 'set_drawer') {
      _drawer[0] = value;
      command = 'set_drawer|${_drawer[0]}|0000#';
    } else if (name == 'set_airlim') {
      _airlim[0] = value;
    } else if (name == 'set_vol') {
      _volume[0] = value;
    } else if (name == 'set_treb') {
      _treble[0] = value;
    } else if (name == 'set_mid') {
      _mid[0] = value;
    } else if (name == 'set_bass') {
      _bass[0] = value;
    } else if (name == 'set_move') {
      _move[0] = 0;
      if (value > 0) {
        command = '$name|1#';
      } else if (value < 0) {
        command = '$name|2#';
      }
    } else if (name == 'set_height') {
      _height[0] = value;
    } else if (name == 'set_rgb_r') {
      _rgb_r[0] = value;
      command = 'set_rgb|${_rgb_r[0]}|${_rgb_g[0]}|${_rgb_b[0]}#';
    } else if (name == 'set_rgb_g') {
      _rgb_g[0] = value;
      command = 'set_rgb|${_rgb_r[0]}|${_rgb_g[0]}|${_rgb_b[0]}#';
    } else if (name == 'set_rgb_b') {
      _rgb_b[0] = value;
      command = 'set_rgb|${_rgb_r[0]}|${_rgb_g[0]}|${_rgb_b[0]}#';
    } else if (name == 'set_preset_1') {
      _preset_1[0] = value;
      command = 'set_preset|${_preset_1[0]}|${_preset_2[0]}|${_preset_3[0]}#';
    } else if (name == 'set_preset_2') {
      _preset_2[0] = value;
      command = 'set_preset|${_preset_1[0]}|${_preset_2[0]}|${_preset_3[0]}#';
    } else if (name == 'set_preset_3') {
      _preset_3[0] = value;
      command = 'set_preset|${_preset_1[0]}|${_preset_2[0]}|${_preset_3[0]}#';
    }

    try {
      if (char_write != null) {
        await char_write!.write(utf8.encode(command), withoutResponse: char_write!.properties.writeWithoutResponse);
        _addLog('TX: $command');
      } else {
        _addLog('No connected device or write characteristic not found');
      }
    } catch (e) {
      _addLog('Audio send error: $e');
    }
  }

  void _parseNotifyResponse(String response) {
    // Expected response examples:
    //   set_vol|50#
    //   set_treb|60#
    //   set_mid|60#
    //   set_bass|40#
    final normalized = response.trim();
    if (normalized.isEmpty) return;

    int? parsedValue;
    if (normalized.contains('|') && normalized.endsWith('#')) {
      final parts = normalized.substring(0, normalized.length - 1).split('|');
      final field = parts[0];
      if (parts.length == 2) {
        if (parts[1] == 'OK' || parts[1] == '?') {
          if (field == 'set_airlim') {
            sendCommand('get_airlim|#');
          } else if (field == 'set_vol') {
            sendCommand('get_vol|#');
          } else if (field == 'set_treb') {
            sendCommand('get_treb|#');
          } else if (field == 'set_mid') {
            sendCommand('get_mid|#');
          } else if (field == 'set_bass') {
            sendCommand('get_bass|#');
          } else if (field == 'set_rgb') {
            sendCommand('get_rgb|#');
          } else if (field == 'set_preset') {
            sendCommand('get_preset|#');
          } else if (field == 'set_drawer') {
            //sendCommand('get_drawer|#');
          }
        }
        else {
          parsedValue = int.tryParse(parts[1]);
          debugPrint("Parsed ${field}: ${parsedValue}");
          if (parsedValue != null) {
            if (field == 'get_airlim') {
              setState(() => _airlim[0] = parsedValue!.clamp(_airlim[1], _airlim[2]));
            } else if (field == 'get_vol') {
              setState(() => _volume[0] = parsedValue!.clamp(_volume[1], _volume[2]));
            } else if (field == 'get_treb') {
              setState(() => _treble[0] = parsedValue!.clamp(_treble[1], _treble[2]));
            } else if (field == 'get_mid') {
              setState(() => _mid[0] = parsedValue!.clamp(_mid[1], _mid[2]));
            } else if (field == 'get_bass') {
              setState(() => _bass[0] = parsedValue!.clamp(_bass[1], _bass[2]));
            } else if (field == 'get_height') {
              setState(() => _height[0] = parsedValue!.clamp(_height[1], _height[2]));
            } else if (field == 'get_drawer') {
              //setState(() => _drawer[0] = 1 - parsedValue!.clamp(_drawer[1], _drawer[2]));
            } else if (field == 'set_move') {
              sendCommand('get_height|#');
            } else if (field == 'get_Mute') {
              setState(() => _mute[0] = parsedValue!.clamp(_mute[1], _mute[2]));
            }
          }
        }
      } else if (parts.length == 3) {
        if (field == 'get_current') {
          setState(() => _current[0] = parsedValue!.clamp(_current[1], _current[2]));
        }
      } else if (parts.length == 4) {
        final p1 = int.tryParse(parts[1]);
        final p2 = int.tryParse(parts[2]);
        final p3 = int.tryParse(parts[3]);
        if (p1 != null && p2 != null && p3 != null) {
          if (field == 'get_rgb') {
            setState(() {
              _rgb_r[0] = p1.clamp(_rgb_r[1], _rgb_r[2]);
              _rgb_g[0] = p2.clamp(_rgb_g[1], _rgb_g[2]);
              _rgb_b[0] = p3.clamp(_rgb_b[1], _rgb_b[2]);
            });
          } else if (field == 'get_preset') {
            setState(() {
              _preset_1[0] = p1.clamp(_preset_1[1], _preset_1[2]);
              _preset_2[0] = p2.clamp(_preset_2[1], _preset_2[2]);
              _preset_3[0] = p3.clamp(_preset_3[1], _preset_3[2]);
            });
          }
        }
      } else if (parts.length == 5) {
        if (field == 'get_air') {
          setState(() => _air[0] = parsedValue!.clamp(_air[1], _air[2]));
        }
      }
    }
    else {
      if (normalized.contains('|')) {
        final parts = normalized.substring(0, normalized.length - 1).split('|');
        final field = parts[0];
         if (parts.length == 2) {
          if (field == 'mute_bt') {
            sendCommand('get_Mute|#');
          } else {
            debugPrint("Received unrecognized control message: $normalized");
          }
        } else {
          debugPrint("Received unrecognized control message: $normalized");
        }
      }
      else if (normalized == 'wellness_bt') {
        debugPrint("Received wellness button event");
      } else {
        debugPrint("Received non-control message");
      }
    }
  }

  Widget _buildPlaneSelector() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(_planes.length, (index) {
          final plane = _planes[index];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(plane.label),
              selected: _selectedPlaneIndex == index,
              onSelected: (_) => setState(() => _selectedPlaneIndex = index),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildPlaneControls() {
    final plane = _planes[_selectedPlaneIndex];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: plane.controls
          .map((item) => _buildAudioSlider(item.label, item.value, (value) => _sendControlCommand(item.commandName, value)))
          .toList(),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Terminal")),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPlaneSelector(),
                SizedBox(height: 10),
                _buildPlaneControls(),
              ],
            ),
          ),
          Expanded(child: ListView.builder(
            controller: _logScroller,
            itemCount: _logs.length,
            itemBuilder: (c, i) => Padding(
              padding: EdgeInsets.all(8),
              child: Text(_logs[i], style: TextStyle(fontFamily: 'monospace')),
            ),
          )),
          Padding(
            padding: EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(child: TextField(controller: _controller, decoration: InputDecoration(hintText: "e.g. get_height|#\\n"))),
                IconButton(icon: Icon(Icons.send), onPressed: () => sendCommand(_controller.text)),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildAudioSlider(String label, List<int> value, ValueChanged<int> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label),
              Text(value[0].toString(), style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          Slider(
            value: value[0].toDouble(),
            min: value[1].toDouble(),
            max: value[2].toDouble(),
            divisions: value[2] - value[1] + 1,
            label: value.toString(),
            onChanged: (double newValue) {}, // Disable direct dragging to prevent desync with device state
            onChangeEnd: (double newValue) => onChanged(newValue.round()),
          ),
        ],
      ),
    );
  }
}
