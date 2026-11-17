# Improvement Plan and Engineering Log

Last updated: 2026-11-16. The port has booted and been play-tested on a TrimUI Smart Pro with CrossMix OS. It remains experimental: memory stability during long sessions is not confirmed. The user-facing overview is in [README.md](README.md); setup details are in [overlay/docs/trimui.md](overlay/docs/trimui.md).

## Priorities

### P0: Validate memory stability on the device

- Investigate the 2026-11-16 SIGSEGV. It followed a successful save while Catacombs Level 2 was laying rooms again. The last telemetry was RSS 418 MB and `MemAvailable` 387 MB, so the log does not point to an out-of-memory kill. The captured backtrace contains libc addresses only; use the matching deployed build (`cc545ba1`, dirty) for symbolized diagnosis.
- Install the latest cross-compiled binary and start a fresh session.
- Repeat a route through town, the Blood Moor, Dark Wood, Underground Passage, and Tristram. Use a portal if the session remains stable.
- Review `d2d.log` and `launcher.log` for peak RSS and `memavail`, `memory low`, `art back`, slow frames, `MAIN STUCK`, and `Killed`.
- Success means no process kill, available memory recovering after art is released, and no black floor in the active level. Record route and session duration.

### P1: Isolate any remaining memory growth

- A previous device log showed RSS rising from 477 MB to 750 MB and `MemAvailable` falling from 355 MB to 73 MB after returning to the Blood Moor. This confirms memory pressure, not a single cause.
- If it recurs, sample around level construction, room activation, monster generation, and DT1 restoration. Record RSS, `MemAvailable`, and restored bytes without per-frame logging.
- Identify and reproduce the largest increase before changing memory ownership.

### P2: Verify the shared DT1 cache

- Compare cold and revisited outdoor areas on TrimUI with the same route; record RSS and `MemAvailable`.
- Native `test_dt1_cache` now covers case-insensitive shared paths, missing-path retry, separate decode/skip archives, shared ownership, and decoded-pixel release/restoration. Direct `manage_art` active/remote-level protection and concurrent level construction still need coverage.
- Check concurrent level construction for duplicate decode or unsafe MPQ reads.
- AbyssEngine has no reusable DT1/level cache; see the research note below.

### P3: Consider unloading complete levels only if needed

- Before freeing a `Level`, enumerate and clear all references in `World`, `Fight`, `Loot`, `Spawning`, portals, automap, and client state.
- Keep the active level, referenced town, other players' levels, and active portal destinations.
- Decide explicitly how reconstruction affects monsters, ground items, saves, and quest state. Test round trips and sanitizers natively first.
- Do not implement this if the DT1 cache stabilizes memory.

### P4: Controls and performance

- Re-test town equipment with A, interruption of the B skill while attacking with A, level transitions, and level edges under memory pressure.
- Keep performance work separate from stability work. Use the A/B protocol below for widescreen, panels, blits, and `-mcpu=cortex_a53`.
- Prioritize memory growth and freezes over further FPS optimization.

### P5: Optional Normal-campaign challenge prototype (implemented 2026-11-16)

- Esc > Options > Challenge Options exposes four independent, opt-in toggles. They do not change the save's official Normal/Nightmare/Hell difficulty, quest flags, unlocks, monster levels, experience, or Treasure Classes. `More Monsters` increases `MonDen` by 50% for rooms populated after enabling it.
- `Harder Monsters` scales monster maximum/current life by 50% and combat stats by 25%. It applies immediately to live and kept monsters and to new spawns; disabling it scales back to base stats and preserves the current life percentage.
- `Class-Usable Elite Loot` adds 50% relative weight to class-usable equipment bases in champion, unique, and superunique drop rolls only. It leaves normal-mode weights, NoDrop, item count, quality rolls, and all non-elite drops unchanged; it does not guarantee class items.
- `Hide Gold and Potions` hides only ground labels for gold, health potions, mana potions, and rejuvenation potions. It does not remove items or block pickup.
- Settings persist in `d2d.cfg`: `challenge_monsters`, `challenge_more_monsters`, `challenge_class_loot`, and `loot_filter`; all default off. These are local settings, not character-save fields.
- Focused rules tests pass for unchanged Normal drop distribution, increased class-usable elite weighting, reversible stat scaling, and protected loot-label categories. The smoke now checks persistence for all four challenge toggles, initializes the synthetic character's fixed-point life before combat, and uses the menu's actual Save-to-Exit navigation. It passes with `D2_MPQ_DIR` set to the game-data directory; without that environment variable, CTest skips it when MPQs are outside its default path.
- Next: install only after choosing to test on TrimUI and tune the multipliers by playing several classes. Do not enable by default until the balance is tested.

