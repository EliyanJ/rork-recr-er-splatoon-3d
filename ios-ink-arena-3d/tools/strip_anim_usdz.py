#!/usr/bin/env python3
"""Strip mesh + material + textures from animation-only USDZ clips.

Meshy exports every animation clip as a full USDZ (mesh + skeleton + skinning +
texture ~2.3 MB). After the chantier 1 animation refactor, the runtime replays
the clip's `AnimationResource` directly on the character's shared base model, so
the mesh/material/texture inside each *-anim-* clip is dead weight (~6 MB each).

This tool keeps only what an `AnimationResource` needs — the `SkelRoot`,
`Skeleton` and `SkelAnimation` prims — and drops every `Mesh`, `Material` and
`Shader`, plus the packaged `textures/` folder. Result: ~6 MB -> <1 MB per clip.

Usage:
    pip install usd-core
    python3 strip_anim_usdz.py --resources ../InkArena3D/Resources
    python3 strip_anim_usdz.py --resources ../InkArena3D/Resources --dry-run
    python3 strip_anim_usdz.py --resources ../InkArena3D/Resources --keep-dummy-mesh

Flags:
    --resources PATH   Folder holding the *-anim-*.usdz clips (required).
    --pattern GLOB      Which files to process (default "*-anim-*.usdz").
    --dry-run           Report what would change; write nothing.
    --keep-dummy-mesh   Plan B: instead of removing every mesh, replace the
                        skinned mesh with a single degenerate triangle still
                        bound to the skeleton. Use only if RealityKit refuses a
                        mesh-less skeleton USDZ (test on ONE file first).
    --backup            Copy each original to <name>.usdz.bak before writing.

Safety: every rewritten package is re-opened and verified to still expose a
`UsdSkelAnimation` whose joint order matches the original. A clip that fails
verification is left untouched and reported as an error.
"""

from __future__ import annotations

import argparse
import os
import shutil
import sys
import tempfile
import zipfile
from typing import Optional

try:
    from pxr import Usd, UsdGeom, UsdShade, UsdSkel, UsdUtils, Sdf, Vt, Gf
except ImportError:
    sys.exit(
        "pxr (usd-core) is required. Install it with:\n    pip install usd-core"
    )


def joint_signature(stage: "Usd.Stage") -> Optional[list[str]]:
    """Return the joint order of the first Skeleton in the stage, or None."""
    for prim in stage.Traverse():
        if prim.IsA(UsdSkel.Skeleton):
            skel = UsdSkel.Skeleton(prim)
            joints = skel.GetJointsAttr().Get()
            if joints:
                return list(joints)
    return None


def has_skel_animation(stage: "Usd.Stage") -> bool:
    for prim in stage.Traverse():
        if prim.IsA(UsdSkel.Animation):
            return True
    return False


def strip_stage(stage: "Usd.Stage", keep_dummy_mesh: bool) -> None:
    """Remove mesh/material/shader prims from `stage` in place."""
    to_remove: list[str] = []
    dummy_targets: list[str] = []
    for prim in stage.Traverse():
        type_name = prim.GetTypeName()
        if prim.IsA(UsdGeom.Mesh):
            if keep_dummy_mesh:
                dummy_targets.append(prim.GetPath().pathString)
            else:
                to_remove.append(prim.GetPath().pathString)
        elif prim.IsA(UsdShade.Material) or prim.IsA(UsdShade.Shader):
            to_remove.append(prim.GetPath().pathString)
        elif "Light" in type_name:
            # Lights (e.g. DomeLight) carry .hdr/.exr texture references that
            # would otherwise be dragged into the repackaged USDZ. A skeletal
            # animation clip needs none of them.
            to_remove.append(prim.GetPath().pathString)

    if keep_dummy_mesh:
        # Collapse every skinned mesh to a single degenerate triangle. The
        # SkelBindingAPI (jointIndices/jointWeights) is re-authored so the lone
        # triangle stays bound to joint 0 — enough for RealityKit to treat the
        # asset as a skinned model while adding ~0 bytes.
        for path in dummy_targets:
            mesh = UsdGeom.Mesh(stage.GetPrimAtPath(path))
            mesh.GetPointsAttr().Set(
                Vt.Vec3fArray([Gf.Vec3f(0, 0, 0), Gf.Vec3f(0, 0, 0), Gf.Vec3f(0, 0, 0)])
            )
            mesh.GetFaceVertexCountsAttr().Set(Vt.IntArray([3]))
            mesh.GetFaceVertexIndicesAttr().Set(Vt.IntArray([0, 1, 2]))
            if mesh.GetNormalsAttr().HasAuthoredValue():
                mesh.GetNormalsAttr().Set(Vt.Vec3fArray([Gf.Vec3f(0, 1, 0)] * 3))
            binding = UsdSkel.BindingAPI(mesh.GetPrim())
            binding.CreateJointIndicesPrimvar(constant=False, elementSize=1).Set(
                Vt.IntArray([0, 0, 0])
            )
            binding.CreateJointWeightsPrimvar(constant=False, elementSize=1).Set(
                Vt.FloatArray([1.0, 1.0, 1.0])
            )
    else:
        # Remove deepest paths first so parents still exist when children go.
        for path in sorted(to_remove, key=lambda p: p.count("/"), reverse=True):
            stage.RemovePrim(Sdf.Path(path))


