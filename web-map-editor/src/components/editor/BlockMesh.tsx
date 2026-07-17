import { useMemo, useRef } from "react";
import * as THREE from "three";
import { useGLTF } from "@react-three/drei";

import { KIND_COLORS } from "@/types/mapEditor";
import type { EditorBlock } from "@/types/mapEditor";

interface Props {
  block: EditorBlock;
  selected: boolean;
  onSelect: (id: string, additive: boolean) => void;
  registerRef: (id: string, obj: THREE.Object3D | null) => void;
}

function ImportedMesh({ url }: { url: string }) {
  const { scene } = useGLTF(url);
  const cloned = useMemo(() => scene.clone(true), [scene]);
  return <primitive object={cloned} />;
}

/** Renders one editor block: primitive geometry, imported model, or the
 * translucent tint used to signal its interactive kind. */
export default function BlockMesh({ block, selected, onSelect, registerRef }: Props) {
  const groupRef = useRef<THREE.Group>(null);
  const tint = block.kind !== "solid" ? KIND_COLORS[block.kind] : block.color;
  const rotationRad: [number, number, number] = [
    (block.rotation.x * Math.PI) / 180,
    (block.rotation.y * Math.PI) / 180,
    (block.rotation.z * Math.PI) / 180,
  ];

  const geometryNode = () => {
    const d = block.dimensions;
    switch (block.geometry) {
      case "box":
        return (
          <mesh castShadow receiveShadow>
            <boxGeometry args={[d.width, d.height, d.depth]} />
            <meshStandardMaterial
              color={tint}
              transparent={block.opacity < 1}
              opacity={block.opacity}
              roughness={0.8}
            />
          </mesh>
        );
      case "cylinder":
        return (
          <mesh castShadow receiveShadow>
            <cylinderGeometry args={[d.radius, d.radius, d.height, 24]} />
            <meshStandardMaterial
              color={tint}
              transparent={block.opacity < 1}
              opacity={block.opacity}
              roughness={0.8}
            />
          </mesh>
        );
      case "sphere":
        return (
          <mesh castShadow receiveShadow>
            <sphereGeometry args={[d.radius, 24, 24]} />
            <meshStandardMaterial
              color={tint}
              transparent={block.opacity < 1}
              opacity={block.opacity}
              roughness={0.8}
            />
          </mesh>
        );
      case "prism":
        return (
          <mesh castShadow receiveShadow rotation={[0, Math.PI / 4, 0]}>
            <cylinderGeometry args={[d.width * 0.75, d.width * 0.75, d.height, 3]} />
            <meshStandardMaterial
              color={tint}
              transparent={block.opacity < 1}
              opacity={block.opacity}
              roughness={0.8}
            />
          </mesh>
        );
      case "imported":
        return block.modelUrl ? (
          <ImportedMesh url={block.modelUrl} />
        ) : (
          <mesh>
            <boxGeometry args={[2, 2, 2]} />
            <meshStandardMaterial color="#ff4d4d" wireframe />
          </mesh>
        );
    }
  };

  return (
    <group
      ref={(obj) => {
        groupRef.current = obj;
        registerRef(block.id, obj);
      }}
      position={[block.position.x, block.position.y, block.position.z]}
      rotation={rotationRad}
      scale={[block.scale.x, block.scale.y, block.scale.z]}
      userData={{ blockId: block.id }}
      onClick={(e) => {
        e.stopPropagation();
        onSelect(block.id, e.shiftKey);
      }}
    >
      {geometryNode()}
      {selected && (
        <mesh scale={1.03}>
          {block.geometry === "box" || block.geometry === "prism" ? (
            <boxGeometry
              args={[block.dimensions.width, block.dimensions.height, block.dimensions.depth]}
            />
          ) : block.geometry === "cylinder" ? (
            <cylinderGeometry
              args={[block.dimensions.radius, block.dimensions.radius, block.dimensions.height, 24]}
            />
          ) : (
            <sphereGeometry args={[block.dimensions.radius, 24, 24]} />
          )}
          <meshBasicMaterial color="#ffd23f" wireframe />
        </mesh>
      )}
      {block.collision.mode === "custom" && (
        <mesh
          position={[block.collision.offset.x, block.collision.offset.y, block.collision.offset.z]}
        >
          <boxGeometry args={[block.collision.size.x, block.collision.size.y, block.collision.size.z]} />
          <meshBasicMaterial color="#ff5555" wireframe />
        </mesh>
      )}
    </group>
  );
}
