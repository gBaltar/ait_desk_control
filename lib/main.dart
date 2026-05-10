import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
//import 'package:flutter_blue_plus_windows/flutter_blue_plus_windows.dart';

void main() => runApp(MaterialApp(home: ScanScreen()));

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  _ScanScreenState createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  List<ScanResult> scanResults = [];
  bool _isScanning = false;

  void startScan() async {
    print("Starting BLE scan...");
    if (!kIsWeb) {
      await FlutterBluePlus.startScan(timeout: Duration(seconds: 60), continuousUpdates: true, removeIfGone: Duration(seconds: 60));
    }
    else {
      await FlutterBluePlus.startScan(timeout: Duration(seconds: 60), continuousUpdates: true, removeIfGone: Duration(seconds: 60), webOptionalServices: [Guid.fromString("49535343-fe7d-4ae5-8fa9-9fafd205e455")]);
    }
  }
  @override
  void initState() {
    super.initState();
      
    FlutterBluePlus.scanResults.listen((results) {
      setState(() => scanResults = results);
    });
  
    // Set up listener to handle timeout
    FlutterBluePlus.isScanning.listen((scanning) {
      setState(() => _isScanning = scanning );
    });

    if (!kIsWeb) {
      print("Starting BLE scan...");
      startScan();
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
    return Scaffold(
      appBar: AppBar(title: _isScanning ? Text("Scanning for BLE devices") : Text("BLE devices") , actions: [
        IconButton(icon: Icon(Icons.refresh), onPressed: startScan)
      ]),
      body: ListView.builder(
        itemCount: scanResults.length,
        itemBuilder: (c, i) => ListTile(
          title: Text(scanResults[i].device.platformName.isNotEmpty 
            ? scanResults[i].device.platformName
            : "Unknown Device"),
          subtitle: Text(scanResults[i].device.remoteId.toString()),
          onTap: () async {
            if (_isScanning) {
              await FlutterBluePlus.stopScan();
            }
            Navigator.push(
              context, 
              MaterialPageRoute(builder: (c) => AITScreen(device: scanResults[i].device))
            );
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
  final TextEditingController _controller = TextEditingController();
  List<String> logs = [];
  StreamSubscription? _lastValueSubscription;

  @override
  void initState() {
    super.initState();

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
    _connectionSubscription.cancel();
    _lastValueSubscription?.cancel();
    widget.device.disconnect();
    super.dispose();
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
          setState(() {
            String hex = value.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
            String text = utf8.decode(value, allowMalformed: true);
            logs.add("RX: $text\n($hex)");
          });
        });
      } catch (e) {
        setState(() => logs.add("Error setting notifications: $e"));
      }
    }
    else {
      debugPrint("Required characteristics not found. This device may not be compatible.");
    }
  }

  void sendCommand() async {
    String input = _controller.text;
    input = input.replaceAll("\\n", "\n").replaceAll("\\r", "\r");
    
    try {
      List<int> bytes = utf8.encode(input);
      
      // Determine write type automatically or pick one
      await char_write!.write(bytes, withoutResponse: char_write!.properties.writeWithoutResponse);
      setState(() => logs.add("TX: $input"));
    } catch (e) {
      setState(() => logs.add(" Send Error: $e"));
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Terminal")),
      body: Column(
        children: [
          Expanded(child: ListView.builder(
            itemCount: logs.length,
            itemBuilder: (c, i) => Padding(
              padding: EdgeInsets.all(8),
              child: Text(logs[i], style: TextStyle(fontFamily: 'monospace')),
            ),
          )),
          Padding(
            padding: EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(child: TextField(controller: _controller, decoration: InputDecoration(hintText: "e.g. get_height|#\\n"))),
                IconButton(icon: Icon(Icons.send), onPressed: sendCommand),
              ],
            ),
          )
        ],
      ),
    );
  }
}

class DeviceScreen extends StatefulWidget {
  final BluetoothDevice device;
  const DeviceScreen({super.key, required this.device});

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  List<BluetoothService> _services = [];
  late StreamSubscription<BluetoothConnectionState> _connectionSubscription;

