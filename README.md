# AiT Desk Control

A Flutter-based app for controlling AiT standing desks over Bluetooth.

## Overview

This app connects to AiT desks using Bluetooth and provides remote control features, including:

- Discovering AiT desk devices nearby
- Connecting securely over Bluetooth
- Controling desk motors, lights, audio and lock
- Flutter cross-platform support, tested on Android and web

## Features

- Bluetooth device scanning and pairing
- Desk height control with presets
- Drawer lock control
- Controling color of lights with rainbow effect
- Controlling audio settings
- Monitoring current and air quality sensors

## Getting Started

1. Install Flutter and set up your development environment:
   - https://docs.flutter.dev/get-started/install
2. Open the project in your IDE.
3. Run the app on a supported device with Bluetooth enabled.

## Run the App

From the project root:

```bash
flutter pub get
flutter run
```

## Notes

- The app is designed specifically for AiT desk models that support Bluetooth control.
- Web needs to be served with https to access bluetooth
- Desk lock can be secured using a pin but changing it is not supported currently

## Project Structure

- `lib/main.dart` — App entry point
- `pubspec.yaml` — Dependencies and Flutter configuration

## License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.