## Community ideas for a more personal, replayable game (2026-11-16)

This is a small scan of public Diablo II: Resurrected forum discussions, not a representative survey or consensus. D2R suggestions do not necessarily fit this 1.14d-based project. Reddit search pages were not readable through the available web fetcher, so the findings below are from Blizzard's public forums.

- **Preserve random loot.** Discussion of class-specific/personal loot is sharply divided: some players want more relevant drops, while others value off-class finds, trading, and the achievement of finding a rare item. Keep the existing loot system as the default. The P5 class-usable weighting should remain small, opt-in, limited to special monsters, and never guarantee a class item. [Forum search: class-specific loot](https://us.forums.blizzard.com/en/d2r/search?q=class%20specific%20loot%20drops%20Diablo%20II)
- **A loot filter is a low-risk freshness/QoL feature.** Repeated suggestions ask to hide low-value labels such as cracked gear or unwanted potion tiers, while retaining control over what remains visible. This changes presentation, not drop rolls, and suits TrimUI's small display. The current prototype is a single gold/potion-label toggle; presets and per-category options remain future extensions, with runes, gems, quest items, and useful bases protected. [Forum search: loot filters and item QoL](https://us.forums.blizzard.com/en/d2r/search?q=loot%20filter%20item%20quality%20of%20life)
- **Prefer skill diversity over a mandatory new item.** One recurring argument is that fixing an underused skill by adding a dominant runeword can make that item mandatory instead of creating more builds. If build balance is explored later, test small skill changes independently and preserve the original item randomness. [Forum search: runewords and build variety](https://us.forums.blizzard.com/en/d2r/search?q=runeswords%20build%20variety%20itemization)
- **Do not make challenge only a health/damage multiplier.** Some players warn that flat scaling can widen the gap between optimized and off-meta builds. For P5, test gradual stat scaling together with existing elite affixes or behaviors; compare survivability and time-to-kill across classes, not only one strong build. [Forum search: challenge scaling and players count](https://us.forums.blizzard.com/en/d2r/search?q=challenge%20difficulty%20players%20count%20solo)

### Suggested order for a personal-play prototype

1. Validate the implemented loot-label filter on TrimUI; expand to presets/category toggles only if the simple gold/potion filter is useful.
2. Tune the P5 challenge switches, with separate scaling and restrained special-monster class bias; validate the same settings on several classes.
3. One narrowly selected underused skill adjustment, only after a normal playthrough and combat logs identify a specific pain point.

Avoid global drop-rate boosts, guaranteed class drops, and new high-power runewords in the first iteration: they could erase the long-tail item hunt and make the new challenge self-defeating.

## Session notes

### 2026-11-14 to 2026-11-15: Port and device bring-up

- The TrimUI Smart Pro booted the port under CrossMix OS. Build and packaging produce an AArch64 Linux binary and a PortMaster-compatible package. This is device validation, not a stability or official-support claim.
- The project uses the `upstream/` D2Decomp submodule and the pinned `vendor/handkit/` checkout. SDL 3.4.20, Zig 0.14.1, OpenAL Soft 1.24.3, and zlib 1.3.2 have built successfully. Exact pins and checksums are in [VERSIONS.md](VERSIONS.md).
- The PortMaster ZIP was checked with CrossMix's bundled `harbourmaster`; install metadata is accepted. A manual install is also supported. Detailed SD-card conventions and non-interactive mtools commands are in [PORTMASTER-NOTES.md](PORTMASTER-NOTES.md).
- Implemented TrimUI-facing features include a save action with synchronous disk flush, `lang = ESP`, game-speed control, native SDL gamepad input, item and panel controls, and a reliable exit chord. The save label and some videos/key configuration screens still fall back to English.
- The launcher enables widescreen. The view adapts to the display aspect ratio: 16:9 uses the wider view, while a 4:3 display is effectively unchanged.
- The latest code also adds a short Corpse Explosion range highlight using the skill's calculated damage radius. It compiles for ARM; its appearance still needs device testing.

### Diagnostics

With `show_fps = 1`, the screen shows FPS and battery percentage when Linux exposes it through `/sys/class/power_supply`; otherwise it shows `--%`. The battery value is refreshed every 15 seconds. Render and present timings remain in `d2d.log`, which reports:

- `alive`: FPS, average render, and present times every five seconds.
- `phases`: clear, floor/shadow, walls/units, post-world, HUD, rain, labels, widescreen copy, and automap timing.
- `simulation`: every five seconds, average and maximum milliseconds per world turn for total simulation, level preparation, monster fight/AI, and room activation, plus the current monster and room counts. These timings exclude client rendering and presentation.
- `sys`: CPU frequency/governor, temperature, `memavail`, RSS, and load.
- `pad button` / `joystick button`: inputs received by the game.

The tested device held 2 GHz in the `performance` governor and ran at 57-67 C. Memory bandwidth is limited: a full 2 MB framebuffer pass costs about 3 ms.

### 2026-11-16: Memory work and follow-up

- A weak cache for decoded DT1 data shared by path reduced RSS by about 59 MB in a 60-second native macOS run around town and nearby areas (621 MB to 562 MB). This is not a TrimUI measurement; a long device run remains necessary.
- The current memory strategy releases pixel data for distant levels, calls `malloc_trim` on Linux/glibc, restores active-level art immediately, and restores nearby art gradually as memory allows. It does not unload the rest of already-built levels.
- Review of the SD logs found one launch spanning 07:15 to 19:59, but only 321 five-second `alive` samples (about 27 minutes of sampled runtime) with a 12-hour gap; the timestamps do not prove continuous play. The saved config used `linear`, `game_speed = 8`, and `show_fps = 1`.
- Those samples averaged 20.6 FPS and 42.7 ms render; `present` averaged about 6 ms. `walls+units` commonly took 15-18 ms, the floor 6-8 ms, and `wide-copy` about 2.7 ms. There was one 4.8-second stall in `wide-copy` and a 164 ms present stall. Three `MAIN STUCK` reports occurred: two during initial loading and one at the wide-copy stall.
- Memory telemetry in this log ranged from 363 to 439 MB RSS and 359 to 434 MB `MemAvailable`. Four `memory low` events released 112 MB of tile art in total, followed by one `art back`; no `Killed` event occurred. This is substantially better than the earlier 477-to-750 MB session, but the crash still needs investigation.
- The final save completed before signal 11. The last sample showed 418 MB RSS and about 388 MB available, so this crash is not explained by the memory figures in the log. The battery overlay change was made after this run and still needs a device check.
- AbyssEngine was reviewed as a reference. Its current tree focuses on intro scenes and menus, has no levels or DT1 support, decodes DC6 assets per instance, and marks patch/single-unit MPQ support as TODO. Its explicit resource ownership is a useful principle, but there is no level-loading or cache implementation to port.

## Experiments

For A/B comparisons, use the same place (town, stationary, no rain), `show_fps = 1`, and a two- to three-minute run. Average `fps`, `render avg`, `present avg`, and `phases` from `d2d.log`. Rain, open panels, and heat can otherwise confound results.

| Experiment | Result | Follow-up |
|---|---|---|
| SDL 3.2.10, 3.2.30, and 3.4.20 | Works with Handkit; CPU draw time was unchanged. Rain looked finer and smoother. | Continue device checks for SDL 3.4-specific behavior. |
| `linear` vs `nearest` scaling | `linear` looked better on device. | Compare SDL 3.4 `pixelart`; it has not been measured on TrimUI. |
| Strip debug symbols | Binary shrank from 316 MB to 11 MB; ZIP from 78 MB to 5 MB. No FPS change. | Complete. |
| 32-bit writes for lit floor pixels | Mac benchmark: 11.5 to 5.7 ms. Device render: 33-34 to 30-33 ms, about 5-10%. | Rendering is not limited to this calculation alone. |
| 32-bit frame clear and row-wise rain | Average render improved from 37.4 to 28 ms; town FPS from 22.7 to 27. | Keep under observation. |
| Rendering phase profile | Clear 3.3 ms; floor 8-11; walls/units 4-5; UI 3.5; widescreen copy 2.8; automap 1. With inventory/stash open, post-world rises to 12-24 ms. | Measure the roughly 10 ms before `render_ingame`. |
| Memory before shared DT1 cache | RSS 477 to 750 MB; `MemAvailable` 355 to 73 MB; process ended in `Killed`. | Repeat with current cache and longer session. |
| Shared DT1 cache | Native macOS RSS 621 to 562 MB over 60 seconds. | Measure on device. |
| LTO | Failed because Handkit's `ar` cannot archive the `libstorm.a` bitcode. | Discarded. |
| Menu button | The OS consumes Menu before SDL; launcher exit chord works, with Select + Start as an in-game fallback. | No SDL-side fix identified. |
| `-mcpu=cortex_a53` vs generic | Not isolated; earlier runs changed more than one variable. | Test with the A/B protocol; expected gain is 0-5%. |
| TrimUI session log, 2026-11-16 | 20.6 FPS and 42.7 ms average render in 321 sampled windows; memory stayed below 439 MB RSS. | Reproduce the wide-copy stall and SIGSEGV before tuning based on this run. |

Other observations: framebuffer clearing and memory writes are relatively expensive on this device. The device ran without visible thermal throttling in the observed sessions. Battery voltage/percentage logging has not been implemented.

## Open issues

- **Town equipment with A:** holding A equips correctly in a dungeon but can select the wrong action in town. Re-test with stash closed and away from NPCs; inspect the `to equip` / `to store` / `to take out` prompt. If needed, log `stash_open`, `store.npc`, held item, and selected `PadHoldKind`.
- **OpenAL shutdown:** normal exit can abort while destroying the audio context (`double free`); saving is unaffected. A possible `alcSuspendContext` fix has not been tested.
- **SIGSEGV after save:** the 2026-11-16 log ends with signal 11 after Catacombs Level 2 room updates. The captured stack has no d2d frame and memory was not near the earlier high-water mark. Reproduce with symbols from the matching revision before attributing a cause.
- **Localization:** the Spanish Save label falls back to `SAVE`; intro videos and key configuration remain English.
- **Scaling:** `pixelart` is available with SDL 3.4 but has not been compared against `linear` on TrimUI.
- **FPS:** walls/units are the largest regularly sampled render phase. Profile that path and reproduce the 4.8-second `wide-copy` stall before optimizing panel blits or changing dependencies. Keep SDL/Handkit and library pins fixed during each A/B test.
- **Level lifetime:** unloading distant complete levels is unsafe until every retained pointer and per-level state has been accounted for.
- **Battery:** Verify that the new `show_fps` percentage matches the TrimUI's system indicator and stays readable while playing. CrossMix has no known calibration tool for this port; voltage logging from `/sys/class/power_supply` may help characterize shutdown behavior.

## Recording future results

For every new device experiment, record the date, binary revision/configuration, TrimUI model and firmware, route, duration, observed FPS/render/present times, memory peaks, and what did or did not work. Read logs before sharing them; paths may contain personal information. Never attach game files, saves, keys, or unreviewed logs.
