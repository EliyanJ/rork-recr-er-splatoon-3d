import EditorScene from "@/components/editor/EditorScene";
import HierarchyPanel from "@/components/editor/HierarchyPanel";
import PropertiesPanel from "@/components/editor/PropertiesPanel";
import Toolbar from "@/components/editor/Toolbar";
import { useEditorStore } from "@/store/useEditorStore";

/** Ink Arena 3D map editor — a standalone blockout tool: build arenas with
 * primitive shapes, tag interactive gadgets, and export a JSON file used to
 * generate the actual RealityKit map in the game. */
const Index = () => {
  const viewMode = useEditorStore((s) => s.viewMode);

  return (
    <div className="flex h-screen w-screen flex-col overflow-hidden bg-background text-foreground">
      <Toolbar />
      <div className="flex flex-1 overflow-hidden">
        {viewMode === "edit" && <HierarchyPanel />}
        <div className="relative flex-1">
          <EditorScene />
          {viewMode === "play" && (
            <div className="pointer-events-none absolute inset-x-0 bottom-4 flex flex-col items-center gap-1 text-xs text-white/80">
              <p className="rounded bg-black/50 px-3 py-1">
                Clique dans la vue pour verrouiller la souris — ZQSD/WASD pour marcher, Espace pour sauter, Échap pour sortir
              </p>
            </div>
          )}
        </div>
        {viewMode === "edit" && <PropertiesPanel />}
      </div>
    </div>
  );
};

export default Index;
