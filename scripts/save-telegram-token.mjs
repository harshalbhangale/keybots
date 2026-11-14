// Saves the Telegram bot token to keys/telegram.token (gitignored, 0600) without it
// appearing on screen or in chat, and prints only the bot's public username.
//   AIRKEY_KEYS_DIR=/path/to/keys node save-telegram-token.mjs
import { writeFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import { KEYS_DIR } from "./common.mjs";

function askHidden(prompt) {
  return new Promise((resolve) => {
    process.stdout.write(prompt);
    const stdin = process.stdin;
    stdin.setRawMode?.(true);
    stdin.resume();
    let s = "";
    stdin.on("data", (b) => {
      for (const ch of b.toString("utf8")) {
        if (ch === "\r" || ch === "\n") {
          stdin.setRawMode?.(false);
          stdin.pause();
          process.stdout.write("\n");
          return resolve(s.trim());
        }
        if (ch === "\u0003") process.exit(1);
        if (ch === "\u007f") s = s.slice(0, -1);
        else s += ch;
      }
    });
  });
}

const token = await askHidden("Paste the bot token from BotFather (hidden), then Enter: ");
if (!/^\d+:[A-Za-z0-9_-]{30,}$/.test(token)) {
  console.error("That doesn't look like a Telegram bot token (it looks like 123456789:ABC...). Nothing was saved.");
  process.exit(1);
}
const me = await fetch(`https://api.telegram.org/bot${token}/getMe`).then((r) => r.json()).catch(() => null);
if (!me?.ok) {
  console.error("Telegram didn't accept that token. Nothing was saved.");
  process.exit(1);
}
mkdirSync(KEYS_DIR, { recursive: true });
writeFileSync(join(KEYS_DIR, "telegram.token"), token + "\n", { mode: 0o600 });
console.log(`Saved. Bot: @${me.result.username} (${me.result.first_name}). Privacy mode: ${me.result.can_read_all_group_messages ? "off (it can read group messages)" : "ON. In BotFather send /setprivacy, pick the bot, choose Disable"}.`);
