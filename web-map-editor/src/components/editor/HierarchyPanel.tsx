import { Boxes, Copy, Group, Trash2, Ungroup } from "lucide-react";

import { Button } from "@/components/ui/button";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Separator } from "@/components/ui/separator";
import { cn } from "@/lib/utils";
import { useEditorStore } from "@/store/useEditorStore";
import { KIND_LABELS } from "@/types/mapEditor";

/** Left panel: flat list of every block in the map, grouped visually by
 * prefab group, with quick group/duplicate/delete actions. */
export default function HierarchyPanel() {
  const blocks = useEditorStore((s) => s.document.blocks);
  const selectedIds = useEditorStore((s) => s.selectedIds);
  const toggleSelection = useEditorStore((s) => s.toggleSelection);
  const groupSelected = useEditorStore((s) => s.groupSelected);
  const ungroupSelected = useEditorStore((s) => s.ungroupSelected);
  const duplicateSelected = useEditorStore((s) => s.duplicateSelected);
  const removeSelected = useEditorStore((s) => s.removeSelected);

  return (
    <div className="flex h-full w-64 flex-col border-r border-border bg-card">
      <div className="flex items-center gap-2 px-3 py-2 text-sm font-semibold text-foreground">
        <Boxes className="h-4 w-4" /> Blocs ({blocks.length})
      </div>
      <Separator />
      <ScrollArea className="flex-1">
        <div className="flex flex-col gap-0.5 p-1">
          {blocks.length === 0 && (
            <p className="px-2 py-4 text-center text-xs text-muted-foreground">
              Ajoute une forme depuis la barre du haut.
            </p>
          )}
          {blocks.map((b) => (
            <button
              key={b.id}
              onClick={(e) => toggleSelection(b.id, e.shiftKey)}
              className={cn(
                "flex items-center justify-between rounded px-2 py-1.5 text-left text-xs transition-colors",
                selectedIds.includes(b.id)
                  ? "bg-primary/20 text-primary"
                  : "text-muted-foreground hover:bg-muted",
              )}
            >
              <span className="truncate">{b.name}</span>
              <span className="ml-2 shrink-0 text-[10px] opacity-70">{KIND_LABELS[b.kind]}</span>
            </button>
          ))}
        </div>
      </ScrollArea>
      <Separator />
      <div className="grid grid-cols-2 gap-1 p-2">
        <Button size="sm" variant="secondary" onClick={groupSelected} disabled={selectedIds.length < 2}>
          <Group className="mr-1 h-3.5 w-3.5" /> Grouper
        </Button>
        <Button size="sm" variant="secondary" onClick={ungroupSelected} disabled={selectedIds.length === 0}>
          <Ungroup className="mr-1 h-3.5 w-3.5" /> Dégrouper
        </Button>
        <Button size="sm" variant="secondary" onClick={duplicateSelected} disabled={selectedIds.length === 0}>
          <Copy className="mr-1 h-3.5 w-3.5" /> Dupliquer
        </Button>
        <Button size="sm" variant="destructive" onClick={removeSelected} disabled={selectedIds.length === 0}>
          <Trash2 className="mr-1 h-3.5 w-3.5" /> Supprimer
        </Button>
      </div>
    </div>
  );
}
