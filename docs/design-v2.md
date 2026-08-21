# Buzzness Tycoon — Design v2

Working design for turning the current toy loop into a real game. Decisions
already made:

- **No offline progress.** The game rewards presence (Rusty's Retirement
  model). The meadow must be worth leaving on screen.
- **Goals via Steam achievements** backed by an in-game discovery collection.
- **Identity:** an ambient garden you leave running, where *layout*
  (adjacency + breeding) and *build* (traits) are the decisions, exponential
  curves are the pacing, and discovery is the goal structure.

---

## 1. Economy (numbers must grow)

Move the honey economy to `f64` and add suffix formatting (K, M, B, T, …).
Show **honey/sec** in the HUD at all times — it is the number players watch.

### Repeatable generators

Bees stop being one-time unlocks. Each type is a generator bought repeatedly
with geometric cost:

```
cost(type, n) = base(type) × 1.15^n        // n = number already owned
```

| Bee       | Base cost | Relative output | Role                  |
|-----------|-----------|-----------------|-----------------------|
| Worker    | 15        | 1×              | starter               |
| Swift     | 150       | 7.5×            | tier 2                |
| Efficient | 1.5K      | 55×             | tier 3                |
| Gardener  | 15K       | 400×            | tier 4 + grows flowers|

Tier rule of thumb: each tier ≈ ×10 cost, ×7.5 output, so old tiers become
pocket change and the newest tier is always the exciting buy.

### Milestones

Owning N of a bee type multiplies that type's output:

```
10 owned → ×2      25 → ×2      50 → ×2      100 → ×2      every +100 → ×2
```

The player is always minutes away from *some* threshold. Milestone hits get
floating text + a chime (pitch rises with milestone size).

### The wall-and-breakthrough rhythm

Cost (geometric) always outruns income (roughly linear in purchases), so
progress stalls by design. Walls are broken by: prestige, new trait synergy,
better meadow layout, or a newly bred flower. Every other system exists to
smash walls.

### Prestige rework

Royal jelly keeps its ×(1 + 0.1·jelly) global multiplier, but each prestige
*count* also unlocks a mechanic, so run N+1 plays differently than run N:

| Prestige # | Unlock                                  |
|------------|-----------------------------------------|
| 1          | Queen's Court (trait slots 1–3)         |
| 2          | Breeding (hybrids can sprout)           |
| 3          | Trait slots 4–5 + shop reroll           |
| 4          | Night economy (moonbloom flowers)       |
| 5+         | Jelly-only shop (permanent meta-upgrades)|

---

## 2. Meadow layout: adjacency + breeding

Three base flowers are enough because bonuses come from **patterns, not
variety**. Adjacency = the 4 orthogonal isometric neighbors (revisit if
diagonals read better in play).

### Adjacency rules

- **Cluster** — 3+ same-type flowers connected: +50% pollen each.
- **Pairs** — each of the 3 base pairs has a personality:
  - rose⇄tulip: +25% pollen to both (cross-pollination)
  - tulip⇄dandelion: dandelion growth cooldown −20%
  - dandelion⇄rose: bees visiting either gain +1 carry capacity
- **Meadow tile** — a flower touching all 3 base types: ×2 pollen.
  (Deliberately competes with Cluster; layout is the puzzle.)
- **Hive gradient** — flowers near the hive are visited more often; far
  flowers yield +% per ring of distance. Risk/reward across the whole board.

### Breeding (unlocked at prestige 2)

Two adjacent mature flowers of different types have a small chance per bloom
cycle to sprout a hybrid on an adjacent empty tile. Watching it happen is the
point — it only occurs while the game runs (no-offline synergy).

| Flower                 | Parents            | Rarity    |
|------------------------|--------------------|-----------|
| Rose, Tulip, Dandelion | —                  | Common    |
| Rosetulip (peony?)     | rose + tulip       | Uncommon  |
| Tuliondel (poppy?)     | tulip + dandelion  | Uncommon  |
| Dandelrose (marigold?) | dandelion + rose   | Uncommon  |
| Trillium               | any two hybrids    | Rare      |
| Moonbloom              | Trillium at night, prestige 4+ | Legendary |

