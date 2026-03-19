extends RefCounted

const MastMaterialHelper = preload("res://scripts/props/mast_material_helper.gd")
const MastSmokeHelper = preload("res://scripts/props/mast_smoke_helper.gd")

# Facade for mast visual concerns.
#
# `mast.gd` still talks to one helper, but the actual responsibilities are now split into:
# - MastMaterialHelper: shader/material instance ownership and parameter updates
# - MastSmokeHelper: burn smoke lifecycle and particle tuning

static func apply_sail_material_settings(mast: Node3D, burn_mask_a: Texture2D, burn_mask_b: Texture2D, burn_mask_c: Texture2D) -> void:
	MastMaterialHelper.apply_sail_material_settings(mast, burn_mask_a, burn_mask_b, burn_mask_c)

static func ensure_sail_smoke(mast: Node3D, smoke_scene: PackedScene) -> Node3D:
	return MastSmokeHelper.ensure_sail_smoke(mast, smoke_scene)

static func update_sail_smoke(mast: Node3D, smoke_scene: PackedScene) -> void:
	MastSmokeHelper.update_sail_smoke(mast, smoke_scene)

static func ensure_sail_material(mast: Node3D, mesh: MeshInstance3D) -> ShaderMaterial:
	return MastMaterialHelper.ensure_sail_material(mast, mesh)

static func apply_deform_bounds(mesh: MeshInstance3D, mat: ShaderMaterial) -> void:
	MastMaterialHelper.apply_deform_bounds(mesh, mat)
