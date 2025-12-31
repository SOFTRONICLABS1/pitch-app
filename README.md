# pitch-app

Flutter port of the pitch detection web demo. The app listens to the microphone and runs the same Rust pitch
detectors (McLeod, autocorrelation, YIN) via FFI, showing either a scrolling timeline or a circular needle view.

## Rust algorithm bridge

The mobile app uses the same Rust algorithms from `pitch-detection` via FFI. Build the native library before running on device:

### Android
```bash
cd pitch-app/native/pitch_ffi
cargo install cargo-ndk             # one-time
cargo ndk -t arm64-v8a -t armeabi-v7a -t x86_64 \
  -o ../../android/app/src/main/jniLibs \
  build --release
```

### iOS
```bash
cd pitch-app/native/pitch_ffi
cargo install cargo-lipo            # one-time
cargo lipo --release
# Then add target/universal/release/libpitch_ffi.a to Xcode
# (Runner > Build Phases > Link Binary With Libraries) and ensure headers are exposed.
```

## Running it

```bash
cd pitch-app
flutter pub get
flutter run        # choose iOS or Android target
```

### Permissions

- Android: `RECORD_AUDIO` is already declared in the manifest.
- iOS: `NSMicrophoneUsageDescription` is set to "pitch-app needs microphone access to detect your pitch."

If audio never starts, make sure the microphone permission is granted in system settings.

## Controls

- Start/Stop: begins or ends microphone capture and pitch analysis.
- Detector: switch between McLeod and autocorrelation algorithms.
- Window size: 512/1024/2048/4096 samples (larger windows stabilize low notes).
- Clarity threshold: filters out noisy frames.
- Display: toggle between timeline and circle gauge views.
# pitch-app
