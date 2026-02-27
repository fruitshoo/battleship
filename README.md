# Battleship

A dynamic 3D naval combat and boarding action game built with **Godot Engine 4**. Navigate the high seas, manage your crew, engage in strategic ship-to-ship combat, and capture enemy vessels!

## Core Gameplay Mechanics

### 1. Realistic Ship Navigation & Physics
- **Wind & Sail Physics:** Utilize the wind direction to your advantage. Adjust the sail angle (`Q` / `E`) to catch the wind and maximize thrust.
- **Rudder Control:** Steer the ship (`A` / `D`) realistically based on the rudder angle and current speed.
- **Rowing System:** Press `W` to row, providing a temporary speed boost at the cost of stamina. Perfect for closing the distance or escaping danger.
- **Dynamic Water:** The ship elegantly bobs and reacts to the ocean waves, with visual meshes perfectly synced to the physics engine for a smooth, jitter-free experience!

### 2. Artillery Combat & Grapeshot System
- **Broadside Cannons:** Fire upon enemy vessels using the port, starboard, or front cannons (`Spacebar`).
- **Distance-based Auto Grapeshot:**
  - **Long Range (>15m):** Fires a standard destructive Round Shot to smash the enemy hull.
  - **Close Quarters (<=15m):** Automatically switches to **Grapeshot**. Fires a spread of pellets that deals intense AoE damage to the enemy crew while preserving the hull!
- **Critical Hits:** Cannonballs have a 20% chance to score a devastating critical hit, triggering massive explosions and dealing double damage.

### 3. Derelict Ship Capture & Fleet Formations
- **The "Ghost Ship" Mechanic:** If you successfully kill all the enemy soldiers on a ship without sinking it, the ship becomes **Derelict** (White flag).
- **Autonomous Capture AI:** Your soldiers will automatically spot nearby empty ships (within 12m) and jump onto them to capture!
- **Fleet Formation System:** Captured ships don't just follow blindly—they maintain a disciplined formation.
  - **`F` Key Toggle:** Switch between **Column (Line)** and **Wing (V-Shape)** formations in real-time.
- **Immediate Armament:** Captured ships are instantly fitted with 3 cannons (Front, Left, Right) to fight alongside you.
- **Grappling Hooks:** Visual ropes tether ships during boarding, ensuring they stay close for the action.
- **Ramming & Melee Boarding:** Ramming initiated combat where soldiers jump across. If a ship sinks, your boarders will dive into the sea and become **Survivors** for you to rescue!

### 4. VFX & Immersive Combat Feedback ✨
- **Soldier Feedback:**
  - **Hit Flashes & Particles:** Enemies and allies flash on impact with unique particle bursts.
  - **Knockback:** Tactical physical feedback when taking damage.
  - **Slash Trail Effects:** Sword swings are visually represented with dynamic "twirl" arcs.
- **Heavy Weaponry Visuals:**
  - **Janggun-jeon (Great General's Arrow) 🪵:** A massive log-missile with visceral feedback. It features **nonlinear acceleration (Ease-In)**, flight wobble, muzzle smoke, and heavy camera shake on impact.
  - **Atmospheric Effects:** Cannon fire and explosions create randomized shockwaves and charcoal muzzle smoke.
  - **Explosive Wood Debris:** Ships shatter into structural planks and sawdust when hit.

### 5. Dynamic Environment & Performance
- **Cloud Shadows:** Real-time noise-based cloud shadows move across the ocean and ships using Decals.
- **Ocean Plane Mechanics:** A performance-optimized ocean mesh that dynamic follows the player, enabling beautiful shadows and submerged visibility.
- **Fog Optimization:** Adaptive fog depth scales with camera zoom, ensuring high performance even in complex naval battles.
- **AI & Crew:** Friendly and enemy soldiers use `NavigationAgent3D` for dynamic deck patrols and combat.
- **Meta-Progression:** Earn Gold from victories to upgrade Hull Armor, Cannon Damage, and Crew Training.

## Built With
- **Godot Engine 4.6** (GDScript)
- Custom 3D meshes and Particle Systems (`GPUParticles3D`)
- Advanced Audio System (`AudioManager` Singleton) for adaptive SFX.

## Controls
- **`A` / `D`**: Steer Rudder Left/Right
- **`Q` / `E`**: Adjust Sail Angle (Catch the wind)
- **`W`**: Row (Speed Boost / Consumes Stamina)
- **`S`**: Stop Rowing
- **`Spacebar`**: Fire Cannons at the nearest enemy
- **`F`**: Toggle Fleet Formation (Column / Wing)
- **`Right Click` (Hold)**: Pan Camera
- **`Mouse Wheel`**: Zoom In/Out

## Play on Web (GitHub Pages)
If you are playing the web version, please ensure your browser supports **WebGL 2.0**.
- **Renderer:** Compatibility (OpenGL)
- **Controls:** Same as desktop.
- **Link:** `https://fruitshoo.github.io/battleship/` (Required Setup in GitHub Settings)

---
*Take the helm, captain! The sea awaits.*
