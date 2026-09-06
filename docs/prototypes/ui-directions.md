# UI directions — interactive, disposable preview

**Question:** Which information hierarchy makes the next useful action clear while preserving the meadow's atmosphere?

Run `just poc-ui`, then open <http://localhost:8765/src/ui/prototype/?variant=A>. You can also open `src/ui/prototype/index.html` directly. No install/build or external services. The preview uses the game's actual sprites, font and Mocha palette. Raylib has no existing web route, so the three layouts live in a standalone preview beside the native UI sources and are never included in the game executable.

Use the bottom arrows or keyboard left/right to switch. `?variant=A`, `B`, or `C` is shareable and survives reload. The shared mock economy survives switching, but reload/Reset starts over. No save files, local storage, Steam calls or production mutations. The debug controls advance time and fill storage so you can inspect blocked states immediately.

| Variant | Idea | Tradeoff |
| --- | --- | --- |
| A — Meadow first (selected) | Slim honey strip, a pinned goal, full Upgrade Tree and Royal Shop destinations | Preserves the full progression structure while leaving the meadow open. |
| B — Field journal | Gentle chapters and a daily intention organize progression around the meadow | Stronger guidance and personality, but less meadow space; compact screens scroll. Chapters are illustrative suggestions, not implemented quests. |
| C — Research workbench | Linear upgrade paths beside an always-visible effect inspector and meadow reference | Clearest comparison/planning view; better as an optional research screen than the default meadow HUD. |

Try: fill storage → inspect Tailwind → follow its Storage blocker → buy Storage → welcome a worker → choose Iris → pin Fertile Soil → switch variants. Purchases, capacity recovery, goals and flower previews really respond. Economy values are deliberately simplified stubs, not a proposal to rebalance the game.

## Short desktop playtest

Headless Chrome, 1280×800 and 800×600: all three layouts passed storage blocker/recovery, upgrade purchase, worker purchase, flower preview, goal pinning, time advance, and state retention across switching. No browser exceptions or horizontal overflow at 800×600. Screenshots show each layout and its compact form. Native controller navigation and browser-to-Raylib parity are not established.

The exercise suggests taking **A's compact economy and pinned goal**, **B's friendly progression wording**, and **C's inspector hierarchy**. Keep the journal/workbench as optional destinations so the default view remains a meadow. The purchasing flow should always explain a storage blocker before estimating a wait.

## Further game improvements worth testing

1. **Production diagnosis:** a small optional breakdown of pollen supply, flight time and storage overflow. Test whether a player can choose a useful upgrade without trial and error. Derive these from measured simulation counters; avoid guessed recommendations.
2. **A remembered next goal:** pin one upgrade, show its cost/capacity blocker, and notify once when ready. Measure whether this reduces repeatedly opening the tree. Avoid constant pulsing.
3. **A flower collection page:** compare growth, pollen and lifetime with the flower's actual growth strip. Combine it with Discoveries rather than creating another competing HUD button.
4. **Short seasonal meadow requests:** optional layout challenges with cosmetic rewards, using the garden planner experiment. No daily streak pressure or forced reset.
5. **Performance diagnostics:** profile rendering at several meadow sizes and inspect long frame percentiles during autosave. The existing simulation benchmark cannot establish GPU/Deck performance.

These are follow-ups, not implemented production features. Choose a direction before rewriting it in native UI; do not merge the HTML prototype into the production interface.

## Selected direction: preserve the tree and Royal Shop

The user chose A’s meadow-first layout but rejected replacing progression with three paths. A now contains all 28 tree nodes (root plus 27 upgrades), their real prerequisites and per-run caps, branch navigation, zoom/Fit, selection inspector and goal pinning. The separate Royal Shop includes all seven existing perks, current-run Prestige gating, and a demo Ascend that keeps Royal purchases while resetting run upgrades. Node metadata is a snapshot of `src/upgrade_tree.zig`; effects and economy remain UI stubs. B/C remain historical alternatives.

The honey pane was also rejected for covering the meadow. A now uses a thin resource strip; hover/focus exposes secondary details and selecting it opens Storage. The native HUD change is in PR #85.

Revised Chrome playtest: verified 28 tree nodes, Aura’s actual level prerequisites, Storage purchase, goal pinning, all seven shop buttons gated by Prestige, Royal purchase and retention across demo Ascend, Escape back to the meadow, and 800×600 layouts. Use **Late run** to inspect the unlocked Royal Shop without progressing a real save.
