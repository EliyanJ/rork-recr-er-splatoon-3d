import { create } from "zustand";

import {
  createDefaultDocument,
  createDefaultGround,
  nextId,
  type BlockKind,
  type EditorBlock,
  type Geometry,
  type GroundDef,
  type MapDocument,
} from "@/types/mapEditor";

export type TransformMode = "translate" | "rotate" | "scale";
export type ViewMode = "edit" | "play";

interface EditorState {
  document: MapDocument;
  selectedIds: string[];
  transformMode: TransformMode;
  viewMode: ViewMode;
  groundEditMode: boolean;
  history: MapDocument[];
  future: MapDocument[];

  addBlock: (geometry: Geometry, overrides?: Partial<EditorBlock>) => string;
  updateBlock: (id: string, patch: Partial<EditorBlock>, opts?: { commit?: boolean }) => void;
  updateBlocks: (ids: string[], patch: Partial<EditorBlock>) => void;
  removeSelected: () => void;
  duplicateSelected: () => void;
  groupSelected: () => void;
  ungroupSelected: () => void;
  setSelection: (ids: string[]) => void;
  toggleSelection: (id: string, additive: boolean) => void;
  clearSelection: () => void;
  setTransformMode: (mode: TransformMode) => void;
  setViewMode: (mode: ViewMode) => void;
  setGround: (patch: Partial<GroundDef>) => void;
  setGroundEditMode: (on: boolean) => void;
  addGroundPoint: (x: number, z: number) => void;
  resetGroundPoints: () => void;
  loadDocument: (doc: MapDocument) => void;
  resetDocument: () => void;
  renameDocument: (name: string) => void;
  commitHistory: () => void;
  undo: () => void;
  redo: () => void;
}

function cloneDoc(doc: MapDocument): MapDocument {
  return JSON.parse(JSON.stringify(doc));
}

function defaultDimensions(geometry: Geometry) {
  switch (geometry) {
    case "box":
      return { width: 4, height: 3, depth: 4, radius: 1 };
    case "cylinder":
      return { width: 1, height: 4, depth: 1, radius: 2 };
    case "sphere":
      return { width: 1, height: 1, depth: 1, radius: 2 };
    case "prism":
      return { width: 4, height: 3, depth: 4, radius: 1 };
    case "imported":
      return { width: 1, height: 1, depth: 1, radius: 1 };
  }
}

function defaultKindParams(kind: BlockKind) {
  switch (kind) {
    case "conveyor":
      return { conveyor: { speed: 3, direction: 0 } };
    case "bounce":
      return { bounce: { force: 12 } };
    case "vent":
      return { vent: { force: 10, height: 6 } };
    case "spawn":
      return { spawn: { team: "a" as const } };
    default:
      return {};
  }
}

