# Keybots for Android (preview)

A small Android version of the Keybots keyboard, built from the iOS app's design.

What it does:
- A full keyboard (numbers, letters, shift, delete, return) in the Keybots look, with the PAY / TRADE / FOLLOW / CHECK tabs.
- When the line you type reads like a command (`pay alex 0.4`, `swap 1 near`, or a scam such as `send 5 near to drain.near`), the strip above the keys turns into a card. Hold its button and the keyboard checks the same limits as the iOS app: 0.5 NEAR a payment, 1 NEAR a trade.
- A setup screen: turn the keyboard on, pick it, try it.

What it does not do: it does not sign or send anything. Payments, swaps and Face ID approvals run in the Keybots iOS app on NEAR testnet.

Build (no Gradle; needs the Android SDK with build-tools 35.0.0 and platform android-36, and JDK 17):

```bash
./android/build.sh
```

The APK lands in `android/build/keybots.apk`. Copy it to `landing/public/keybots.apk` to update the site's download button. The signing key (`android/keybots-preview.jks`) is made on first build and kept out of git.

Tested on an Android emulator (API 36): installs, the keyboard can be enabled and picked, typing `pay alex 0.4` shows the PAY card, and holding it shows the limits check.
