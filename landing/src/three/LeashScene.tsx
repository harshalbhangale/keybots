import { Canvas, useFrame, useThree } from "@react-three/fiber";
import { Float, Grid, Html, MeshDistortMaterial, QuadraticBezierLine, RoundedBox, Sparkles, Trail } from "@react-three/drei";
import { Bloom, EffectComposer } from "@react-three/postprocessing";
import { useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import * as THREE from "three";
import { AMBER, LIME, RED, Studio } from "./common";
import { useLeash, type AgentId, type Decision } from "../lib/leash";

const AGENT_POS: Record<AgentId, THREE.Vector3> = {
  pay: new THREE.Vector3(-3.7, 1.45, 0),
  inbox: new THREE.Vector3(-3.7, -1.45, 0),
};
const VAULT = new THREE.Vector3(0, 0, 0);
const RECEIVERS: { account: string; label: string; pos: THREE.Vector3 }[] = [
  { account: "harshal.near", label: "harshal.near", pos: new THREE.Vector3(3.5, 2.25, -0.4) },
  { account: "mom.near", label: "mom.near", pos: new THREE.Vector3(3.9, 0.75, 0.2) },
  { account: "designer.near", label: "designer.near", pos: new THREE.Vector3(3.7, -0.75, 0) },
  { account: "drain.near", label: "drain.near", pos: new THREE.Vector3(3.3, -2.25, 0.3) },
];
const receiverPos = (acc: string) => RECEIVERS.find((r) => r.account === acc)?.pos ?? new THREE.Vector3(4.6, -0.2, -0.6);

/* ---------- vault ---------- */

function Vault({ paused, flash }: { paused: boolean; flash: React.MutableRefObject<{ at: number; color: THREE.Color }> }) {
  const shell = useRef<THREE.Mesh>(null);
  const core = useRef<THREE.Mesh>(null);
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const coreMat = useRef<any>(null);
  const halo = useRef<THREE.MeshBasicMaterial>(null);
  const shock = useRef<THREE.Mesh>(null);
  const target = useMemo(() => new THREE.Color(), []);

  useFrame((s, dt) => {
    const t = s.clock.elapsedTime;
    if (shell.current) {
      shell.current.rotation.y = t * (paused ? 0.05 : 0.25);
      shell.current.rotation.x = Math.sin(t * 0.3) * 0.15;
    }
    if (core.current) core.current.rotation.y = -t * 0.6;
    target.copy(paused ? RED : LIME);
    if (coreMat.current) {
      coreMat.current.emissive.lerp(target, Math.min(1, dt * 4));
      coreMat.current.color.lerp(target, Math.min(1, dt * 4));
      coreMat.current.speed = paused ? 0.6 : 2.4;
    }
    const age = (performance.now() - flash.current.at) / 1000;
    if (halo.current) {
      halo.current.color.copy(age < 0.9 ? flash.current.color : target);
      halo.current.opacity = 0.08 + (age < 0.9 ? (1 - age / 0.9) * 0.35 : 0);
    }
    if (shock.current) {
      const k = age < 0.8 ? age / 0.8 : 1;
      shock.current.scale.setScalar(1 + k * 2.2);
      (shock.current.material as THREE.MeshBasicMaterial).opacity = age < 0.8 ? (1 - k) * 0.9 : 0;
      (shock.current.material as THREE.MeshBasicMaterial).color.copy(flash.current.color);
    }
  });

  return (
    <group>
      <Float speed={1.2} rotationIntensity={0.2} floatIntensity={0.4}>
        <RoundedBox ref={shell} args={[2.3, 2.3, 2.3]} radius={0.38} smoothness={6}>
          <meshPhysicalMaterial
            transmission={1}
            thickness={1.4}
            roughness={0.08}
            ior={1.35}
            clearcoat={1}
            color="#e9f3dc"
            attenuationColor="#c6f25a"
            attenuationDistance={4}
          />
        </RoundedBox>
        <mesh ref={core}>
          <icosahedronGeometry args={[0.62, 8]} />
          <MeshDistortMaterial ref={coreMat} color={LIME} emissive={LIME} emissiveIntensity={2.2} roughness={0.2} distort={0.35} speed={2.4} toneMapped={false} />
        </mesh>
      </Float>
      <mesh>
        <sphereGeometry args={[1.9, 32, 32]} />
        <meshBasicMaterial ref={halo} color={LIME} transparent opacity={0.08} depthWrite={false} side={THREE.BackSide} />
      </mesh>
      <mesh ref={shock} rotation-x={Math.PI / 2}>
        <torusGeometry args={[1.4, 0.03, 8, 96]} />
        <meshBasicMaterial color={RED} transparent opacity={0} toneMapped={false} />
      </mesh>
      <Html position={[0, -1.75, 0]} center distanceFactor={15} zIndexRange={[5, 0]}>
        <div className="tag on" style={{ whiteSpace: "nowrap" }}>
          leash.airkey-harshal.testnet
        </div>
      </Html>
    </group>
  );
}

/* ---------- agents + tethers ---------- */

function Agent({ id, paused, spent, cap }: { id: AgentId; paused: boolean; spent: number; cap: number }) {
  const ref = useRef<THREE.Group>(null);
  const color = id === "pay" ? LIME : AMBER;
  useFrame((s) => {
    if (!ref.current) return;
    const t = s.clock.elapsedTime + (id === "pay" ? 0 : 1.7);
    ref.current.position.set(AGENT_POS[id].x + Math.sin(t * 0.8) * 0.12, AGENT_POS[id].y + Math.cos(t * 0.9) * 0.15, Math.sin(t * 0.5) * 0.2);
  });
  return (
    <group ref={ref} position={AGENT_POS[id]}>
      <mesh>
        <sphereGeometry args={[0.42, 48, 48]} />
        <meshPhysicalMaterial color={color} emissive={color} emissiveIntensity={paused ? 0.05 : 0.6} roughness={0.25} clearcoat={1} />
      </mesh>
      <mesh rotation-x={Math.PI / 2.4}>
        <torusGeometry args={[0.66, 0.012, 8, 80]} />
        <meshBasicMaterial color={color} transparent opacity={0.5} />
      </mesh>
      <Html position={[0, -0.85, 0]} center distanceFactor={15} zIndexRange={[5, 0]}>
        <div className="tag" style={{ whiteSpace: "nowrap", color: id === "pay" ? "var(--lime)" : "var(--amber)" }}>
          {id === "pay" ? "pay · trusted" : "inbox · untrusted"} · {spent.toFixed(1)}/{cap}
        </div>
      </Html>
    </group>
  );
}

function Tether({ id, paused }: { id: AgentId; paused: boolean }) {
  const line = useRef<any>(null);
  const mid = useMemo(() => new THREE.Vector3(), []);
  useFrame((s) => {
    const t = s.clock.elapsedTime + (id === "pay" ? 0 : 1.7);
    const a = new THREE.Vector3(AGENT_POS[id].x + Math.sin(t * 0.8) * 0.12, AGENT_POS[id].y + Math.cos(t * 0.9) * 0.15, Math.sin(t * 0.5) * 0.2);
    mid.set((a.x + VAULT.x) / 2, (a.y + VAULT.y) / 2 - 0.7 + Math.sin(t * 1.3) * 0.15, 0.4);
    line.current?.setPoints(a, VAULT, mid);
  });
  return (
    <QuadraticBezierLine
      ref={line}
      start={AGENT_POS[id]}
      end={VAULT}
      color={paused ? "#ff5a52" : id === "pay" ? "#c6f25a" : "#f5b841"}
      lineWidth={1.6}
      dashed={paused}
      dashScale={6}
      transparent
      opacity={0.7}
    />
  );
}

function Receiver({ account, label, pos, blocked, allowed }: { account: string; label: string; pos: THREE.Vector3; blocked: boolean; allowed: boolean }) {
  const ref = useRef<THREE.Mesh>(null);
  useFrame((s, dt) => {
    if (ref.current) ref.current.rotation.y += dt * (blocked ? 1.6 : 0.6);
    if (ref.current) ref.current.rotation.x = Math.sin(s.clock.elapsedTime + pos.y) * 0.3;
  });
  const color = blocked ? "#ff5a52" : allowed ? "#c6f25a" : "#a7a9a3";
  return (
    <group position={pos}>
      <mesh ref={ref} userData={{ account }}>
        {account === "drain.near" ? <octahedronGeometry args={[0.36, 0]} /> : <torusGeometry args={[0.28, 0.09, 16, 48]} />}
        <meshPhysicalMaterial color={color} emissive={color} emissiveIntensity={blocked ? 0.9 : 0.25} roughness={0.3} clearcoat={1} flatShading={account === "drain.near"} />
      </mesh>
      <Html position={[0, -0.62, 0]} center distanceFactor={15} zIndexRange={[5, 0]}>
        <div className={`tag ${blocked ? "off" : allowed ? "on" : ""}`} style={{ whiteSpace: "nowrap" }}>
          {label}
          {blocked ? " · blocked" : allowed ? " · allowed" : ""}
        </div>
      </Html>
    </group>
  );
}

/* ---------- payment pulses ---------- */

type Pulse = { id: number; d: Decision; born: number; fromVault: boolean };

const ease = (t: number) => 1 - Math.pow(1 - t, 3);

function PulseOrb({ p, onDone, flash }: { p: Pulse; onDone: (id: number) => void; flash: React.MutableRefObject<{ at: number; color: THREE.Color }> }) {
  const ref = useRef<THREE.Mesh>(null);
  const mat = useRef<THREE.MeshBasicMaterial>(null);
  const hit = useRef(false);
  const outcome = p.d.outcome;
  const color = outcome === "paid" ? LIME : outcome === "blocked" ? RED : outcome === "pending" ? AMBER : new THREE.Color("#8d8f89");
  const from = AGENT_POS[p.d.agent];
  const to = p.d.intent ? receiverPos(p.d.intent.receiver) : VAULT;
  const v = useMemo(() => new THREE.Vector3(), []);

  useFrame(() => {
    const t = (performance.now() - p.born) / 1000;
    if (!ref.current || !mat.current) return;
    let done = false;
    if (outcome === "none") {
      const k = Math.min(1, t / 0.6);
      ref.current.position.copy(from).add(new THREE.Vector3(k * 0.8, 0, 0));
      mat.current.opacity = 1 - k;
      done = k >= 1;
    } else if (p.fromVault) {
      const k = Math.min(1, t / 0.8);
      v.lerpVectors(VAULT, to, ease(k));
      v.y += Math.sin(k * Math.PI) * 0.6;
      ref.current.position.copy(v);
      done = k >= 1;
    } else {
      const inbound = 0.75;
      if (t < inbound) {
        const k = ease(t / inbound);
        v.lerpVectors(from, VAULT, k);
        v.y -= Math.sin(k * Math.PI) * 0.6;
        ref.current.position.copy(v);
      } else {
        if (!hit.current) {
          hit.current = true;
          flash.current = { at: performance.now(), color: color.clone() };
        }
        const k = Math.min(1, (t - inbound) / 0.8);
        if (outcome === "paid") {
          v.lerpVectors(VAULT, to, ease(k));
          v.y += Math.sin(k * Math.PI) * 0.6;
        } else if (outcome === "blocked") {
          v.lerpVectors(VAULT, from, ease(k) * 0.55);
          v.y += Math.sin(k * Math.PI * 2) * 0.3;
          mat.current.opacity = 1 - k;
        } else {
          // pending: drift into orbit, then hand over to the PendingOrb
          v.set(Math.cos(k * 3) * 1.8 * k, Math.sin(k * 3) * 0.5 * k, Math.sin(k * 3) * 1.8 * k);
          mat.current.opacity = 1 - k * 0.6;
        }
        ref.current.position.copy(v);
        done = k >= 1;
      }
    }
    if (done) onDone(p.id);
  });

  return (
    <Trail width={1.2} length={5} color={color} attenuation={(w) => w * w} decay={1.5}>
      <mesh ref={ref} position={from}>
        <sphereGeometry args={[0.13, 20, 20]} />
        <meshBasicMaterial ref={mat} color={color.clone().multiplyScalar(2.2)} toneMapped={false} transparent />
      </mesh>
    </Trail>
  );
}

function PendingOrbs({ pending }: { pending: Decision[] }) {
  const group = useRef<THREE.Group>(null);
  useFrame((s) => {
    if (!group.current) return;
    group.current.children.forEach((c, i) => {
      const a = s.clock.elapsedTime * 0.9 + (i / Math.max(1, pending.length)) * Math.PI * 2;
      c.position.set(Math.cos(a) * 1.8, Math.sin(a * 2) * 0.25, Math.sin(a) * 1.8);
    });
  });
  return (
    <group ref={group}>
      {pending.map((d) => (
        <mesh key={d.id}>
          <sphereGeometry args={[0.12, 16, 16]} />
          <meshBasicMaterial color={AMBER.clone().multiplyScalar(2)} toneMapped={false} />
        </mesh>
      ))}
    </group>
  );
}

function Pulses() {
  const s = useLeash();
  const [pulses, setPulses] = useState<Pulse[]>([]);
  const seen = useRef(0);
  const flash = useRef({ at: -1e9, color: LIME.clone() });

  useEffect(() => {
    const fresh = s.log.filter((d) => d.id > seen.current);
    if (!fresh.length) return;
    seen.current = Math.max(...fresh.map((d) => d.id));
    setPulses((ps) => [
      ...ps,
      ...fresh.reverse().map((d) => ({ id: d.id, d, born: performance.now(), fromVault: d.trace[0]?.label === "Owner approved" })),
    ]);
  }, [s.log]);

  return (
    <>
      <Vault paused={s.paused} flash={flash} />
      {(["pay", "inbox"] as AgentId[]).map((id) => (
        <group key={id}>
          <Agent id={id} paused={s.paused} spent={s.agents[id].spentToday} cap={s.agents[id].dailyCap} />
          <Tether id={id} paused={s.paused} />
        </group>
      ))}
      {RECEIVERS.map((r) => (
        <Receiver key={r.account} {...r} blocked={s.blocklist.includes(r.account)} allowed={s.allowlist.includes(r.account)} />
      ))}
      <PendingOrbs pending={s.pending} />
      {pulses.map((p) => (
        <PulseOrb key={p.id} p={p} flash={flash} onDone={(id) => setPulses((ps) => ps.filter((x) => x.id !== id))} />
      ))}
    </>
  );
}

function Framing() {
  const camera = useThree((s) => s.camera) as THREE.PerspectiveCamera;
  const size = useThree((s) => s.size);
  useLayoutEffect(() => {
    const aspect = size.width / size.height;
    const halfH = Math.tan(THREE.MathUtils.degToRad(camera.fov / 2));
    const width = 12.4; // agents to receiver labels
    const d = Math.max(9.5, width / (2 * halfH * aspect));
    camera.position.set(0, d * 0.16, d);
    camera.lookAt(0, 0, 0);
    camera.updateProjectionMatrix();
  }, [camera, size]);
  return null;
}

function Drift({ children }: { children: React.ReactNode }) {
  const g = useRef<THREE.Group>(null);
  useFrame((state, dt) => {
    if (!g.current) return;
    g.current.rotation.y = THREE.MathUtils.damp(g.current.rotation.y, state.pointer.x * 0.25, 2.5, dt);
    g.current.rotation.x = THREE.MathUtils.damp(g.current.rotation.x, -state.pointer.y * 0.12, 2.5, dt);
  });
  return <group ref={g}>{children}</group>;
}

export default function LeashScene({ active = true }: { active?: boolean }) {
  return (
    <Canvas frameloop={active ? "always" : "never"} dpr={[1, 1.75]} camera={{ position: [0, 1.6, 11], fov: 35 }} gl={{ antialias: true, alpha: true }}>
      <Framing />
      <Studio intensity={0.8} />
      <ambientLight intensity={0.3} />
      <pointLight position={[0, 0, 0]} intensity={6} color="#c6f25a" distance={6} />
      <Drift>
        <Pulses />
        <Sparkles count={60} scale={[12, 6, 4]} size={2} speed={0.3} color="#c6f25a" opacity={0.5} />
      </Drift>
      <Grid
        position={[0, -3.3, 0]}
        args={[40, 40]}
        cellSize={0.6}
        cellThickness={0.6}
        cellColor="#1f2420"
        sectionSize={3}
        sectionThickness={1}
        sectionColor="#2f3a22"
        fadeDistance={22}
        fadeStrength={1.4}
        infiniteGrid
      />
      <EffectComposer multisampling={0}>
        <Bloom mipmapBlur intensity={1.2} luminanceThreshold={0.8} luminanceSmoothing={0.2} />
      </EffectComposer>
    </Canvas>
  );
}