export const useEditorStore = create<EditorState>((set, get) => ({
  document: createDefaultDocument(),
  selectedIds: [],
  transformMode: "translate",
  viewMode: "edit",
  groundEditMode: false,
  history: [],
  future: [],

  addBlock: (geometry, overrides) => {
    const id = nextId("block");
    const kind = overrides?.kind ?? "solid";
    const block: EditorBlock = {
      id,
      name: overrides?.name ?? `${geometry}_${id.slice(-4)}`,
      geometry,
      kind,
      position: overrides?.position ?? { x: 0, y: 1.5, z: 0 },
      rotation: overrides?.rotation ?? { x: 0, y: 0, z: 0 },
      scale: overrides?.scale ?? { x: 1, y: 1, z: 1 },
      dimensions: overrides?.dimensions ?? defaultDimensions(geometry),
      color: overrides?.color ?? "#8b8f9a",
      opacity: overrides?.opacity ?? 1,
      collision: overrides?.collision ?? {
        mode: "auto",
        size: { x: 4, y: 3, z: 4 },
        offset: { x: 0, y: 0, z: 0 },
      },
      ...defaultKindParams(kind),
      ...overrides,
    };
    set((s) => {
      const doc = cloneDoc(s.document);
      doc.blocks.push(block);
      return {
        document: doc,
        selectedIds: [id],
        history: [...s.history, cloneDoc(s.document)].slice(-50),
        future: [],
      };
    });
    return id;
  },

  updateBlock: (id, patch) => {
    set((s) => {
      const doc = cloneDoc(s.document);
      const idx = doc.blocks.findIndex((b) => b.id === id);
      if (idx === -1) return {};
      doc.blocks[idx] = { ...doc.blocks[idx], ...patch };
      return { document: doc };
    });
  },

  updateBlocks: (ids, patch) => {
    set((s) => {
      const doc = cloneDoc(s.document);
      doc.blocks = doc.blocks.map((b) => (ids.includes(b.id) ? { ...b, ...patch } : b));
      return { document: doc };
    });
  },

  removeSelected: () => {
    set((s) => {
      if (s.selectedIds.length === 0) return {};
      const doc = cloneDoc(s.document);
      doc.blocks = doc.blocks.filter((b) => !s.selectedIds.includes(b.id));
      return {
        document: doc,
        selectedIds: [],
        history: [...s.history, cloneDoc(s.document)].slice(-50),
        future: [],
      };
    });
  },

  duplicateSelected: () => {
    set((s) => {
      if (s.selectedIds.length === 0) return {};
      const doc = cloneDoc(s.document);
      const idMap = new Map<string, string>();
      const groupIdMap = new Map<string, string>();
      const selected = doc.blocks.filter((b) => s.selectedIds.includes(b.id));
      const copies: EditorBlock[] = selected.map((b) => {
        const newId = nextId("block");
        idMap.set(b.id, newId);
        let newGroupId = b.groupId;
        if (b.groupId) {
          if (!groupIdMap.has(b.groupId)) groupIdMap.set(b.groupId, nextId("group"));
          newGroupId = groupIdMap.get(b.groupId);
        }
        return {
          ...b,
          id: newId,
          name: `${b.name}_copie`,
          groupId: newGroupId,
          position: { x: b.position.x + 2, y: b.position.y, z: b.position.z + 2 },
        };
      });
      doc.blocks.push(...copies);
      return {
        document: doc,
        selectedIds: copies.map((c) => c.id),
        history: [...s.history, cloneDoc(s.document)].slice(-50),
        future: [],
      };
    });
  },

  groupSelected: () => {
    set((s) => {
      if (s.selectedIds.length < 2) return {};
      const groupId = nextId("group");
      const doc = cloneDoc(s.document);
      doc.blocks = doc.blocks.map((b) =>
        s.selectedIds.includes(b.id) ? { ...b, groupId } : b,
      );
      return { document: doc, history: [...s.history, cloneDoc(s.document)].slice(-50), future: [] };
    });
  },

  ungroupSelected: () => {
    set((s) => {
      const doc = cloneDoc(s.document);
      doc.blocks = doc.blocks.map((b) =>
        s.selectedIds.includes(b.id) ? { ...b, groupId: undefined } : b,
      );
      return { document: doc, history: [...s.history, cloneDoc(s.document)].slice(-50), future: [] };
    });
  },

  setSelection: (ids) => set({ selectedIds: ids }),

  toggleSelection: (id, additive) => {
    set((s) => {
      if (!additive) return { selectedIds: [id] };
      const has = s.selectedIds.includes(id);
      return {
        selectedIds: has ? s.selectedIds.filter((x) => x !== id) : [...s.selectedIds, id],
      };
    });
  },

  clearSelection: () => set({ selectedIds: [] }),

  setTransformMode: (mode) => set({ transformMode: mode }),
  setViewMode: (mode) => set({ viewMode: mode, selectedIds: mode === "play" ? [] : get().selectedIds }),

  setGround: (patch) => {
    set((s) => {
      const doc = cloneDoc(s.document);
      doc.ground = { ...doc.ground, ...patch };
      return { document: doc };
    });
  },

  setGroundEditMode: (on) => set({ groundEditMode: on }),

  addGroundPoint: (x, z) => {
    set((s) => {
      const doc = cloneDoc(s.document);
      doc.ground.points = [...doc.ground.points, [x, z]];
      return { document: doc };
    });
  },

  resetGroundPoints: () => {
    set((s) => {
      const doc = cloneDoc(s.document);
      doc.ground.points = [];
      return { document: doc };
    });
  },

  loadDocument: (doc) => set({ document: doc, selectedIds: [], history: [], future: [] }),

  resetDocument: () =>
    set({
      document: createDefaultDocument(),
      selectedIds: [],
      history: [],
      future: [],
      groundEditMode: false,
    }),

  renameDocument: (name) => {
    set((s) => ({ document: { ...s.document, name } }));
  },

  commitHistory: () => {
    set((s) => ({ history: [...s.history, cloneDoc(s.document)].slice(-50), future: [] }));
  },

  undo: () => {
    set((s) => {
      if (s.history.length === 0) return {};
      const prev = s.history[s.history.length - 1];
      return {
        document: prev,
        history: s.history.slice(0, -1),
        future: [cloneDoc(s.document), ...s.future].slice(0, 50),
        selectedIds: [],
      };
    });
  },

  redo: () => {
    set((s) => {
      if (s.future.length === 0) return {};
      const next = s.future[0];
      return {
        document: next,
        future: s.future.slice(1),
        history: [...s.history, cloneDoc(s.document)].slice(-50),
        selectedIds: [],
      };
    });
  },
}));

export { createDefaultGround };
