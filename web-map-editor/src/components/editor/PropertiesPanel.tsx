import { ScrollArea } from "@/components/ui/scroll-area";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Separator } from "@/components/ui/separator";
import { Slider } from "@/components/ui/slider";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Button } from "@/components/ui/button";
import { useEditorStore } from "@/store/useEditorStore";
import {
  KIND_LABELS,
  type BlockKind,
  type CollisionMode,
  type GroundShape,
} from "@/types/mapEditor";

function NumberRow({
  label,
  value,
  onChange,
  step = 0.1,
}: {
  label: string;
  value: number;
  onChange: (v: number) => void;
  step?: number;
}) {
  return (
    <div className="flex items-center justify-between gap-2">
      <Label className="w-16 shrink-0 text-xs text-muted-foreground">{label}</Label>
      <Input
        type="number"
        step={step}
        value={Number.isFinite(value) ? value : 0}
        onChange={(e) => onChange(parseFloat(e.target.value) || 0)}
        className="h-7 text-xs"
      />
    </div>
  );
}

function SectionTitle({ children }: { children: React.ReactNode }) {
  return <p className="mb-1.5 mt-3 text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">{children}</p>;
}

/** Right panel: full inspector for the current selection (transform,
 * dimensions, kind, hitbox) or the ground settings when nothing is selected. */
