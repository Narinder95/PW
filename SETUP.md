# Flutter Setup Guide for PW

## Prerequisites

### 1. Install Flutter SDK
- Download from: https://flutter.dev/docs/get-started/install/windows
- Extract to a location (e.g., `C:\src\flutter`)
- Add Flutter to PATH in your system environment variables

### 2. Verify Installation
```bash
flutter --version
dart --version
```

### 3. Install VS Code Extensions
1. Open VS Code
2. Go to Extensions (Ctrl+Shift+X)
3. Search and install:
   - **Flutter** (Dart Code)
   - **Dart** (Dart Code)

## Project Setup

### 1. Clone/Navigate to Project
```bash
cd C:\Users\narin\OneDrive\Desktop\PW
```

### 2. Get Dependencies
```bash
flutter pub get
```

### 3. Run the App

**On Android Emulator:**
```bash
flutter run
```

**On Physical Device:**
- Connect device via USB
- Enable Developer Mode
- Run: `flutter run`

**On iOS Simulator (Mac only):**
```bash
flutter run
```

## Development Workflow

### Hot Reload
Press `r` in the terminal while app is running to reload code changes instantly.

### Hot Restart
Press `R` to restart the app and reset state.

### Stop App
Press `q` to quit the app.

## Project Commands

```bash
# Get latest dependencies
flutter pub get

# Run analyzer
flutter analyze

# Run tests
flutter test

# Build APK (Android)
flutter build apk

# Build iOS app (Mac)
flutter build ios

# Clean build
flutter clean
```

## Folder Structure

- **lib/** - All Dart source code
- **lib/main.dart** - Entry point
- **lib/screens/** - Screen widgets
- **lib/widgets/** - Reusable components
- **lib/models/** - Data models
- **assets/** - Images, fonts, data files
- **test/** - Unit and widget tests
- **pubspec.yaml** - Dependencies & config

## Useful Links

- Flutter Docs: https://flutter.dev/docs
- Dart Language: https://dart.dev/guides
- Material Design 3: https://m3.material.io/
- Flutter Packages: https://pub.dev/

## Troubleshooting

### Device not detected
```bash
flutter devices
adb devices  # Check Android devices
```

### Dependencies issues
```bash
flutter clean
flutter pub get
```

### iOS build issues (Mac)
```bash
cd ios
pod install
cd ..
flutter clean
flutter run
```
