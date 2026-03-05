import sys

tscn_path = "scenes/effects/water_explosion.tscn"
with open(tscn_path, 'r') as f:
    content = f.read()

# Remove the splash texture ext_resource
content = content.replace('[ext_resource type="Texture2D" uid="uid://wxwdy0sxs71g" path="res://assets/vfx/particles/water/water_splash_small.png" id="1_splash"]\n', '')

# Replace the main WaterExplosion node to use the mist materials
import re
content = re.sub(r'\[node name="WaterExplosion" type="GPUParticles3D".*?script = ExtResource\("3_script"\)',
                 r'[node name="WaterExplosion" type="GPUParticles3D" format=3 uid="uid://1591442480"]\n'
                 r'emitting = false\n'
                 r'amount = 12\n'
                 r'lifetime = 1.4\n'
                 r'one_shot = true\n'
                 r'explosiveness = 0.9\n'
                 r'randomness = 0.5\n'
                 r'process_material = SubResource("ParticleProcessMaterial_mist")\n'
                 r'draw_pass_1 = SubResource("QuadMesh_mist")\n'
                 r'script = ExtResource("3_script")', content, flags=re.DOTALL)

# Remove the child Mist node entirely
content = re.sub(r'\[node name="Mist" type="GPUParticles3D" parent="."[^\[]*$', '', content, flags=re.DOTALL)

with open(tscn_path, 'w') as f:
    f.write(content)

print("Updated water_explosion.tscn")
