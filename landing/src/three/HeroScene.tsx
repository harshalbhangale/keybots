import { Canvas, useFrame, useThree } from "@react-three/fiber";
import { Float, RoundedBox } from "@react-three/drei";
import { Bloom, EffectComposer } from "@react-three/postprocessing";
import { useLayoutEffect, useMemo, useRef } from "react";
import * as THREE from "three";
import { LIME, RED, Studio, useLabel } from "./common";
import { heroMood, pressAt } from "./bus";

type KeyDef = { id: string; label: string; w: number; x: number; z: number; accent?: boolean; dark?: boolean };

const U = 1; // key width
const G = 0.14; // gap
const ROW_W = 10 * U + 9 * G;

function layout(): KeyDef[] {
  const keys: KeyDef[] = [];
  const row = (chars: string, z: number) => {
    const w = chars.length * U + (chars.length - 1) * G;
    chars.split("").forEach((c, i) =>
      keys.push({ id: c, label: c, w: U, x: -w / 2 + U / 2 + i * (U + G), z, accent: c === "p" }),
    );
  };
  row("qwertyuiop", -1.71);
  row("asdfghjkl", -0.57);
  // row 3: shift, z..m, backspace
  const side = 1.4;
  const mid = 7 * U + 6 * G;
  const g3 = (ROW_W - mid - 2 * side) / 2;
  keys.push({ id: "shift", label: "⇧", w: side, x: -ROW_W / 2 + side / 2, z: 0.57, dark: true });
  "zxcvbnm".split("").forEach((c, i) => keys.push({ id: c, label: c, w: U, x: -ROW_W / 2 + side + g3 + U / 2 + i * (U + G), z: 0.57 }));
  keys.push({ id: "back", label: "⌫", w: side, x: ROW_W / 2 - side / 2, z: 0.57, dark: true });
  // row 4: 123, space, go
  const n = 1.5;
  const go = 2.0;
  const sp = ROW_W - n - go - 2 * G;
  keys.push({ id: "123", label: "123", w: n, x: -ROW_W / 2 + n / 2, z: 1.71, dark: true });
  keys.push({ id: "space", label: "AIRKEY", w: sp, x: -ROW_W / 2 + n + G + sp / 2, z: 1.71 });
  keys.push({ id: "go", label: "go", w: go, x: ROW_W / 2 - go / 2, z: 1.71, dark: true });
  return keys;
}

function Key({ k }: { k: KeyDef }) {
  const group = useRef<THREE.Group>(null);
  const mat = useRef<THREE.MeshPhysicalMaterial>(null);
  const isSpace = k.id === "space";
  const tex = useLabel(k.label, k.w, isSpace ? { size: 54, weight: 700, spacing: 22, color: "#8d8f89" } : {});
  const base = 0.36;
  const color = k.dark ? "#1a1c1c" : "#2a2d2d";

  useFrame(() => {
    const t = (performance.now() - (pressAt[k.id] ?? -1e9)) / 1000;
    const down = t < 0.22 ? Math.sin((t / 0.22) * Math.PI) : 0;
    const glow = Math.max(0, 1 - t / 0.7);
    if (group.current) group.current.position.y = base - down * 0.17;
    if (mat.current) mat.current.emissiveIntensity = glow * glow * 1.2;
  });

  return (
    <group ref={group} position={[k.x, base, k.z]}>
      <RoundedBox args={[k.w, 0.42, 0.92]} radius={0.13} smoothness={4} castShadow>
        <meshPhysicalMaterial
          ref={mat}
          color={color}
          roughness={0.38}
          metalness={0.05}
          clearcoat={0.7}
          clearcoatRoughness={0.25}
          emissive={LIME}
          emissiveIntensity={0}
        />
      </RoundedBox>
      <mesh position={[0, 0.212, 0.02]} rotation-x={-Math.PI / 2}>
        <planeGeometry args={[k.w * 0.92, 0.92]} />
        <meshBasicMaterial map={tex} transparent depthWrite={false} />
      </mesh>
      {k.accent && (
        <mesh position={[k.w / 2 - 0.12, 0.215, 0]} rotation-x={-Math.PI / 2}>
          <planeGeometry args={[0.07, 0.46]} />
          <meshBasicMaterial color={LIME} toneMapped={false} />
        </mesh>
      )}
    </group>
  );
}

