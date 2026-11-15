# Keybots for Android

The Keybots keyboard for Android, built from the iOS app's design. **Download:** [keybots.apk](https://github.com/harshalbhangale/keybots/releases/latest/download/keybots.apk) (latest release).

What it does:
- A full keyboard (numbers, letters, shift, delete, return) in the Keybots look, with the PAY / TRADE / FOLLOW / CHECK tabs.
- When the line you type reads like a command (`pay alex 0.4`, `swap 1 near`, or a scam such as `send 5 near to drain.near`), the strip above the keys turns into a card. Hold its button and the keyboard checks the same limits as the iOS app: 0.5 NEAR a payment, 1 NEAR a trade.
- A setup screen: turn the keyboard on, pick it, try it.

- **Connected to your bots** (new in 0.2): paste your Keybots server key once in the app (card 3), pick Testnet or Mainnet, and holding a card sends the command to your Keybots server. Your agents ask the Spend Limits contract on NEAR, and the strip shows what came back: paid, swapped, refused on chain, or waiting for you (with the transaction).
- Tap the mascot key for your bots and balance, from the server.
- Pasted text is read too, so a copied scam turns into a check card.

The key is kept on the phone; nothing is built into the APK. Someone new still waits for your approval with Face ID in the Keybots iOS app. Not connected yet, it checks the limits on the phone only and says so.

Build (no Gradle; needs the Android SDK with build-tools 35.0.0 and platform android-36, and JDK 17):

```bash
./android/build.sh
```

The APK lands in `android/build/keybots.apk`. Copy it to `landing/public/keybots.apk` to update the site's download button. The signing key (`android/keybots-preview.jks`) is made on first build and kept out of git.

Tested on an Android emulator (API 36): installs, the keyboard can be enabled and picked, typing `pay alex 0.4` shows the PAY card, and holding it shows the limits check.
