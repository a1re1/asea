# ASEA • The Unwritten Sea

An original low-poly sailing overworld built with Godot 4.7 and Blender: nine large islands and 25 smaller discoveries across a 5 km sea. Sail between watchtowers, ruins, villages, islets and buoys while charting the water around you. This prototype covers sailing and exploration; walking, puzzles, dungeons and quests are future work.

## Run

```bash
bash tools/run.sh
```

Auto-detects Godot (`$GODOT`, then `Godot.app` under Downloads/Applications, then `godot` on PATH). Main scene: `scenes/main.tscn`. Save: `user://voyage.json`.

Alternatively, import `project.godot` in the Godot project manager and press **F5**. The checked-in GLBs run without Blender; use Blender to edit or regenerate the original models.

Captures (native renderer, isolated save, quit after ~60 frames):

```bash
bash tools/run.sh -- --capture=/tmp/asea-sailing.png
bash tools/run.sh -- --capture-map=/tmp/asea-chart.png
```

## Controls

- **W/S** target throttle (holds after release; boat glides)
- **A/D** steer · **Shift** faster · **Space** brake · **R** recover to harbor
- **M / Tab** chart · **Escape** close chart · **CHART** button
- **Right mouse drag** orbit camera · **Mouse wheel** zoom
- Click a discovered place on the chart or in its sidebar to set a waypoint.

Chart freezes the boat. HUD (cream/ink, 1440×900 stretch) shows region, charted count, compass/wind, knots, waypoint, discovery toast.

Fog clears only around sailed water. Discovery, revealed cells, boat position and the selected waypoint persist between sessions. **R** returns to the harbor while keeping exploration. The fixed east-wind indicator is cosmetic; sailing uses arcade throttle and steering.

Godot stores the voyage in its project user-data folder (on macOS, normally `~/Library/Application Support/Godot/app_userdata/ASEA • The Unwritten Sea/`). To start fresh, close the game and rename `voyage.json` to a backup name before launching again. Verification preserves the normal save; native capture flags use a separate capture voyage.

## Tests

```bash
bash tools/verify.sh
```

Logic suite (`tests/*_test.gd`) plus main-scene smoke. `tests/runtime_smoke.gd` is a separate stage (not in the logic runner).

The command fails on test failures, missing assertion records or engine errors. It exercises sailing, shoreline collision, discovery, physical map input, pause/resume, recovery and persistence. Native rendering has been checked with Godot 4.7.2 Compatibility on macOS; web exports and other platforms have not been verified.

Blender sources: see [ASSETS.md](ASSETS.md).
