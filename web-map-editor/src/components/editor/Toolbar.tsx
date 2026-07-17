import { useRef } from "react";
import {
  Box,
  Circle,
  Cylinder,
  Download,
  Loader2,
  Move,
  Play,
  Redo2,
  RotateCw,
  Scaling,
  Square,
  Triangle,
  Undo2,
  Upload,
  Waypoints,
} from "lucide-react";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Separator } from "@/components/ui/separator";
import { useEditorStore } from "@/store/useEditorStore";
import { exportDocument, readDocumentFile } from "@/lib/exportImport";
import { toast } from "sonner";

/** Top bar: add shapes, transform-mode switches, play/edit toggle, and the
 * export / import buttons for the map file. */
export default function Toolbar() {
  const addBlock = useEditorStore((s) => s.addBlock);
  const transformMode = useEditorStore((s) => s.transformMode);
  const setTransformMode = useEditorStore((s) => s.setTransformMode);
  const viewMode = useEditorStore((s) => s.viewMode);
  const setViewMode = useEditorStore((s) => s.setViewMode);
  const documentName = useEditorStore((s) => s.document.name);
  const renameDocument = useEditorStore((s) => s.renameDocument);
  const document = useEditorStore((s) => s.document);
  const loadDocument = useEditorStore((s) => s.loadDocument);
  const undo = useEditorStore((s) => s.undo);
  const redo = useEditorStore((s) => s.redo);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const importInputRef = useRef<HTMLInputElement>(null);
  const pendingImportRef = useRef(false);

  const handleImportModel = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    const url = URL.createObjectURL(file);
    addBlock("imported", {
      modelUrl: url,
      modelName: file.name,
      name: file.name.replace(/\.(glb|gltf)$/i, ""),
    });
    e.target.value = "";
  };

  const handleImportMap = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    try {
      pendingImportRef.current = true;
      const doc = await readDocumentFile(file);
      loadDocument(doc);
      toast.success("Map chargée.");
    } catch {
      toast.error("Impossible de lire ce fichier de map.");
    } finally {
      pendingImportRef.current = false;
      e.target.value = "";
    }
  };

  return (
    <div className="flex flex-wrap items-center gap-2 border-b border-border bg-card px-3 py-2">
      <Input
        value={documentName}
        onChange={(e) => renameDocument(e.target.value)}
        className="h-8 w-40 text-sm"
        placeholder="Nom de la map"
      />
      <Separator orientation="vertical" className="h-6" />

      <Button size="sm" variant="secondary" onClick={() => addBlock("box")}>
        <Box className="mr-1 h-4 w-4" /> Boîte
      </Button>
      <Button size="sm" variant="secondary" onClick={() => addBlock("cylinder")}>
        <Cylinder className="mr-1 h-4 w-4" /> Cylindre
      </Button>
      <Button size="sm" variant="secondary" onClick={() => addBlock("sphere")}>
        <Circle className="mr-1 h-4 w-4" /> Sphère
      </Button>
      <Button size="sm" variant="secondary" onClick={() => addBlock("prism")}>
        <Triangle className="mr-1 h-4 w-4" /> Prisme
      </Button>
      <Button size="sm" variant="secondary" onClick={() => fileInputRef.current?.click()}>
        <Waypoints className="mr-1 h-4 w-4" /> Importer un modèle
      </Button>
      <input
        ref={fileInputRef}
        type="file"
        accept=".glb,.gltf"
        className="hidden"
        onChange={handleImportModel}
      />

      <Separator orientation="vertical" className="h-6" />

      <div className="flex items-center gap-1 rounded-md bg-muted p-1">
        <Button
          size="icon"
          variant={transformMode === "translate" ? "default" : "ghost"}
          className="h-7 w-7"
          onClick={() => setTransformMode("translate")}
          title="Déplacer (G)"
        >
          <Move className="h-4 w-4" />
        </Button>
        <Button
          size="icon"
          variant={transformMode === "rotate" ? "default" : "ghost"}
          className="h-7 w-7"
          onClick={() => setTransformMode("rotate")}
          title="Tourner (R)"
        >
          <RotateCw className="h-4 w-4" />
        </Button>
        <Button
          size="icon"
          variant={transformMode === "scale" ? "default" : "ghost"}
          className="h-7 w-7"
          onClick={() => setTransformMode("scale")}
          title="Étirer (S)"
        >
          <Scaling className="h-4 w-4" />
        </Button>
      </div>

      <Button size="icon" variant="ghost" className="h-8 w-8" onClick={undo} title="Annuler">
        <Undo2 className="h-4 w-4" />
      </Button>
      <Button size="icon" variant="ghost" className="h-8 w-8" onClick={redo} title="Rétablir">
        <Redo2 className="h-4 w-4" />
      </Button>

      <div className="flex-1" />

      <Button
        size="sm"
        variant={viewMode === "play" ? "default" : "outline"}
        onClick={() => setViewMode(viewMode === "play" ? "edit" : "play")}
      >
        {viewMode === "play" ? (
          <>
            <Loader2 className="mr-1 h-4 w-4" /> Quitter le test
          </>
        ) : (
          <>
            <Play className="mr-1 h-4 w-4" /> Tester à pied
          </>
        )}
      </Button>

      <Button size="sm" variant="outline" onClick={() => importInputRef.current?.click()}>
        <Upload className="mr-1 h-4 w-4" /> Charger une map
      </Button>
      <input
        ref={importInputRef}
        type="file"
        accept=".json"
        className="hidden"
        onChange={handleImportMap}
      />

      <Button size="sm" onClick={() => exportDocument(document)}>
        <Download className="mr-1 h-4 w-4" /> Exporter
      </Button>
    </div>
  );
}
