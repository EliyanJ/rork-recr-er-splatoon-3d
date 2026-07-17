import type { EditorBlock, MapDocument } from "@/types/mapEditor";

/** Converts any blob: URLs on imported models to embedded data URLs so the
 * exported JSON is fully self-contained and can be reloaded anywhere. */
async function inlineModelUrls(blocks: EditorBlock[]): Promise<EditorBlock[]> {
  return Promise.all(
    blocks.map(async (b) => {
      if (b.geometry !== "imported" || !b.modelUrl || !b.modelUrl.startsWith("blob:")) return b;
      try {
        const res = await fetch(b.modelUrl);
        const blob = await res.blob();
        const dataUrl: string = await new Promise((resolve, reject) => {
          const reader = new FileReader();
          reader.onload = () => resolve(reader.result as string);
          reader.onerror = reject;
          reader.readAsDataURL(blob);
        });
        return { ...b, modelUrl: dataUrl };
      } catch {
        return b;
      }
    }),
  );
}

export async function exportDocument(doc: MapDocument): Promise<void> {
  const blocks = await inlineModelUrls(doc.blocks);
  const payload: MapDocument = { ...doc, blocks };
  const json = JSON.stringify(payload, null, 2);
  const blob = new Blob([json], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const a = window.document.createElement("a");
  a.href = url;
  const safeName = doc.name.trim().length > 0 ? doc.name.trim().replace(/\s+/g, "_") : "map";
  a.download = `${safeName}.inkmap.json`;
  a.click();
  URL.revokeObjectURL(url);
}

export function readDocumentFile(file: File): Promise<MapDocument> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => {
      try {
        const parsed = JSON.parse(reader.result as string) as MapDocument;
        if (!parsed || parsed.version !== 1 || !Array.isArray(parsed.blocks)) {
          reject(new Error("Fichier de map invalide."));
          return;
        }
        resolve(parsed);
      } catch (err) {
        reject(err);
      }
    };
    reader.onerror = reject;
    reader.readAsText(file);
  });
}
