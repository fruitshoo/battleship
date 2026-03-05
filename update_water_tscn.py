import re
import uuid

tscn_path = "scenes/effects/water_explosion.tscn"
with open(tscn_path, 'r') as f:
    content = f.read()

# Replace the ext_resource
content = re.sub(
    r'\[ext_resource type="Texture2D" uid="uid://[^"]+" path="res://assets/vfx/particles/water/water_mist\.tga" id="1_mist"\]',
    r'[ext_resource type="Texture2D" uid="uid://exp01flip" path="res://assets/vfx/flipbooks/explosion_01_8x8.tga" id="1_mist"]',
    content
)

# Update Gradient to be water colored (blues and cyans instead of white/gray)
content = re.sub(
    r'colors = PackedColorArray\(0\.85, 0\.92, 1, 0\.5, 1, 1, 1, 0\.7, 0\.8, 0\.9, 1, 0\.4, 0\.6, 0\.8, 1, 0\)',
    r'colors = PackedColorArray(0.6, 0.9, 1, 0.6, 0.3, 0.7, 1, 1.0, 0.1, 0.5, 0.9, 0.8, 0.0, 0.2, 0.6, 0.0)',
    content
)

# Replace Material animation frames
content = re.sub(
    r'particles_anim_h_frames = 4\nparticles_anim_v_frames = 4',
    r'particles_anim_h_frames = 8\nparticles_anim_v_frames = 8',
    content
)

# Increase scale slightly as the explosion texture has a lot of padding
content = re.sub(
    r'size = Vector2\(1\.8, 1\.8\)',
    r'size = Vector2(3.5, 3.5)',
    content
)

# Decrease particle amount since flipbooks are large and one explosion sprite is enough (maybe 2-3)
content = re.sub(
    r'amount = 12',
    r'amount = 3',
    content
)

with open(tscn_path, 'w') as f:
    f.write(content)

print("Updated water_explosion.tscn gradient and animation frames")
