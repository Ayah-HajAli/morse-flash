# Morse Flash

Type a message, your phone flashes it out in Morse code via the camera
flash. Point a second phone's camera at it, and it decodes the flashes
back into text live.

## What's included

```
lib/
  core/
    morse_table.dart       # Morse alphabet + reverse lookup
    morse_pulse.dart        # text -> timed on/off pulse sequence
    morse_transmitter.dart  # plays pulses out through the torch
    light_sampler.dart      # camera frame -> brightness value
    morse_decoder.dart      # brightness stream -> decoded text (the core logic)
  widgets/
    pulse_visualizer.dart   # animated dot/dash timeline (send screen)
    signal_meter.dart       # live brightness waveform (receive screen)
  screens/
    transmit_screen.dart
    receive_screen.dart
  theme.dart
  main.dart
scripts/
  setup.py                 # one-shot: copies source + patches permissions + pub get
pubspec.yaml
```

This is real, complete Dart/Flutter source — not pseudocode. I don't have
a Flutter SDK available in this sandbox to `flutter run` it myself, so
you'll want to build and test it on your machine/device. Below is
everything needed to get it running.

## Setup

**Fastest path: use the setup script.** It copies the source in, patches
the Android/iOS permission files, and runs `flutter pub get` for you —
one command instead of the manual copy/edit steps below.

1. **Scaffold the native project shell** (this only needs `android/`,
   `ios/`, etc. to match your installed toolchain — it always starts as
   Flutter's default counter-app template, that's normal):

   ```bash
   flutter create --org com.example morse_flash_app
   ```

2. **Run the setup script**, pointing it at that new project (adjust the
   path if `morse_flash_app` isn't a sibling folder of this one):

   ```bash
   python3 morse_flash/scripts/setup.py morse_flash_app
   ```

   This copies `lib/` and `pubspec.yaml` over the default template,
   inserts the camera/flashlight permission lines into
   `AndroidManifest.xml` and `Info.plist` (only if they're not already
   there — safe to re-run), and runs `flutter pub get`. You should see a
   `\u2713` line for each step.

3. **Run it — on a real phone, not a simulator.** Simulators have no
   camera or flash to test with.

   ```bash
   cd morse_flash_app
   flutter devices   # confirm a physical phone shows up in the list
   flutter run
   ```

<details>
<summary>Manual setup (if you'd rather not run the script, or it hits an error)</summary>

1. Copy this project's `lib/` folder and `pubspec.yaml` into the
   `flutter create`-generated project, replacing the defaults.
2. `flutter pub get`
3. Add permissions:

   **Android** — `android/app/src/main/AndroidManifest.xml`, inside `<manifest>`:

   ```xml
   <uses-permission android:name="android.permission.CAMERA"/>
   <uses-permission android:name="android.permission.FLASHLIGHT"/>
   ```

   **iOS** — `ios/Runner/Info.plist`, inside the top-level `<dict>`:

   ```xml
   <key>NSCameraUsageDescription</key>
   <string>Camera access is needed to receive Morse flashes from another phone.</string>
   ```

</details>



## Using it

- **Send**: type a message, optionally adjust speed, tap "Flash it."
  Hold the phone with its rear camera flash facing the other phone's
  camera, a foot or two apart, in a dim-ish room for best contrast.
- **Receive**: point the rear camera at the sending phone's flash.
  Center it in the on-screen box. Status will move from *"Point
  camera..."* → *"Signal found — syncing"* → *"Locked — decoding"* as it
  finds and locks onto the flash pattern.

There's also an **"Also flash the screen"** toggle on the Send screen —
useful for testing solo (flash the screen, film it with the same or a
second device) or as a fallback on devices where torch access misbehaves.

## How the decoding actually works

The interesting part isn't the Morse table — it's turning a noisy stream
of camera brightness values into reliable on/off timing. Roughly:

1. **`light_sampler.dart`** reads only a small, stride-sampled patch from
   the center of each camera frame and computes brightness — deliberately
   avoiding a full image decode, since this needs to run ~30x/second.
2. **`morse_decoder.dart`** keeps a slowly-decaying rolling min/max of
   recent brightness and sets the on/off threshold at their midpoint, so
   it self-adjusts to ambient light rather than using a fixed brightness
   cutoff.
3. Raw per-frame on/off readings are **debounced** (a couple of
   consecutive frames must agree) before being trusted, to ignore single-
   frame camera noise.
4. Before locking on, it looks for the **sync preamble** — three short,
   evenly-spaced flashes followed by a distinctly longer pause — the same
   shape `morse_pulse.dart` prepends to every outgoing message. Finding
   this both confirms "this really is a Morse signal" and calibrates the
   unit duration (dot length) for that specific transmission.
5. Once locked, subsequent on/off pulse durations are classified against
   that calibrated unit (dot vs. dash, intra-letter vs. inter-letter vs.
   word gap) and assembled into text via the reverse Morse table.
6. A long silence after at least one decoded letter flips the status to
   "message complete" and re-arms for the next sync.

## Tuning knobs / known limitations

- **Speed**: the send-screen slider maps to `unitMs` (80–300ms). Camera
  frame rate (usually ~30fps ≈ 33ms/frame) sets a practical floor —
  going much below ~100ms/unit will make dot/dash timing unreliable on
  most phones. 150ms is a safe default.
- **Torch latency**: some phones have tens-of-ms of lag toggling the
  torch. Because the receiver calibrates its unit length from the
  *actual* observed preamble rather than assuming the sender's requested
  timing, this is self-correcting rather than something you need to
  tune by hand.
- **Ambient light**: very bright rooms reduce contrast between "flash on"
  and "flash off." The adaptive threshold helps, but a dim room and
  keeping the two phones a foot or two apart works best.
- **Debounce vs. speed tradeoff**: `debounceSamples` in
  `MorseSignalDecoder` (default 2) trades noise rejection against
  reaction latency — raise it if you see garbled letters from camera
  flicker, lower it if fast messages get merged together.
- **One sender at a time**: the decoder assumes a single light source in
  frame. It'll get confused by other moving/blinking lights in view.
