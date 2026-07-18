# tools/

Utilities for maintaining the Ink Arena 3D asset pipeline.

## strip_anim_usdz.py

Strips the mesh, material and packaged textures out of animation-only clips
(`Resources/*-anim-*.usdz`), keeping only the skeleton + `SkelAnimation` needed
to replay the clip on the character's shared base model.

### Why

Meshy exports each animation clip as a full USDZ (mesh + skeleton + skinning +
~1024² texture ≈ 3–6 MB). Since the chantier 1 animation refactor, the runtime
plays a clip's `AnimationResource` directly on the character's single base model
(`AnimationClipStore` decodes each clip once and drops the mesh), so the
geometry and texture baked into every clip are dead weight. Stripping them
brings each clip from ~6 MB down to <1 MB.

> **Dependency:** run this ONLY after the chantier 1 animation system is merged
> and validated in-game. The old system cloned the clip's mesh; stripping it
> before the refactor would break every animation.

### Install

```sh
pip install usd-core
```

### Usage

```sh
# Preview what would change (writes nothing):
python3 strip_anim_usdz.py --resources ../InkArena3D/Resources --dry-run

# Strip in place, keeping a .bak copy of each original:
python3 strip_anim_usdz.py --resources ../InkArena3D/Resources --backup

# Plan B — if RealityKit refuses a mesh-less skeleton USDZ, keep a 1-triangle
# dummy mesh bound to the skeleton instead (test on ONE clip first):
python3 strip_anim_usdz.py --resources ../InkArena3D/Resources --keep-dummy-mesh
```

### Flags

| Flag                | Effect                                                        |
| ------------------- | ------------------------------------------------------------ |
| `--resources PATH`  | Folder holding the clips (required).                          |
| `--pattern GLOB`    | Which files to process (default `*-anim-*.usdz`).             |
| `--dry-run`         | Report only; write nothing.                                  |
| `--keep-dummy-mesh` | Keep a degenerate 1-triangle skinned mesh (Plan B fallback). |
| `--backup`          | Copy each original to `<name>.usdz.bak` before writing.       |

### Safety

Each rewritten package is re-opened and verified to still expose a
`UsdSkelAnimation` whose joint order matches the original. Any clip that fails
verification is left untouched and reported as an error, so a bad strip can
never silently ship.

### Validation after running

1. `runChecks` (build).
2. Launch a match and confirm every clip still animates (hero + bots, idle ↔
   run crossfade, hit/splat one-shots). Under the hood this checks that
   `Entity(named:)` still exposes `availableAnimations.first != nil`.
3. Confirm the `.ipa`/archive size dropped by ≥100 MB.
