/** Core data model for the Ink Arena 3D map editor. Everything the user
 * builds gets serialized to this shape and exported as JSON. */

export type Geometry = "box" | "cylinder" | "sphere" | "prism" | "imported";

/** Functional role of a block once translated into the game engine. */
export type BlockKind =
  | "solid"
  | "bounce"
  | "vent"
  | "conveyor"
  | "cover"
  | "spawn";

export type CollisionMode = "auto" | "custom" | "none";

export interface Vec3 {
  x: number;
  y: number;
  z: number;
}

export interface CollisionDef {
  mode: CollisionMode;
  /** Full width/height/depth of the custom hitbox (meters). */
  size: Vec3;
  /** Offset of the custom hitbox relative to the block center. */
  offset: Vec3;
}

export interface ConveyorParams {
  speed: number;
  /** Direction of travel, degrees around the vertical axis. */
  direction: number;
}

export interface BounceParams {
  force: number;
}

export interface VentParams {
  force: number;
  height: number;
}

export type SpawnTeam = "a" | "b" | "neutral";

export interface SpawnParams {
  team: SpawnTeam;
}

export interface Dimensions {
  width: number;
  height: number;
  depth: number;
  radius: number;
}

export interface EditorBlock {
  id: string;
  name: string;
  geometry: Geometry;
  kind: BlockKind;
  position: Vec3;
  /** Euler rotation in degrees. */
  rotation: Vec3;
  scale: Vec3;
  dimensions: Dimensions;
  color: string;
  opacity: number;
  collision: CollisionDef;
  groupId?: string;
  modelUrl?: string;
  modelName?: string;
  conveyor?: ConveyorParams;
  bounce?: BounceParams;
  vent?: VentParams;
  spawn?: SpawnParams;
}

export type GroundShape = "rectangle" | "circle" | "polygon";

export interface GroundDef {
  shape: GroundShape;
  width: number;
  depth: number;
  radius: number;
  /** x/z point list used only when shape === "polygon". */
  points: [number, number][];
  color: string;
}

export interface MapDocument {
  version: 1;
  name: string;
  ground: GroundDef;
  blocks: EditorBlock[];
}

export const KIND_LABELS: Record<BlockKind, string> = {
  solid: "Solide",
  bounce: "Rebond",
  vent: "Ventilateur",
  conveyor: "Tapis roulant",
  cover: "Toit couvert",
  spawn: "Point d'apparition",
};

export const KIND_COLORS: Record<BlockKind, string> = {
  solid: "#8b8f9a",
  bounce: "#ff5da2",
  vent: "#4fd1ff",
  conveyor: "#ffb84f",
  cover: "#9a7bff",
  spawn: "#4fff8e",
};

export function createDefaultGround(): GroundDef {
  return {
    shape: "rectangle",
    width: 80,
    depth: 60,
    radius: 30,
    points: [],
    color: "#3a4048",
  };
}

export function createDefaultDocument(): MapDocument {
  return {
    version: 1,
    name: "Nouvelle map",
    ground: createDefaultGround(),
    blocks: [],
  };
}

let counter = 0;
export function nextId(prefix: string): string {
  counter += 1;
  return `${prefix}_${Date.now().toString(36)}_${counter}`;
}
