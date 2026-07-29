#!/usr/bin/env python3
"""Strip mesh + material + textures from animation-only USDZ clips.

Meshy exports every animation clip as a full USDZ (mesh + skeleton + skinning +
texture ~2.3 MB). After the chantier 1 animation refactor, the runtime replays
the clip's `AnimationResource` directly on the character's shared base model, so
the mesh/material/texture inside each *-anim-* clip is dead weight (~6 MB each).

!!! REGRESSION HISTORY — READ BEFORE USING !!!

Removing every Mesh prim BREAKS ALL ANIMATION IN THE GAME. RealityKit only
exposes a skeletal animation through `entity.availableAnimations` when the USDZ
still contains a mesh bound to the skeleton. With the mesh gone the package
still validates at the USD level (Skeleton + SkelAnimation are intact, joint
order unchanged), so this tool's own verification passed — but at runtime
`availableAnimations` came back EMPTY, no clip was ever cached, and every
character slid around the arena in a frozen pose with no error logged.

Therefore mesh removal is NO LONGER THE DEFAULT. The default now collapses each
skinned mesh to a single degenerate triangle that stays bound to the skeleton:
nearly the same size saving, but the structure RealityKit requires survives.
USD-level verification CANNOT prove a clip still animates in RealityKit — any
change here must be confirmed on a real device before shipping.

Usage:
    pip install usd-core
    python3 strip_anim_usdz.py --resources ../InkArena3D/Resources
    python3 strip_anim_usdz.py --resources ../InkArena3D/Resources --dry-run

Flags:
    --resources PATH   Folder holding the *-anim-*.usdz clips (required).
    --pattern GLOB      Which files to process (default "*-anim-*.usdz").
    --exclude GLOB      Files to skip, repeatable. Defaults to
                        "*-anim-idle.usdz": the base character models are static
                        (no skeleton), so the rigged idle clip IS the animatable
                        body that gets cloned and displayed. Stripping its mesh
                        would leave invisible characters, so a plain run can
                        never touch them.
    --dry-run           Report what would change; write nothing.
    --remove-mesh       Drop every Mesh prim entirely. KNOWN BROKEN at runtime
                        (see above). Kept only for experimentation.
    --backup            Copy each original to <name>.usdz.bak before writing.

Safety: every rewritten package is re-opened and verified to still expose a
`UsdSkelAnimation` whose joint order matches the original, AND (unless
--remove-mesh) to still carry a skeleton-bound mesh.
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


def has_skinned_mesh(stage: "Usd.Stage") -> bool:
    """True when a Mesh bound to the skeleton survives — RealityKit needs one to
    expose the clip through `availableAnimations`."""
    for prim in stage.Traverse():
        if prim.IsA(UsdGeom.Mesh) and prim.HasAPI(UsdSkel.BindingAPI):
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

    # Collapse every skinned mesh to a single degenerate triangle. The
    # SkelBindingAPI (jointIndices/jointWeights) is re-authored so the lone
    # triangle stays bound to joint 0 — enough for RealityKit to treat the
    # asset as a skinned model while adding ~0 bytes.
    for path in dummy_targets:
        prim = stage.GetPrimAtPath(path)
        mesh = UsdGeom.Mesh(prim)
        mesh.GetPointsAttr().Set(
            Vt.Vec3fArray([Gf.Vec3f(0, 0, 0), Gf.Vec3f(0, 0, 0), Gf.Vec3f(0, 0, 0)])
        )
        mesh.GetFaceVertexCountsAttr().Set(Vt.IntArray([3]))
        mesh.GetFaceVertexIndicesAttr().Set(Vt.IntArray([0, 1, 2]))
        if mesh.GetNormalsAttr().HasAuthoredValue():
            mesh.GetNormalsAttr().Set(Vt.Vec3fArray([Gf.Vec3f(0, 1, 0)] * 3))
        binding = UsdSkel.BindingAPI(prim)
        binding.CreateJointIndicesPrimvar(constant=False, elementSize=1).Set(
            Vt.IntArray([0, 0, 0])
        )
        binding.CreateJointWeightsPrimvar(constant=False, elementSize=1).Set(
            Vt.FloatArray([1.0, 1.0, 1.0])
        )
        # Drop the UV set and any other leftover primvar: they still hold
        # per-vertex arrays for the original dense mesh (megabytes) and are
        # meaningless now that the geometry is one triangle. The two skinning
        # primvars must survive — they are what keeps the mesh bound.
        keep = {"primvars:skel:jointIndices", "primvars:skel:jointWeights"}
        for primvar in UsdGeom.PrimvarsAPI(prim).GetPrimvars():
            name = primvar.GetName()
            if name not in keep:
                prim.RemoveProperty(name)
        # A material binding would re-reference the textures we are removing,
        # which is exactly what made CreateNewUsdzPackage fail.
        UsdShade.MaterialBindingAPI(prim).UnbindAllBindings()
        # GeomSubsets exist only to bind per-face materials; their face-index
        # arrays are sized for the original mesh.
        for child in prim.GetChildren():
            if child.IsA(UsdGeom.Subset):
                to_remove.append(child.GetPath().pathString)

    # Always strip materials, shaders and lights — in dummy-mesh mode too.
    # Leaving them behind keeps the textures/*.png references alive, and
    # CreateNewUsdzPackage then fails because those files are not on disk.
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
        # The check that would have caught the frozen-character regression:
        # without a skeleton-bound mesh RealityKit exposes no animation at all.
        if keep_dummy_mesh and not has_skinned_mesh(check):
            return False, "verification failed: no skeleton-bound mesh survived"

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
    parser.add_argument(
        "--exclude",
        action="append",
        default=None,
        help="Glob of files to skip (repeatable). Default: *-anim-idle.usdz",
    )
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument(
        "--remove-mesh",
        action="store_true",
        help="Drop Mesh prims entirely. KNOWN BROKEN at runtime.",
    )
    parser.add_argument("--backup", action="store_true")
    args = parser.parse_args()
    # Inverted default: keeping a skeleton-bound dummy mesh is the safe mode.
    keep_dummy_mesh = not args.remove_mesh
    if args.remove_mesh:
        print(
            "WARNING: --remove-mesh produced characters with NO animation at "
            "runtime. Verify on a real device before shipping.\n"
        )

    import fnmatch

    resources = os.path.abspath(args.resources)
    if not os.path.isdir(resources):
        return int(bool(sys.stderr.write(f"Not a directory: {resources}\n")))

    excludes = args.exclude if args.exclude is not None else ["*-anim-idle.usdz"]
    clips = sorted(
        os.path.join(resources, f)
        for f in os.listdir(resources)
        if fnmatch.fnmatch(f, args.pattern)
        and not any(fnmatch.fnmatch(f, e) for e in excludes)
    )
    if excludes:
        print(f"Excluding: {', '.join(excludes)}")
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
            path, keep_dummy_mesh, args.dry_run, args.backup
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
