# Asset Pipeline

## Goal

- 같은 종류의 자산은 같은 위치에 둔다.
- 같은 atlas를 공유하는 모델은 Godot에서 중복 텍스처를 만들지 않게 관리한다.
- `glb`와 `gltf separate` 사용 기준을 명확히 한다.

## Model Format Rule

### Default

- 공유 atlas를 쓰는 프랍은 `gltf separate`를 기본으로 사용한다.
- 단일 소품, 테스트 자산, 빠른 임시 확인용만 `glb`를 허용한다.

### Use `gltf separate` when

- 여러 모델이 같은 atlas를 공유한다.
- 텍스처 경로를 직접 관리해야 한다.
- 머티리얼을 여러 프랍에서 공통으로 써야 한다.
- 나중에 텍스처 교체나 정리가 자주 일어날 가능성이 있다.

### Use `glb` when

- 모델 하나가 텍스처 하나를 독립적으로 쓴다.
- 외부 파일 수를 줄이는 편이 더 중요하다.
- 임시 테스트 자산이다.

## Blender Export Rule

### Before export

- 같은 atlas를 쓰는 모델은 같은 `Image` datablock을 공유한다.
- 같은 atlas를 쓰는 모델은 가능한 같은 `Material`을 공유한다.
- 모델마다 packed image를 따로 들고 있지 않게 한다.

### Export choice

- 공유 atlas 프랍: `glTF Separate (.gltf + .bin + textures)`
- 독립 프랍: `glb` 가능

## Folder Rule

`assets/models/props/<asset_name>/`

Examples:

- `assets/models/props/cannon/`
- `assets/models/props/mast/`
- `assets/models/props/sail/`
- `assets/models/props/shield/`

Each asset folder should contain:

- source model file
- related textures
- optional shared material `.tres`

## Naming Rule

### Preferred names

- model: `<asset_name>.gltf` or `<asset_name>.glb`
- albedo: `<asset_name>_albedo.png`
- normal: `<asset_name>_normal.png`
- orm/mask: `<asset_name>_mask.png`
- shared material: `<asset_name>_shared_material.tres`

### Avoid

- duplicated names like `cannon_cannon_albedo.png`
- generated names like `*_Gemini_Generated_*` as the main managed file name
- placing model files directly under `assets/models/props/` without a subfolder

## Scene Rule

Runtime entry scenes go under:

- `scenes/entities/props/`

Examples:

- `barrel_model.tscn`
- `round_shield.tscn`
- `square_shield.tscn`

These scenes may:

- instance the imported model
- apply a shared material
- expose a stable path for gameplay code

## Shared Material Rule

If multiple models use the same atlas:

- treat the imported model as mesh/container only
- apply the final material with `material_override` or shared `.tres`

This is the preferred Godot-side fix when the source asset already exists and re-export is not worth doing immediately.

## Compatibility Files

Some current assets still need compatibility texture names because existing `glb` imports reference them internally.

Examples:

- `cannon_cannon_albedo.png`
- `mast_mast_albedo.png`
- `yardarm_mast_albedo.png`

Rule:

- do not delete these files unless the source model is re-exported
- when re-exporting, remove compatibility files and keep only the preferred names

## Cleanup Rule

Safe to remove when unreferenced:

- old one-off update scripts
- unused effect scripts
- duplicate `.tres` not referenced by any scene or script
- `.DS_Store`

Not safe to remove blindly:

- compatibility textures still referenced by imported `glb`
- imported assets whose path is still baked into `.import` metadata

## Recommended Migration Strategy

1. New shared-atlas props use `gltf separate`.
2. Existing `glb` props stay as-is until they need re-export.
3. Re-export old `glb` assets one by one and remove compatibility texture files afterward.
4. Keep stable gameplay entry scenes in `scenes/entities/props/` even if the underlying import format changes.