Hybrids have higher base pollen and their own adjacency quirks (e.g.
Moonbloom only produces at night, ×6).

---

## 3. Queen's Court (traits) + rarity

Balatro's core loop translated: a small pool of passive rule-modifiers,
**limited slots (max 5)**, bought from a **rotating shop**, so combinations
form builds.

- Shop refreshes every in-game dawn with 3 offers; one reroll per day
  (prestige 3+).
- Traits are permanent once slotted; replacing one destroys it (real choice).
- Trait costs scale with current honey/sec so the shop stays relevant.

### Rarity tiers

| Rarity    | Shop weight | Shape of effect                          | Color    |
|-----------|-------------|------------------------------------------|----------|
| Common    | 70%         | flat additive (+% pollen, −% cooldown)   | wood     |
| Uncommon  | 25%         | conditional (time of day, flower type, adjacency) | leaf |
| Rare      | 5%          | rule-changing (counts double, spreads, converts) | dusk |
| Legendary | never sold  | build-defining; earned by discovery deeds | honey/gold |

Legendaries drop from deeds, not the shop (Balatro soul-card energy): breed a
Trillium, hit 100 of one bee type, reach 1B honey/sec, etc.

### Draft trait list

Common: `+20% pollen` · `−15% grow cooldown` · `+500 storage per Cluster` ·
`bees fly 15% faster` · `+10% honey at delivery`

Uncommon: `night deliveries ×2` · `roses count double for Clusters` ·
`dandelions occasionally spread to adjacent empty tiles` · `first delivery
each dawn ×10` · `hive gradient far-bonus doubled` · `Gardeners also water:
adjacent flowers never wilt`

Rare: `every 10th delivery ×10` · `Meadow tiles chain: adjacent Meadow tiles
multiply` · `hybrids inherit both parents' pair bonuses` · `Burst lab
recharges from deliveries` · `clusters have no size cap, +10% per member`

Legendary: `Second Queen — duplicate the effect of the trait to this one's
left` (Balatro Blueprint) · `Moonlight Economy — night lasts twice as long,
everything at night ×3` · `Golden Comb — milestone multipliers become ×3`

### Multiplication juice

When bonuses stack on one delivery, show the math happening:
`12 × 4 × 2.5` ticking up with escalating pitch chimes (procedural audio
already supports this) and a small screen shake at ×100+.

---

## 4. Discovery collection → Steam achievements

One in-game "Discoveries" book indexes everything; Steam achievements map
onto it 1:1 so the scaffolding is shared:

- every flower bred (6+)
- every trait discovered (~25–30 at launch)
- bee milestones (25/100 of each type)
- honey/sec thresholds (1K, 1M, 1B, …)
- layout deeds (a 10-flower Cluster, 4 Meadow tiles at once)
- prestige counts (1, 3, 5)

Target 35–45 achievements at launch. Undiscovered entries show silhouettes.

---

## 5. UI direction: diegetic

Current UI reads as programmer-panels floating over a soft world. Move it
*into* the meadow:

- **Shop** → a market stall on a corner tile; clicking it opens the buy view.
- **Upgrade tree** → literally the tree; purchased nodes grow visible
  branches/blossoms on it.
- **Honey count** → the hive's visible fill level + small counter above it.
- **Trait slots** → banners/pennants hanging at the hive.
- **Popups** → wooden signposts; Discoveries is a book on a stump.

References: Rusty's Retirement, Forager. This is the largest
perceived-quality jump available and can land incrementally (start with shop
stall + hive counter).

---

## 6. Rough build order

1. `f64` economy, suffix formatting, honey/sec HUD, repeatable bee purchases
   with 1.15^n cost + milestones. *(Makes the numbers game exist.)*
2. Adjacency rules + layout feedback (highlight clusters/meadow tiles on
   hover). *(Makes the grid matter.)*
3. Prestige rework table + Queen's Court with ~15 traits, rotating shop,
   rarity weights. *(Makes runs differ.)*
4. Breeding + hybrid flowers. *(Makes discovery content.)*
5. Discoveries book + Steam achievements (needs Steamworks binding).
6. Diegetic UI passes, ongoing.

Each step is shippable on its own; 1–2 alone already changes the game from
toy to game.
