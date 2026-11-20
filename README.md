# 🩺 FPS Doctor

**Smart Collision & Performance Auditor for Roblox Studio.**

FPS Doctor is a lightweight, single-file open-source plugin that scans your Roblox game for hidden physics, collision, and shadow bottlenecks—then fixes them safely in one click.

---

## ✨ Features

* **Workspace & Selection Auditor:** Scan your entire `Workspace` or target a specific `Selection` to calculate an overall **Health Score** and break down performance issues.
* **Smart Decorative Detection:** Automatically identifies non-interactive decorative parts using customizable keywords (e.g., `leaf`, `grass`, `rock`, `foliage`, `prop`) and size thresholds.
* **One-Click Batch Fixes:**
  * Disables unnecessary `CanTouch` and `CanQuery` on decorative parts.
  * Optionally disables `CanCollide` on tiny decorative props.
  * Switches heavy decorative `MeshPart` and `UnionOperation` objects to `CollisionFidelity.Box`.
  * Strips `CastShadow` from small parts below a customizable stud threshold.
* **Visual Heatmap Visualizer:** Renders color-coded overlays (`Green` = Safe, `Yellow` = Moderate, `Red` = Heavy) on `MeshParts` and `Unions` based on collision load.
* **Standalone Shadow Optimizer:** Instantly disables `CastShadow` across all parts smaller than your set threshold.
* **Heaviest Objects Inspector:** Lists the top 100 highest-scoring parts—click any item in the list to select it directly in Studio.

---

## 🛡️ Built-In Safety Guarantees

FPS Doctor is designed to optimize your map without breaking gameplay mechanics:

1. **Full Undo Support (`Ctrl + Z`):** Every batch fix and shadow optimization is wrapped in `ChangeHistoryService`, allowing you to revert all changes in a single step.
2. **Interactive Object Protection:** Parts are **never** treated as decorative if they are unanchored, inside a `Tool` / `Accessory` / `Humanoid` character, inside a `Model` containing a `Script`, or attached to `Seats`, `SpawnLocations`, `ClickDetectors`, `ProximityPrompts`, `TouchTransmitters`, or `DragDetectors`.
3. **Trigger Zone Preservation:** Invisible, non-colliding parts (`Transparency >= 1` and `CanCollide == false`) are automatically skipped so custom hitboxes and zone triggers stay intact.
4. **Manual Ignore System:** To protect any specific object or folder from being touched by FPS Doctor, either:
   * Add the CollectionService tag **`FPSDoctor_Ignore`**, or
   * Set the boolean attribute **`FPSDoctorIgnore = true`** on the instance (or any of its ancestors).

---

## 🚀 Installation

### Method 1: Save as Local Plugin (Recommended)
1. Download `FPSDoctor.lua` from this repository.
2. Open **Roblox Studio**, insert a `Script` into `ServerStorage`, and paste the code inside.
3. Right-click the `Script` in the Explorer and select **Save as Local Plugin...**
4. Name it **`FPS Doctor`** and click Save.

### Method 2: Plugins Folder
1. Open Roblox Studio and go to **Plugins** -> **Plugins Folder**.
2. Drop `FPSDoctor.lua` directly into that folder.

---

## ⚙️ Configuration (Optional)

At the top of `FPSDoctor.lua`, you can customize the `CONFIG` table:
* `LOGO_IMAGE` & `TOOLBAR_ICON`: Paste your uploaded Roblox Decal/Image asset ID (e.g., `"rbxassetid://1234567890"`). Leave blank `""` to use the built-in procedural UI logo.
* `MAX_ROWS`: Maximum number of flagged objects displayed in the inspector list (default: `100`).
* `MAX_HEAT_ADORNMENTS`: Maximum `BoxHandleAdornment` overlays rendered at once in Heatmap mode to keep Studio smooth (default: `3000`).

---

## 🤝 Contributing

Contributions, bug reports, and feature requests are welcome! Feel free to open an **Issue** or submit a **Pull Request**.

## 📄 License

This project is open-source and available under the [MIT License](LICENSE).