export default function PropertiesPanel() {
  const selectedIds = useEditorStore((s) => s.selectedIds);
  const blocks = useEditorStore((s) => s.document.blocks);
  const updateBlock = useEditorStore((s) => s.updateBlock);
  const ground = useEditorStore((s) => s.document.ground);
  const setGround = useEditorStore((s) => s.setGround);
  const groundEditMode = useEditorStore((s) => s.groundEditMode);
  const setGroundEditMode = useEditorStore((s) => s.setGroundEditMode);
  const resetGroundPoints = useEditorStore((s) => s.resetGroundPoints);

  const block = selectedIds.length === 1 ? blocks.find((b) => b.id === selectedIds[0]) : undefined;

  if (!block) {
    return (
      <div className="flex h-full w-72 flex-col border-l border-border bg-card">
        <div className="px-3 py-2 text-sm font-semibold text-foreground">Sol de la map</div>
        <Separator />
        <ScrollArea className="flex-1">
          <div className="flex flex-col gap-2 p-3">
            <SectionTitle>Forme</SectionTitle>
            <Select value={ground.shape} onValueChange={(v) => setGround({ shape: v as GroundShape })}>
              <SelectTrigger className="h-8 text-xs">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="rectangle">Rectangle</SelectItem>
                <SelectItem value="circle">Cercle</SelectItem>
                <SelectItem value="polygon">Contour libre</SelectItem>
              </SelectContent>
            </Select>

            {ground.shape === "rectangle" && (
              <>
                <NumberRow label="Largeur" value={ground.width} onChange={(v) => setGround({ width: v })} step={1} />
                <NumberRow label="Profondeur" value={ground.depth} onChange={(v) => setGround({ depth: v })} step={1} />
              </>
            )}
            {ground.shape === "circle" && (
              <NumberRow label="Rayon" value={ground.radius} onChange={(v) => setGround({ radius: v })} step={1} />
            )}
            {ground.shape === "polygon" && (
              <div className="flex flex-col gap-2">
                <p className="text-xs text-muted-foreground">
                  Active le mode édition puis clique sur le sol pour poser les sommets du contour.
                </p>
                <Button
                  size="sm"
                  variant={groundEditMode ? "default" : "secondary"}
                  onClick={() => setGroundEditMode(!groundEditMode)}
                >
                  {groundEditMode ? "Terminer le contour" : "Éditer le contour"}
                </Button>
                <Button size="sm" variant="outline" onClick={resetGroundPoints}>
                  Effacer les sommets ({ground.points.length})
                </Button>
              </div>
            )}

            <SectionTitle>Couleur</SectionTitle>
            <Input
              type="color"
              value={ground.color}
              onChange={(e) => setGround({ color: e.target.value })}
              className="h-8 w-full"
            />

            <SectionTitle>Astuce niveaux</SectionTitle>
            <p className="text-xs text-muted-foreground">
              Pour des terrasses superposées, ajoute des boîtes larges et plates ("floor") à
              différentes hauteurs — elles se comportent comme des sols additionnels.
            </p>
          </div>
        </ScrollArea>
      </div>
    );
  }

  const patch = (p: Partial<typeof block>) => updateBlock(block.id, p);

  return (
    <div className="flex h-full w-72 flex-col border-l border-border bg-card">
      <div className="px-3 py-2 text-sm font-semibold text-foreground">Propriétés</div>
      <Separator />
      <ScrollArea className="flex-1">
        <div className="flex flex-col gap-2 p-3">
          <Label className="text-xs text-muted-foreground">Nom</Label>
          <Input value={block.name} onChange={(e) => patch({ name: e.target.value })} className="h-7 text-xs" />

          <SectionTitle>Position</SectionTitle>
          <NumberRow label="X" value={block.position.x} onChange={(v) => patch({ position: { ...block.position, x: v } })} />
          <NumberRow label="Y" value={block.position.y} onChange={(v) => patch({ position: { ...block.position, y: v } })} />
          <NumberRow label="Z" value={block.position.z} onChange={(v) => patch({ position: { ...block.position, z: v } })} />

          <SectionTitle>Rotation (°)</SectionTitle>
          <NumberRow label="X" value={block.rotation.x} onChange={(v) => patch({ rotation: { ...block.rotation, x: v } })} />
          <NumberRow label="Y" value={block.rotation.y} onChange={(v) => patch({ rotation: { ...block.rotation, y: v } })} />
          <NumberRow label="Z" value={block.rotation.z} onChange={(v) => patch({ rotation: { ...block.rotation, z: v } })} />

          <SectionTitle>Échelle</SectionTitle>
          <NumberRow label="X" value={block.scale.x} onChange={(v) => patch({ scale: { ...block.scale, x: v } })} />
          <NumberRow label="Y" value={block.scale.y} onChange={(v) => patch({ scale: { ...block.scale, y: v } })} />
          <NumberRow label="Z" value={block.scale.z} onChange={(v) => patch({ scale: { ...block.scale, z: v } })} />

          {block.geometry !== "imported" && (
            <>
              <SectionTitle>Dimensions</SectionTitle>
              {(block.geometry === "box" || block.geometry === "prism") && (
                <>
                  <NumberRow label="Larg." value={block.dimensions.width} onChange={(v) => patch({ dimensions: { ...block.dimensions, width: v } })} />
                  <NumberRow label="Haut." value={block.dimensions.height} onChange={(v) => patch({ dimensions: { ...block.dimensions, height: v } })} />
                  <NumberRow label="Prof." value={block.dimensions.depth} onChange={(v) => patch({ dimensions: { ...block.dimensions, depth: v } })} />
                </>
              )}
              {block.geometry === "cylinder" && (
                <>
                  <NumberRow label="Rayon" value={block.dimensions.radius} onChange={(v) => patch({ dimensions: { ...block.dimensions, radius: v } })} />
                  <NumberRow label="Haut." value={block.dimensions.height} onChange={(v) => patch({ dimensions: { ...block.dimensions, height: v } })} />
                </>
              )}
              {block.geometry === "sphere" && (
                <NumberRow label="Rayon" value={block.dimensions.radius} onChange={(v) => patch({ dimensions: { ...block.dimensions, radius: v } })} />
              )}
            </>
          )}

          <SectionTitle>Apparence</SectionTitle>
          <Input type="color" value={block.color} onChange={(e) => patch({ color: e.target.value })} className="h-8 w-full" />
          <div className="flex items-center gap-2">
            <Label className="w-16 shrink-0 text-xs text-muted-foreground">Opacité</Label>
            <Slider
              value={[block.opacity]}
              min={0.1}
              max={1}
              step={0.05}
              onValueChange={([v]) => patch({ opacity: v })}
            />
          </div>

          <SectionTitle>Type de bloc</SectionTitle>
          <Select value={block.kind} onValueChange={(v) => patch({ kind: v as BlockKind })}>
            <SelectTrigger className="h-8 text-xs">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {(Object.keys(KIND_LABELS) as BlockKind[]).map((k) => (
                <SelectItem key={k} value={k}>
                  {KIND_LABELS[k]}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>

          {block.kind === "conveyor" && (
            <>
              <NumberRow
                label="Vitesse"
                value={block.conveyor?.speed ?? 3}
                onChange={(v) => patch({ conveyor: { direction: block.conveyor?.direction ?? 0, speed: v } })}
              />
              <NumberRow
                label="Direction"
                value={block.conveyor?.direction ?? 0}
                onChange={(v) => patch({ conveyor: { speed: block.conveyor?.speed ?? 3, direction: v } })}
                step={5}
              />
            </>
          )}
          {block.kind === "bounce" && (
            <NumberRow
              label="Force"
              value={block.bounce?.force ?? 12}
              onChange={(v) => patch({ bounce: { force: v } })}
              step={1}
            />
          )}
          {block.kind === "vent" && (
            <>
              <NumberRow
                label="Force"
                value={block.vent?.force ?? 10}
                onChange={(v) => patch({ vent: { height: block.vent?.height ?? 6, force: v } })}
                step={1}
              />
              <NumberRow
                label="Portée"
                value={block.vent?.height ?? 6}
                onChange={(v) => patch({ vent: { force: block.vent?.force ?? 10, height: v } })}
                step={0.5}
              />
            </>
          )}
          {block.kind === "spawn" && (
            <Select
              value={block.spawn?.team ?? "a"}
              onValueChange={(v) => patch({ spawn: { team: v as "a" | "b" | "neutral" } })}
            >
              <SelectTrigger className="h-8 text-xs">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="a">Équipe A</SelectItem>
                <SelectItem value="b">Équipe B</SelectItem>
                <SelectItem value="neutral">Neutre</SelectItem>
              </SelectContent>
            </Select>
          )}

          <SectionTitle>Hitbox / collision</SectionTitle>
          <Select
            value={block.collision.mode}
            onValueChange={(v) => patch({ collision: { ...block.collision, mode: v as CollisionMode } })}
          >
            <SelectTrigger className="h-8 text-xs">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="auto">Identique au visuel</SelectItem>
              <SelectItem value="custom">Personnalisée</SelectItem>
              <SelectItem value="none">Aucune (décor)</SelectItem>
            </SelectContent>
          </Select>
          {block.collision.mode === "custom" && (
            <>
              <p className="mt-1 text-[11px] text-muted-foreground">Taille de la hitbox</p>
              <NumberRow label="X" value={block.collision.size.x} onChange={(v) => patch({ collision: { ...block.collision, size: { ...block.collision.size, x: v } } })} />
              <NumberRow label="Y" value={block.collision.size.y} onChange={(v) => patch({ collision: { ...block.collision, size: { ...block.collision.size, y: v } } })} />
              <NumberRow label="Z" value={block.collision.size.z} onChange={(v) => patch({ collision: { ...block.collision, size: { ...block.collision.size, z: v } } })} />
              <p className="mt-1 text-[11px] text-muted-foreground">Décalage de la hitbox</p>
              <NumberRow label="X" value={block.collision.offset.x} onChange={(v) => patch({ collision: { ...block.collision, offset: { ...block.collision.offset, x: v } } })} />
              <NumberRow label="Y" value={block.collision.offset.y} onChange={(v) => patch({ collision: { ...block.collision, offset: { ...block.collision.offset, y: v } } })} />
              <NumberRow label="Z" value={block.collision.offset.z} onChange={(v) => patch({ collision: { ...block.collision, offset: { ...block.collision.offset, z: v } } })} />
            </>
          )}
        </div>
      </ScrollArea>
    </div>
  );
}
