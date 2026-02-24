# Battleship 🏴‍☠️

A dynamic 3D naval combat and boarding action game built with **Godot Engine 4**. Navigate the high seas, manage your crew, engage in strategic ship-to-ship combat, and capture enemy vessels!

## 🌊 Core Gameplay Mechanics

### 1. Realistic Ship Navigation & Physics
- **Wind & Sail Physics:** Utilize the wind direction to your advantage. Adjust the sail angle (`Q` / `E`) to catch the wind and maximize thrust.
- **Rudder Control:** Steer the ship (`A` / `D`) realistically based on the rudder angle and current speed.
- **Rowing System:** Press `W` to row, providing a temporary speed boost at the cost of stamina. Perfect for closing the distance or escaping danger.
- **Dynamic Water:** The ship elegantly bobs and reacts to the ocean waves, with visual meshes perfectly synced to the physics engine for a smooth, jitter-free experience!

### 2. Artillery Combat & Grapeshot System
- **Broadside Cannons:** Fire upon enemy vessels using the port, starboard, or front cannons (`Spacebar`).
- **Distance-based Auto Grapeshot 🍇:**
  - **Long Range (>15m):** Fires a standard destructive Round Shot to smash the enemy hull.
  - **Close Quarters (<=15m):** Automatically switches to **Grapeshot**. Fires a spread of pellets that deals intense AoE damage to the enemy crew while preserving the hull!
- **Critical Hits:** Cannonballs have a 20% chance to score a devastating critical hit, triggering massive explosions and dealing double damage.

### 3. Derelict Ship Capture & Boarding ⚔️
- **The "Ghost Ship" Mechanic:** If you successfully kill all the enemy soldiers on a ship without sinking it (highly effective with Grapeshot), the ship loses control and becomes completely **Derelict**.
- **Reward System (Looting):** Ram your ship into a Derelict vessel to effortlessly capture it!
  - Instantly heals all your existing crew members to 100%.
  - Rescues a prisoner who joins your crew (up to the maximum ship capacity).
- **Ramming & Melee Boarding:** If the enemy crew is still alive, ramming them will initiate brutal melee combat. Your soldiers will automatically cross over and fight. The surviving crew takes over the ship.

### 4. Dynamic AI & Crew Management
- **Soldiers & NavMesh:** Friendly and enemy soldiers use `NavigationAgent3D` to dynamically patrol the decks, seek out enemies, and engage in sword fights or musket fire.
- **Ship Regeneration:** Your ship slowly repairs its hull over time passively.
- **Gold & Upgrades:** Destroying enemy ships grants Gold based on their size, which can be spent on meta-progression upgrades like Hull Armor, Cannon Damage, and Crew Training.

## ⚙️ Built With
- **Godot Engine 4.6** (GDScript)
- Custom 3D meshes and Particle Systems (`GPUParticles3D`)
- Advanced Audio System (`AudioManager` Singleton) for adaptive SFX.

## 🛠️ Controls
- **`A` / `D`**: Steer Rudder Left/Right
- **`Q` / `E`**: Adjust Sail Angle (Catch the wind)
- **`W`**: Row (Speed Boost / Consumes Stamina)
- **`S`**: Stop Rowing
- **`Spacebar`**: Fire Cannons at the nearest enemy
- **`Right Click` (Hold)**: Pan Camera
- **`Mouse Wheel`**: Zoom In/Out

---
*Take the helm, captain! The sea awaits.* ⚓
