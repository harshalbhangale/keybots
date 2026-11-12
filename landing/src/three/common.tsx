import { Environment, Lightformer } from "@react-three/drei";
import { useMemo } from "react";
import * as THREE from "three";

export const LIME = new THREE.Color("#c6f25a");
export const AMBER = new THREE.Color("#f5b841");
export const RED = new THREE.Color("#ff5a52");

/** Studio lighting built from light-formers, so nothing is fetched from a CDN. */
export function Studio({ intensity = 1, tint = "#c6f25a" }: { intensity?: number; tint?: string }) {
  return (
    <Environment resolution={256} frames={1}>
      <group rotation={[-Math.PI / 3, 0, 1]}>
        <Lightformer form="circle" intensity={4 * intensity} rotation-x={Math.PI / 2} position={[0, 5, -9]} scale={2} />
        <Lightformer form="circle" intensity={2 * intensity} rotation-y={Math.PI / 2} position={[-5, 1, -1]} scale={2} />
        <Lightformer form="circle" intensity={2 * intensity} rotation-y={Math.PI / 2} position={[-5, -1, -1]} scale={2} />
        <Lightformer form="circle" intensity={2 * intensity} rotation-y={-Math.PI / 2} position={[10, 1, 0]} scale={8} />
        <Lightformer form="ring" color={tint} intensity={2.5 * intensity} onUpdate={(self) => self.lookAt(0, 0, 0)} position={[10, 10, 0]} scale={10} />
      </group>
    </Environment>
  );
}

/** A canvas texture with a centred label, sized for a key `w` units wide. */
export function useLabel(label: string, w = 1, opts: { color?: string; weight?: number; size?: number; spacing?: number } = {}) {
  return useMemo(() => {
    const { color = "#f2f0ea", weight = 500, size, spacing = 0 } = opts;
    const c = document.createElement("canvas");
    c.width = Math.round(256 * w);
    c.height = 256;
    const g = c.getContext("2d")!;
    g.fillStyle = color;
    g.textAlign = "center";
    g.textBaseline = "middle";
    const fs = size ?? (label.length > 3 ? 64 : label.length > 1 ? 80 : 124);
    g.font = `${weight} ${fs}px "Inter Tight", -apple-system, "Helvetica Neue", Arial, sans-serif`;
    if (spacing) (g as CanvasRenderingContext2D & { letterSpacing: string }).letterSpacing = `${spacing}px`;
    g.fillText(label, c.width / 2 + spacing / 2, 136);
    const t = new THREE.CanvasTexture(c);
    t.colorSpace = THREE.SRGBColorSpace;
    t.anisotropy = 8;
    return t;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [label, w]);
}
