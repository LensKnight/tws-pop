<div align="center">
  <img src="assets/app_icon.png" width="140" alt="TWS POP Logo">

  <p><strong>Smart Earbud Popups for Android</strong></p>
</div>

<div align="center">
  <h1>TWS POP</h1>
  <p><strong>Smart Earbud Popups for Android</strong></p>
  <p>A device-aware popup experience for headphones and earbuds.</p>

  ![Flutter](https://img.shields.io/badge/Flutter-Framework-02569B?logo=flutter&logoColor=white)
  ![Android](https://img.shields.io/badge/Platform-Android-3DDC84?logo=android&logoColor=white)
  ![License](https://img.shields.io/badge/License-MIT-white)
  [![Latest Release](https://img.shields.io/github/v/release/LensKnight/tws-pop)](https://github.com/LensKnight/tws-pop/releases)
</div>

---


# TWS POP

**A device-aware popup experience for headphones and earbuds on Android.**

TWS POP is an Android application designed to provide a personalized popup experience when supported headphones and earbuds connect. It combines device-specific artwork, floating animations, and custom video playback.

---

## Overview

TWS POP makes connecting headphones and earbuds more personalized through dedicated visuals and device-specific popup experiences.

## Features

- **Device Detection** — Identifies supported headphone and earbud models.
- **Custom Visuals** — Displays device-specific artwork.
- **Floating Animations** — Adds subtle motion to device artwork.
- **Video Playback** — Supports dedicated popup videos for selected devices.
- **Default Experience** — Provides a fallback popup for other devices.

## Supported Devices

| Device | Popup Experience |
|---|---|
| boAt Airdopes 219 | Custom video |
| OnePlus Nord Buds | Dedicated video |
| Sony WH-CH720N | Headphone artwork |
| Other devices | Default popup |

*Feature availability depends on the device name reported by Android and the current implementation.*

## Installation

1. Visit the [GitHub Releases](https://github.com/LensKnight/tws-pop/releases) page.
2. Download `TWS_POP.apk` from the latest release.
3. Open the downloaded APK on your Android device.
4. Allow installation from the source if Android prompts you.
5. Complete installation and launch TWS POP.

Only install APK files from sources you trust.

## Development Setup

### Requirements

- Flutter SDK
- Android SDK and build tools
- JDK compatible with the project's Android Gradle configuration
- Git

### Clone the Repository

```bash
git clone https://github.com/LensKnight/tws-pop.git
cd tws-pop
```

### Install Dependencies

```bash
flutter pub get
```

### Run the Application

```bash
flutter run
```

### Build a Release APK

```bash
flutter build apk --release
```

The generated APK will be available at:

```text
build/app/outputs/flutter-apk/app-release.apk
```

## Project Structure

```text
tws-pop/
├── android/
│   └── app/
│       └── src/main/
│           ├── assets/
│           ├── kotlin/
│           └── res/
├── lib/
│   └── main.dart
├── assets/
├── pubspec.yaml
└── README.md
```

## Releases and Updates

Official APK releases are available on the [GitHub Releases](https://github.com/LensKnight/tws-pop/releases) page.

To update the application, download the latest APK and install it over the existing version. Android may ask you to confirm the installation.

## Contributing

Suggestions, bug reports, and contributions are welcome.

When reporting an issue, include:

- Your Android device model
- Your headphone or earbud model
- The steps required to reproduce the issue
- Any relevant error messages

## License

TWS POP is licensed under the [MIT License](LICENSE).

You are free to use, copy, modify, merge, publish, distribute, sublicense, and sell copies of the software, subject to the license terms.

---

**TWS POP**  
*Personalized audio-device experiences for Android.*
