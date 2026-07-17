import { useRef } from "react";
import * as THREE from "three";
import { Canvas } from "@react-three/fiber";
import { Grid, OrbitControls, TransformControls } from "@react-three/drei";

import { useEditorStore } from "@/store/useEditorStore";
import BlockMesh from "@/components/editor/BlockMesh";
import GroundMesh from "@/components/editor/GroundMesh";
import PlayMode from "@/components/editor/PlayMode";

/** The 3D viewport: lights, grid, ground, blocks, and the transform gizmo
 * bound to the current selection. Switches to the walk-test rig in play mode. */
export default function EditorScene() {
  const document = useEditorStore((s) => s.document);
  const selectedIds = useEditorStore((s) => s.selectedIds);
  const toggleSelection = useEditorStore((s) => s.toggleSelection);
  const clearSelection = useEditorStore((s) => s.clearSelection);
  const transformMode = useEditorStore((s) => s.transformMode);
  const viewMode = useEditorStore((s) => s.viewMode);
  const updateBlock = useEditorStore((s) => s.updateBlock);
  const commitHistory = useEditorStore((s) => s.commitHistory);

  const objectRefs = useRef<Map<string, THREE.Object3D>>(new Map());
  const orbitRef = useRef<any>(null);
  const transformRef = useRef<any>(null);

  const registerRef = (id: string, obj: THREE.Object3D | null) => {
    if (obj) objectRefs.current.set(id, obj);
    else objectRefs.current.delete(id);
  };

  const selectedBlock =
    selectedIds.length === 1 ? document.blocks.find((b) => b.id === selectedIds[0]) : undefined;
  const selectedObj = selectedBlock ? objectRefs.current.get(selectedBlock.id) : undefined;

  const syncTransform = () => {
    if (!selectedBlock || !selectedObj) return;
    updateBlock(selectedBlock.id, {
      position: { x: selectedObj.position.x, y: selectedObj.position.y, z: selectedObj.position.z },
      rotation: {
        x: THREE.MathUtils.radToDeg(selectedObj.rotation.x),
        y: THREE.MathUtils.radToDeg(selectedObj.rotation.y),
        z: THREE.MathUtils.radToDeg(selectedObj.rotation.z),
      },
      scale: { x: selectedObj.scale.x, y: selectedObj.scale.y, z: selectedObj.scale.z },
    });
  };

  return (
    <Canvas shadows camera={{ position: [40, 32, 40], fov: 50 }} className="bg-[#12151c]">
      <color attach="background" args={["#12151c"]} />
      <hemisphereLight intensity={0.55} groundColor="#20242c" />
      <directionalLight
        position={[30, 45, 20]}
        intensity={1.3}
        castShadow
        shadow-mapSize={[2048, 2048]}
      />
      <Grid
        args={[400, 400]}
        cellSize={2}
        cellThickness={0.5}
        sectionSize={10}
        sectionThickness={1}
        cellColor="#2a3038"
        sectionColor="#3b4a5a"
        fadeDistance={140}
        infiniteGrid
      />

      {viewMode === "play" ? (
        <PlayMode />
      ) : (
        <>
          <group
            onPointerMissed={() => clearSelection()}
          >
            <GroundMesh />
            {document.blocks.map((block) => (
              <BlockMesh
                key={block.id}
                block={block}
                selected={selectedIds.includes(block.id)}
                onSelect={(id, additive) => toggleSelection(id, additive)}
                registerRef={registerRef}
              />
            ))}
          </group>

          {selectedObj && (
            <TransformControls
              ref={transformRef}
              object={selectedObj}
              mode={transformMode}
              onObjectChange={syncTransform}
              onMouseUp={commitHistory}
              onMouseDown={() => {
                if (orbitRef.current) orbitRef.current.enabled = false;
              }}
            />
          )}

          <OrbitControls ref={orbitRef} makeDefault enableDamping dampingFactor={0.08} />
        </>
      )}
    </Canvas>
  );
}