function Keyboard() {
  const keys = useMemo(layout, []);
  return (
    <group>
      {/* tray */}
      <RoundedBox args={[ROW_W + 0.7, 0.4, 4.6]} radius={0.3} smoothness={6} position={[0, 0, 0]} receiveShadow>
        <meshPhysicalMaterial color="#0f1111" roughness={0.25} metalness={0.4} clearcoat={1} clearcoatRoughness={0.15} />
      </RoundedBox>
      {/* lime underglow strip */}
      <mesh position={[0, -0.21, 0]} rotation-x={-Math.PI / 2}>
        <planeGeometry args={[ROW_W + 0.2, 4.2]} />
        <meshBasicMaterial color={LIME} transparent opacity={0.06} toneMapped={false} />
      </mesh>
      {keys.map((k) => (
        <Key key={k.id} k={k} />
      ))}
    </group>
  );
}

/** The leash: a glowing ring that circles the keyboard and takes the colour of the last decision. */
function LeashRing() {
  const ring = useRef<THREE.Mesh>(null);
  const mat = useRef<THREE.MeshBasicMaterial>(null);
  const beads = useRef<THREE.InstancedMesh>(null);
  const dummy = useMemo(() => new THREE.Object3D(), []);
  const target = useMemo(() => new THREE.Color(), []);
  const N = 5;

  useFrame((state, dt) => {
    const t = state.clock.elapsedTime;
    if (ring.current) {
      ring.current.rotation.z = t * 0.12;
    }
    const age = (performance.now() - heroMood.at) / 1000;
    const m = age < 2.6 ? heroMood.value : 0;
    target.copy(m === 2 ? RED : m === 3 ? new THREE.Color("#f5b841") : LIME);
    if (mat.current) {
      mat.current.color.lerp(target, Math.min(1, dt * 5));
    }
    if (beads.current) {
      for (let i = 0; i < N; i++) {
        const a = t * 0.5 + (i / N) * Math.PI * 2;
        dummy.position.set(Math.cos(a) * 7.6, Math.sin(a) * 3.6, 0);
        const s = 0.09 + 0.05 * Math.sin(t * 3 + i);
        dummy.scale.setScalar(s);
        dummy.updateMatrix();
        beads.current.setMatrixAt(i, dummy.matrix);
      }
      beads.current.instanceMatrix.needsUpdate = true;
    }
  });

  return (
    <group rotation-x={-Math.PI / 2} position={[0, 0.2, 0]}>
      <mesh ref={ring} scale={[1, 0.475, 1]}>
        <torusGeometry args={[7.6, 0.025, 12, 220]} />
        <meshBasicMaterial ref={mat} color={LIME} toneMapped={false} />
      </mesh>
      <instancedMesh ref={beads} args={[undefined, undefined, N]}>
        <sphereGeometry args={[1, 16, 16]} />
        <meshBasicMaterial color={[2, 2.4, 1.2]} toneMapped={false} />
      </instancedMesh>
    </group>
  );
}

function Coin({ position, rotation, scale = 1, speed = 1 }: { position: [number, number, number]; rotation?: [number, number, number]; scale?: number; speed?: number }) {
  const ref = useRef<THREE.Group>(null);
  const tex = useLabel("Ⓝ", 1, { size: 150, weight: 700, color: "#0b0c0a" });
  useFrame((_, dt) => {
    if (ref.current) ref.current.rotation.y += dt * 0.6 * speed;
  });
  return (
    <Float speed={1.4 * speed} rotationIntensity={0.6} floatIntensity={1.4}>
      <group ref={ref} position={position} rotation={rotation} scale={scale}>
        <mesh rotation-x={Math.PI / 2}>
          <cylinderGeometry args={[0.7, 0.7, 0.14, 48]} />
          <meshPhysicalMaterial color="#c6f25a" roughness={0.25} metalness={0.6} clearcoat={1} />
        </mesh>
        <mesh position={[0, 0, 0.072]}>
          <circleGeometry args={[0.55, 48]} />
          <meshBasicMaterial map={tex} transparent />
        </mesh>
        <mesh position={[0, 0, -0.072]} rotation-y={Math.PI}>
          <circleGeometry args={[0.55, 48]} />
          <meshBasicMaterial map={tex} transparent />
        </mesh>
      </group>
    </Float>
  );
}

