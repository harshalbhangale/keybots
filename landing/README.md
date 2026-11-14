# Keybots landing page

Vite + React, no 3D libraries.

```bash
cd landing
npm install
npm run dev      # http://localhost:5180
npm run build    # static site in landing/dist
```

- `src/Phone.tsx` draws a chat with the Keybots keyboard and plays the demo chats; you can hold or tap the bar's button.
- `src/scenarios.ts` holds the five chats. Each outcome matches a run recorded in the top-level README.
- `src/ui.tsx` has the download badges. `APK_URL` is a placeholder until the Keybots Android build is on S3.
