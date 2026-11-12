// Shared, render-loop-friendly state between DOM sections and 3D scenes (no React re-renders).

/** Keys pressed by the hero's typing script: key id → time of press (ms). */
export const pressAt: Record<string, number> = {};

/** Colour of the hero's last result: 0 none, 1 paid, 2 blocked, 3 pending. */
export const heroMood = { value: 0, at: 0 };
