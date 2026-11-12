import { Canvas, useFrame } from "@react-three/fiber";
import { Float, RoundedBox, Sparkles } from "@react-three/drei";
import { Bloom, EffectComposer } from "@react-three/postprocessing";
import { useRef } from "react";
import * as THREE from "three";
import { LIME, Studio, useLabel } from "./common";

const TAB = LIME.clone().multiplyScalar(1.4);

/** One big AIRKEY keycap: the P key with its lime side tab. Click to press it. */
function Keycap() {
  const group = useRef<THREE.Group>(null);
  const cap = useRef<THREE.Group>(null);
  const ring = useRef<THREE.Mesh>(null);
  const pressed = useRef(-1e9);
  const tex = useLabel("p", 1, { size: 150, weight: 500 });

  useFrame((s, dt) => {
    const t = (performance.now() - pressed.current) / 1000;
    const down = t < 0.3 ? Math.sin((t / 0.3) * Math.PI) : 0;
    if (cap.current) cap.current.position.y = 0.32 - down * 0.28;
    if (group.current) {
      group.current.rotation.y = THREE.MathUtils.damp(group.current.rotation.y, s.pointer.x * 0.6 + Math.sin(s.clock.elapsedTime * 0.4) * 0.25, 3, dt);
      group.current.rotation.x = THREE.MathUtils.damp(group.current.rotation.x, 0.55 - s.pointer.y * 0.3, 3, dt);
    }
    if (ring.current) {
      const k = Math.min(1, t / 1.1);
      ring.current.scale.setScalar(1 + k * 3.5);
      (ring.current.material as THREE.MeshBasicMaterial).opacity = t < 1.1 ? (1 - k) * 0.9 : 0;
    }
  });

  return (
    <Float speed={1.4} floatIntensity={0.6} rotationIntensity={0.15}>
      <group ref={group} onClick={() => (pressed.current = performance.now())} onPointerOver={() => (document.body.style.cursor = "pointer")} onPointerOut={() => (document.body.style.cursor = "")}>
        {/* switch housing */}
        <RoundedBox args={[2.5, 0.5, 2.5]} radius={0.16} smoothness={4} position={[0, -0.3, 0]}>
          <meshPhysicalMaterial color="#0f1111" roughness={0.3} metalness={0.5} clearcoat={1} />
        </RoundedBox>
        <mesh position={[0, -0.04, 0]}>
          <boxGeometry args={[0.5, 0.3, 0.5]} />
          <meshBasicMaterial color={LIME} toneMapped={false} />
        </mesh>
        <group ref={cap} position={[0, 0.32, 0]}>
          <RoundedBox args={[2.2, 0.9, 2.2]} radius={0.32} smoothness={6}>
            <meshPhysicalMaterial color="#2a2d2d" roughness={0.32} clearcoat={0.8} clearcoatRoughness={0.2} />
          </RoundedBox>
          <mesh position={[0, 0.452, 0.04]} rotation-x={-Math.PI / 2}>
            <planeGeometry args={[1.9, 1.9]} />
            <meshBasicMaterial map={tex} transparent />
          </mesh>
          <mesh position={[0.86, 0.455, 0]} rotation-x={-Math.PI / 2}>
            <planeGeometry args={[0.14, 0.95]} />
            <meshBasicMaterial color={TAB} toneMapped={false} />
          </mesh>
        </group>
        <mesh ref={ring} rotation-x={-Math.PI / 2} position={[0, -0.5, 0]}>
          <torusGeometry args={[1.6, 0.03, 8, 120]} />
          <meshBasicMaterial color={TAB} transparent opacity={0} toneMapped={false} />
        </mesh>
      </group>
    </Float>
  );
}

export default function KeycapScene({ active = true }: { active?: boolean }) {
  return (
    <Canvas frameloop={active ? "always" : "never"} dpr={[1, 1.75]} camera={{ position: [0, 2.4, 9.2], fov: 34 }} gl={{ alpha: true, antialias: true }}>
      <color attach="background" args={["#08090a"]} />
      <Studio />
      <ambientLight intensity={0.3} />
      <directionalLight position={[3, 6, 4]} intensity={1.4} />
      <pointLight position={[0, -1, 2]} intensity={6} color="#c6f25a" distance={6} />
      <Keycap />
      <Sparkles count={50} scale={[7, 5, 4]} size={2.4} speed={0.4} color="#c6f25a" />
      <EffectComposer multisampling={0}>
        <Bloom mipmapBlur intensity={1.2} luminanceThreshold={0.85} />
      </EffectComposer>
    </Canvas>
  );
}