function GlassOrb({ position, r = 0.6 }: { position: [number, number, number]; r?: number }) {
  return (
    <Float speed={1.1} floatIntensity={2}>
      <mesh position={position}>
        <sphereGeometry args={[r, 48, 48]} />
        <meshPhysicalMaterial
          transmission={1}
          thickness={1.2}
          roughness={0.05}
          ior={1.45}
          clearcoat={1}
          attenuationColor="#c6f25a"
          attenuationDistance={2.5}
          color="#ffffff"
        />
      </mesh>
    </Float>
  );
}

/** The red "drain.near" shard that the leash keeps away. */
function Shard({ position }: { position: [number, number, number] }) {
  const ref = useRef<THREE.Mesh>(null);
  useFrame((s) => {
    if (!ref.current) return;
    ref.current.rotation.x = s.clock.elapsedTime * 0.4;
    ref.current.rotation.y = s.clock.elapsedTime * 0.6;
  });
  return (
    <Float speed={2} floatIntensity={1.5}>
      <mesh ref={ref} position={position}>
        <octahedronGeometry args={[0.55, 0]} />
        <meshPhysicalMaterial color="#ff5a52" emissive={RED} emissiveIntensity={0.6} roughness={0.2} clearcoat={1} flatShading />
      </mesh>
    </Float>
  );
}

/** Keeps the keyboard a fixed share of the width at any aspect, and pushes it into the lower part of the hero. */
function Framing() {
  const camera = useThree((s) => s.camera) as THREE.PerspectiveCamera;
  const size = useThree((s) => s.size);
  useLayoutEffect(() => {
    const aspect = size.width / size.height;
    const share = aspect < 0.8 ? 1.04 : aspect < 1.2 ? 0.88 : 0.6; // how much of the width the keyboard takes
    const halfH = Math.tan(THREE.MathUtils.degToRad(camera.fov / 2));
    const d = 12.2 / (share * 2 * halfH * aspect);
    const el = THREE.MathUtils.degToRad(aspect < 0.8 ? 38 : 44);
    camera.position.set(0, Math.sin(el) * d, Math.cos(el) * d);
    camera.lookAt(0, 0, 0);
    const shift = aspect < 0.8 ? 0.36 : 0.43;
    camera.setViewOffset(size.width, size.height, 0, -size.height * shift, size.width, size.height);
    camera.updateProjectionMatrix();
  }, [camera, size]);
  return null;
}

function Rig({ children }: { children: React.ReactNode }) {
  const g = useRef<THREE.Group>(null);
  useFrame((state, dt) => {
    if (!g.current) return;
    const { x, y } = state.pointer;
    g.current.rotation.y = THREE.MathUtils.damp(g.current.rotation.y, x * 0.18, 3, dt);
    g.current.rotation.x = THREE.MathUtils.damp(g.current.rotation.x, -y * 0.08, 3, dt);
  });
  return <group ref={g}>{children}</group>;
}

export default function HeroScene({ active = true }: { active?: boolean }) {
  return (
    <Canvas
      frameloop={active ? "always" : "never"}
      dpr={[1, 1.75]}
      camera={{ position: [0, 14, 14], fov: 30 }}
      gl={{ antialias: true, alpha: true, powerPreference: "high-performance" }}
    >
      <color attach="background" args={["#08090a"]} />
      <Framing />
      <Studio tint="#ffffff" />
      <ambientLight intensity={0.25} />
      <directionalLight position={[4, 10, 6]} intensity={1.2} />
      <pointLight position={[0, 3, 5]} intensity={4} color="#c6f25a" distance={10} />
      <group>
        <Rig>
          <Keyboard />
          <LeashRing />
          <Coin position={[-8.2, 3.4, -2]} rotation={[0.3, 0.4, 0.2]} scale={1.1} />
          <Coin position={[8.6, 2.6, -1.5]} rotation={[-0.2, -0.5, 0]} scale={0.8} speed={1.3} />
          <Coin position={[-5.4, 4.6, -5]} scale={0.55} speed={0.8} />
          <GlassOrb position={[6.4, 4.2, -4]} r={0.75} />
          <GlassOrb position={[-9.8, 1.2, 1.4]} r={0.45} />
          <Shard position={[10.4, 4.4, -6]} />
        </Rig>
      </group>
      <EffectComposer multisampling={0}>
        <Bloom mipmapBlur intensity={1.1} luminanceThreshold={0.85} luminanceSmoothing={0.2} />
      </EffectComposer>
    </Canvas>
  );
}