  @override
  void initState() {
    super.initState();

    _connectionSubscription = widget.device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.connected) {
        _onDiscoverServices();
      }
      setState(() {}); // Rebuild to update connection icon
    });

    if (widget.device.isDisconnected) {
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
    _connectionSubscription.cancel();
    widget.device.disconnect();
    super.dispose();
  }

  Future<void> _onDiscoverServices() async {
    try {      
      List<BluetoothService> services = await widget.device.discoverServices();

      Future.delayed(Duration(milliseconds: 2000));
      services = widget.device.servicesList;
      setState(() {
        _services = services;
        for (var s in services) {
          debugPrint("Discovered service: ${s.serviceUuid.str} ${s.uuid} ${s.characteristics.toString()}");
        }
      });
    } catch (e) {
      // This catches the 'device is not connected' error specifically
      debugPrint("Discovery Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isConnected = widget.device.isConnected;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.device.platformName),
        actions: [
          Icon(
            isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
            color: isConnected ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _onDiscoverServices,
        child: ListView(
          children: _services.map((s) => _buildServiceTile(s)).toList(),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _onDiscoverServices,
        child: const Icon(Icons.search),
      ),
    );
  }

  Widget _buildServiceTile(BluetoothService s) {
    return ExpansionTile(
      title: Text("Service: ${s.uuid.str.toUpperCase()}"),
      children: s.characteristics.map((c) => ListTile(
        title: Text("Char: ${c.uuid.str.toUpperCase()} ${c.properties.toString()}"),
        subtitle: const Text("Tap to open terminal"),
        onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (context) => TerminalScreen(char: c))),
      )).toList(),
    );
  }
}

class TerminalScreen extends StatefulWidget {
  final BluetoothCharacteristic char;
  const TerminalScreen({super.key, required this.char});

  @override
  _TerminalScreenState createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  final TextEditingController _controller = TextEditingController();
  List<String> logs = [];
  StreamSubscription? _lastValueSubscription;

  @override
  void initState() {
    super.initState();
    print("${widget.char.toString()}");
    // 1. Check if the characteristic supports notifications
    if (widget.char.properties.notify || widget.char.properties.indicate) {
      _setupNotifications();
    } else {
      logs.add("System: This characteristic does not support notifications.");
    }
  }

  void _setupNotifications() async {
    try {
      await widget.char.setNotifyValue(true);
      
      _lastValueSubscription = widget.char.onValueReceived.listen((value) {
        if (!mounted) return;
        setState(() {
          String hex = value.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
          String text = utf8.decode(value, allowMalformed: true);
          logs.add("RX: $text\n($hex)");
        });
      });
    } catch (e) {
      setState(() => logs.add("Error setting notifications: $e"));
    }
  }

  @override
  void dispose() {
    _lastValueSubscription?.cancel();
    // It's good practice to turn off notifications when leaving
    widget.char.setNotifyValue(false); 
    super.dispose();
  }

  void sendCommand() async {
    if (!widget.char.properties.write && !widget.char.properties.writeWithoutResponse) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("This characteristic is Read-Only"))
      );
      return;
    }

    String input = _controller.text;
    input = input.replaceAll("\\n", "\n").replaceAll("\\r", "\r");
    
    try {
      List<int> bytes = utf8.encode(input);
      
      // Determine write type automatically or pick one
      await widget.char.write(bytes, withoutResponse: widget.char.properties.writeWithoutResponse);
      
      setState(() => logs.add("TX: $input"));

      if (widget.char.properties.read) {
        List<int> response = await widget.char.read(timeout: 1);
        setState(() => logs.add("RX: ${response.toString()} : ${utf8.decode(response)}"));
      }

      _controller.clear();
    } catch (e) {
      setState(() => logs.add("Send Error: $e"));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Terminal")),
      body: Column(
        children: [
          Expanded(child: ListView.builder(
            itemCount: logs.length,
            itemBuilder: (c, i) => Padding(
              padding: EdgeInsets.all(8),
              child: Text(logs[i], style: TextStyle(fontFamily: 'monospace')),
            ),
          )),
          Padding(
            padding: EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(child: TextField(controller: _controller, decoration: InputDecoration(hintText: "e.g. get_height|#\\n"))),
                IconButton(icon: Icon(Icons.send), onPressed: sendCommand),
              ],
            ),
          )
        ],
      ),
    );
  }
}