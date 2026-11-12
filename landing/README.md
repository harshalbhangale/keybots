# AIRKEY landing page

Vite + React + React Three Fiber.

```bash
cd landing
npm install
npm run dev      # http://localhost:5180
npm run build    # static site in landing/dist
```

- `src/three/` — the 3D scenes: the typing keyboard (hero), the leash with its agents and payments (lab), the keycap (closing).
- `src/lib/leash.ts` — a browser copy of the leash's decision order (RULES.md) that drives the "Try the leash" panel. It runs locally; the real decisions are on NEAR testnet and linked in the Testnet section.
- Home and keyboard images are screenshots from `docs/screens/`; the Leash phone screen is drawn for the page.
