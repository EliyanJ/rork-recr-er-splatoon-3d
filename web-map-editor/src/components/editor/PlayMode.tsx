import { useEffect, useMemo, useRef } from "react";
import * as THREE from "three";
import { useFrame, useThree } from "@react-three/fiber";
import { PointerLockControls } from "@react-three/drei";

import { useEditorStore } from "@/store/useEditorStore";
import BlockMesh from "@/components/editor/BlockMesh";
import GroundMesh from "@/components/editor/GroundMesh";

const MOVE_SPEED = 7;
const GRAVITY = -22;
const JUMP_SPEED = 8.5;
const PLAYER_RADIUS = 0.45;
const PLAYER_HEIGHT = 1.75;

/** Minimal walk-test rig: WASD + mouse look, gravity, downward raycast for
 * standing height, and horizontal ray probes to slide along solid blocks.
 * Validates level flow only — no shooting or paint here. */
export default function PlayMode() {
  const document = useEditorStore((s) => s.document);
  const { camera, scene } = useThree();
  const keys = useRef<Record<string, boolean>>({});
  const velocityY = useRef(0);
  const grounded = useRef(false);
  const raycaster = useMemo(() => new THREE.Raycaster(), []);

  const objectRefs = useRef<Map<string, THREE.Object3D>>(new Map());
  const registerRef = (id: string, obj: THREE.Object3D | null) => {
    if (obj) objectRefs.current.set(id, obj);
    else objectRefs.current.delete(id);
  };

  useEffect(() => {
    camera.position.set(0, 3, 8);
    const down = (e: KeyboardEvent) => (keys.current[e.code] = true);
    const up = (e: KeyboardEvent) => (keys.current[e.code] = false);
    window.addEventListener("keydown", down);
    window.addEventListener("keyup", up);
    return () => {
      window.removeEventListener("keydown", down);
      window.removeEventListener("keyup", up);
    };
  }, [camera]);

  const collidables = () => {
    const meshes: THREE.Object3D[] = [];
    scene.traverse((o) => {
      if ((o as THREE.Mesh).isMesh && o.visible) meshes.push(o);
    });
    return meshes;
  };

  useFrame((_, delta) => {
    const dt = Math.min(delta, 0.05);
    const forward = new THREE.Vector3();
    camera.getWorldDirection(forward);
    forward.y = 0;
    forward.normalize();
    const right = new THREE.Vector3().crossVectors(forward, camera.up).normalize();

    const move = new THREE.Vector3();
    if (keys.current["KeyW"]) move.add(forward);
    if (keys.current["KeyS"]) move.sub(forward);
    if (keys.current["KeyD"]) move.add(right);
    if (keys.current["KeyA"]) move.sub(right);
    if (move.lengthSq() > 0) move.normalize().multiplyScalar(MOVE_SPEED * dt);

    const meshes = collidables();

    // Horizontal collision probes (4 directions around the player).
    const probeDirs = [
      new THREE.Vector3(1, 0, 0),
      new THREE.Vector3(-1, 0, 0),
      new THREE.Vector3(0, 0, 1),
      new THREE.Vector3(0, 0, -1),
    ];
    const origin = camera.position.clone();
    origin.y -= PLAYER_HEIGHT * 0.35;

    const nextPos = camera.position.clone().add(move);
    for (const dir of probeDirs) {
      const toWall = dir.clone();
      const wantsThatWay = move.dot(dir) > 0;
      if (!wantsThatWay) continue;
      raycaster.set(origin, toWall);
      raycaster.far = PLAYER_RADIUS + 0.35;
      const hits = raycaster.intersectObjects(meshes, false);
      if (hits.length > 0) {
        const along = move.clone().projectOnVector(dir);
        nextPos.sub(along);
      }
    }

    // Gravity + ground snapping via downward raycast.
    velocityY.current += GRAVITY * dt;
    nextPos.y = camera.position.y + velocityY.current * dt;

    const downOrigin = nextPos.clone();
    downOrigin.y += 0.5;
    raycaster.set(downOrigin, new THREE.Vector3(0, -1, 0));
    raycaster.far = 200;
    const downHits = raycaster.intersectObjects(meshes, false);
    const floorY = downHits.length > 0 ? downHits[0].point.y : 0;
    const feetY = nextPos.y - PLAYER_HEIGHT;

    if (feetY <= floorY + 0.05) {
      nextPos.y = floorY + PLAYER_HEIGHT;
      velocityY.current = 0;
      grounded.current = true;
    } else {
      grounded.current = false;
    }

    if (keys.current["Space"] && grounded.current) {
      velocityY.current = JUMP_SPEED;
    }

    camera.position.copy(nextPos);
  });

  return (
    <>
      <GroundMesh />
      {document.blocks.map((block) => (
        <BlockMesh
          key={block.id}
          block={block}
          selected={false}
          onSelect={() => {}}
          registerRef={registerRef}
        />
      ))}
      <PointerLockControls />
    </>
  );
}