def process_clip(
    usdz_path: str,
    keep_dummy_mesh: bool,
    dry_run: bool,
    backup: bool,
) -> tuple[bool, str]:
    """Strip one clip. Returns (changed, message)."""
    original_size = os.path.getsize(usdz_path)

    src_stage = Usd.Stage.Open(usdz_path)
    if src_stage is None:
        return False, "could not open stage"
    original_joints = joint_signature(src_stage)
    if original_joints is None:
        return False, "no skeleton found — skipped (not an animation clip?)"
    if not has_skel_animation(src_stage):
        return False, "no UsdSkelAnimation found — skipped"

    if dry_run:
        return True, f"would strip ({original_size / 1_000_000:.1f} MB source)"

    with tempfile.TemporaryDirectory() as tmp:
        # A USDZ is a plain (uncompressed) zip whose root .usdc IS already a
        # self-contained layer — extract it and edit it directly. This avoids
        # Usd.Stage.Flatten() (segfaults on these Meshy skeletal exports) and
        # avoids Export keeping an external reference to the original package
        # (which made CreateNewUsdzPackage embed the whole original inside).
        with zipfile.ZipFile(usdz_path) as archive:
            layer_names = [
                n for n in archive.namelist()
                if n.endswith((".usdc", ".usda", ".usd"))
            ]
            if not layer_names:
                return False, "no USD layer inside package"
            archive.extract(layer_names[0], tmp)
        layer_path = os.path.join(tmp, layer_names[0])

        stage = Usd.Stage.Open(layer_path)
        strip_stage(stage, keep_dummy_mesh)
        # Export to a FRESH file so the crate is rewritten with only the
        # surviving prims (RemovePrim + in-place Save leaves the freed mesh
        # bytes in the crate — Export reclaims them, ~3.3 MB -> ~0.1 MB).
        stripped_path = os.path.join(tmp, "stripped.usdc")
        stage.Export(stripped_path)

        out_path = os.path.join(tmp, "clip.usdz")
        if not UsdUtils.CreateNewUsdzPackage(stripped_path, out_path):
            return False, "CreateNewUsdzPackage failed"

        # Verify before overwriting the original.
        check = Usd.Stage.Open(out_path)
        if check is None or not has_skel_animation(check):
            return False, "verification failed: no animation after strip"
        if joint_signature(check) != original_joints:
            return False, "verification failed: joint order changed"

        if backup:
            shutil.copy2(usdz_path, usdz_path + ".bak")
        shutil.copy2(out_path, usdz_path)

    new_size = os.path.getsize(usdz_path)
    saved = (original_size - new_size) / 1_000_000
    return True, (
        f"{original_size / 1_000_000:.1f} MB -> {new_size / 1_000_000:.1f} MB "
        f"(saved {saved:.1f} MB)"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--resources", required=True, help="Folder with the clips")
    parser.add_argument("--pattern", default="*-anim-*.usdz")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--keep-dummy-mesh", action="store_true")
    parser.add_argument("--backup", action="store_true")
    args = parser.parse_args()

    import fnmatch

    resources = os.path.abspath(args.resources)
    if not os.path.isdir(resources):
        return int(bool(sys.stderr.write(f"Not a directory: {resources}\n")))

    clips = sorted(
        os.path.join(resources, f)
        for f in os.listdir(resources)
        if fnmatch.fnmatch(f, args.pattern)
    )
    if not clips:
        print(f"No files matching {args.pattern!r} in {resources}")
        return 0

    print(f"Found {len(clips)} clip(s) matching {args.pattern!r}\n")
    errors = 0
    total_before = 0
    total_after = 0
    for path in clips:
        before = os.path.getsize(path)
        total_before += before
        ok, message = process_clip(
            path, args.keep_dummy_mesh, args.dry_run, args.backup
        )
        total_after += os.path.getsize(path)
        status = "OK " if ok else "ERR"
        if not ok:
            errors += 1
        print(f"[{status}] {os.path.basename(path)}: {message}")

    print()
    if not args.dry_run:
        print(
            f"Total: {total_before / 1_000_000:.1f} MB -> "
            f"{total_after / 1_000_000:.1f} MB "
            f"(saved {(total_before - total_after) / 1_000_000:.1f} MB)"
        )
    if errors:
        print(f"{errors} clip(s) failed and were left untouched.")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
