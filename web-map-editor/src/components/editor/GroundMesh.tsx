import { useMemo } from "react";
import * as THREE from "three";

import { useEditorStore } from "@/store/useEditorStore";
import type { GroundDef } from "@/types/mapEditor";

function buildShape(ground: GroundDef): THREE.Shape {
  const shape = new THREE.Shape();
  if (ground.shape === "rectangle") {
    const hw = ground.width / 2;
    const hd = ground.depth / 2;
    shape.moveTo(-hw, -hd);
    shape.lineTo(hw, -hd);
    shape.lineTo(hw, hd);
    shape.lineTo(-hw, hd);
    shape.closePath();
  } else if (ground.shape === "circle") {
    shape.absarc(0, 0, ground.radius, 0, Math.PI * 2, false);
  } else {
    const pts = ground.points;
    if (pts.length < 3) {
      shape.absarc(0, 0, 20, 0, Math.PI * 2, false);
    } else {
      shape.moveTo(pts[0][0], pts[0][1]);
      for (let i = 1; i < pts.length; i++) shape.lineTo(pts[i][0], pts[i][1]);
      shape.closePath();
    }
  }
  return shape;
}

/** Renders the ground plane in whatever shape the user configured
 * (rectangle, circle, or free polygon outline). */
export default function GroundMesh() {
  const ground = useEditorStore((s) => s.document.ground);
  const groundEditMode = useEditorStore((s) => s.groundEditMode);
  const addGroundPoint = useEditorStore((s) => s.addGroundPoint);

  const geometry = useMemo(() => {
    const shape = buildShape(ground);
    const geo = new THREE.ShapeGeometry(shape);
    geo.rotateX(-Math.PI / 2);
    return geo;
  }, [ground]);

  return (
    <group>
      <mesh
        geometry={geometry}
        receiveShadow
        onClick={(e) => {
          if (ground.shape !== "polygon" || !groundEditMode) return;
          e.stopPropagation();
          addGroundPoint(Number(e.point.x.toFixed(2)), Number(e.point.z.toFixed(2)));
        }}
      >
        <meshStandardMaterial color={ground.color} roughness={0.95} metalness={0} />
      </mesh>
      {ground.shape === "polygon" && ground.points.length > 1 && (
        <line>
          <bufferGeometry
            attach="geometry"
            onUpdate={(geo) => {
              const pts = ground.points.map(([x, z]) => new THREE.Vector3(x, 0.05, z));
              pts.push(pts[0]);
              geo.setFromPoints(pts);
            }}
          />
          <lineBasicMaterial color="#4fd1ff" linewidth={2} />
        </line>
      )}
      {groundEditMode &&
        ground.points.map((p, i) => (
          <mesh key={i} position={[p[0], 0.08, p[1]]}>
            <sphereGeometry args={[0.4, 12, 12]} />
            <meshBasicMaterial color="#4fd1ff" />
          </mesh>
        ))}
    </group>
  );
}
