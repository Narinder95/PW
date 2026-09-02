# PW - Mobile App

Cross-platform mobile app built with Flutter (Android & iOS).

## Project Structure

```
PW/
├── lib/               # Dart source code
│   ├── main.dart      # App entry point
│   ├── screens/       # Screen widgets
│   ├── widgets/       # Reusable widgets
│   ├── models/        # Data models
│   └── utils/         # Utilities
├── assets/            # Images, fonts, etc.
├── pubspec.yaml       # Dependencies & configuration
└── docs/              # Project documentation
```

## Setup

1. **Install Flutter**: https://flutter.dev/docs/get-started/install
2. **Open in VS Code** and install Flutter extension
3. **Run**:
   ```bash
   flutter pub get
   flutter run
   ```

## Tech Stack

- **Framework**: Flutter (Dart)
- **UI**: Material Design 3
- **Platforms**: Android & iOS (single codebase)
- **Editor**: VS Code

## Features

✓ Bottom navigation with 3 tabs (Journal, Journey, Profile)
✓ Material 3 design system
✓ Cross-platform support

## Next Steps

- [ ] Implement Journal screen
- [ ] Implement Journey screen  
- [ ] Implement Profile screen
- [ ] Add data persistence
- [ ] Firebase integration
