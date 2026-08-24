const rl = @import("raylib");
const std = @import("std");
const World = @import("../world.zig").World;
const utils = @import("../../utils.zig");
const theme = @import("../../theme.zig");
const clock = @import("../../clock.zig");
const ui_scale = @import("../../ui_scale.zig");

const FlowerRenderData = struct {
    entity: u32,
    gridX: f32,
    gridY: f32,
    sortKey: f32,
    isRotten: bool,
    isSuper: bool,
};

// Grayscale post-tint for rotten flowers (lazily compiled; GLSL 330 on
// desktop which is what raylib targets on macOS/Linux/Windows here).
var grayShader: ?rl.Shader = null;
const GRAY_FS: [:0]const u8 =
    \\#version 330
    \\in vec2 fragTexCoord;
    \\in vec4 fragColor;
    \\out vec4 finalColor;
    \\uniform sampler2D texture0;
    \\uniform vec4 colDiffuse;
    \\void main() {
    \\    vec4 t = texture(texture0, fragTexCoord);
    \\    float g = dot(t.rgb, vec3(0.299, 0.587, 0.114));
    \\    finalColor = vec4(vec3(g), t.a) * colDiffuse * fragColor;
    \\}
;

fn grayscaleShader() ?rl.Shader {
    if (grayShader == null) grayShader = rl.loadShaderFromMemory(null, GRAY_FS) catch null;
    return grayShader;
}

pub fn deinit() void {
    if (grayShader) |sh| rl.unloadShader(sh);
    grayShader = null;
    if (shadowDiscTex) |tex| rl.unloadTexture(tex);
    shadowDiscTex = null;
    if (glowDiscTex) |tex| rl.unloadTexture(tex);
    glowDiscTex = null;
}

fn compareFlowers(context: void, a: FlowerRenderData, b: FlowerRenderData) bool {
    _ = context;
    return a.sortKey < b.sortKey;
}

// Upper bound on bees drawn per frame (after frustum culling). Batched
// quad rendering keeps 32k sprites cheap; past this the extra bees overlap
// existing ones anyway.
const MAX_BEES: usize = 32768;
const BeeRenderData = struct {
    x: f32,
    y: f32,
    scale: f32,
    carryingPollen: bool,
    color: rl.Color,
};
var beeRenderList: [MAX_BEES]BeeRenderData = undefined;
var beeRenderCount: usize = 0;

var cachedScreenWidth: f32 = 0;
var cachedScreenHeight: f32 = 0;
const FRUSTUM_MARGIN: f32 = 50.0;

// Beehive cache — the beehive never moves within a run. Invalidated on
// prestige/expand via resetCaches().
const BeehiveCache = struct {
    entity: u32,
    gridX: f32,
    gridY: f32,
    texture: rl.Texture,
    width: f32,
    height: f32,
    scale: f32,
};
var cachedBeehive: ?BeehiveCache = null;

// Shared bee texture — one per session.
var cachedBeeTexture: ?rl.Texture = null;

// Soft-disc textures for ground shadows and pollen glows (lazily created).
// Shadows/glows used to be immediate-mode triangle fans (DrawEllipse is 108
// vertices) interleaved with sprite quads, which forced a texture/mode switch
// per bee and fragmented the render batch into thousands of draw calls. As
// textured quads drawn in same-texture passes, the whole swarm batches.
const DISC_SIZE: i32 = 64;
const SHADOW_DENSITY: f32 = 0.55; // solid core, soft rim
const GLOW_DENSITY: f32 = 0.0; // linear falloff from centre, like DrawCircleGradient
var shadowDiscTex: ?rl.Texture = null;
var glowDiscTex: ?rl.Texture = null;

fn discTexture(slot: *?rl.Texture, density: f32) ?rl.Texture {
    if (slot.* == null) {
        // White with alpha falloff: tinting picks the colour, alpha stays linear.
        const img = rl.genImageGradientRadial(DISC_SIZE, DISC_SIZE, density, rl.Color.init(255, 255, 255, 255), rl.Color.init(255, 255, 255, 0));
        defer rl.unloadImage(img);
        const tex = rl.loadTextureFromImage(img) catch return null;
        rl.setTextureFilter(tex, .bilinear);
        slot.* = tex;
    }
    return slot.*;
}

pub fn resetCaches() void {
    cachedBeehive = null;
    cachedBeeTexture = null;
    beeRenderCount = 0;
}

pub fn draw(world: *World, gridOffset: rl.Vector2, gridScale: f32, worldTint: rl.Color, auraLevel: u16, auraReach: f32) !void {
    cachedScreenWidth = ui_scale.width();
    cachedScreenHeight = ui_scale.height();

    const time = @as(f32, @floatCast(clock.time()));

    if (cachedBeehive == null) {
        var beehiveIter = world.entityToBeehive.keyIterator();
        if (beehiveIter.next()) |entity| {
            if (world.getGridPosition(entity.*)) |gridPos| {
                if (world.getSprite(entity.*)) |sprite| {
                    cachedBeehive = .{
                        .entity = entity.*,
                        .gridX = gridPos.x,
                        .gridY = gridPos.y,
                        .texture = sprite.texture,
                        .width = sprite.width,
                        .height = sprite.height,
                        .scale = sprite.scale,
                    };
                }
            }
        }
    }

    if (cachedBeehive) |bh| {
        // Lab: Aura — expanding rings on the ground so the buff is visible.
        if (auraLevel > 0) drawAuraPulse(bh.gridX, bh.gridY, gridOffset, gridScale, auraLevel, auraReach, time);
        // Soft ground shadow + a gentle "breathing" pulse so the hive feels alive.
        drawGroundShadow(bh.gridX, bh.gridY, gridOffset, gridScale, 0.6, 0.28);
        const pulse = bh.scale * (1.0 + 0.03 * @sin(time * 1.4));
        drawBeehiveAtGridPosition(bh.texture, bh.gridX, bh.gridY, bh.width, bh.height, pulse, gridOffset, gridScale, worldTint);
    }

    var flowerList: [512]FlowerRenderData = undefined;
    var flowerCount: usize = 0;

    var flowerIter = world.iterateFlowers();
    while (flowerIter.next()) |entity| {
        if (world.getGridPosition(entity)) |gridPos| {
            if (world.getLifespan(entity)) |lifespan| {
                if (lifespan.isDead()) continue;
            }
            // A SUPER flower anchors at the block's top-left cell but is drawn
            // at the 2x2 block's centre, sorted with the block's front edge.
            var isSuper = false;
            var isRotten = false;
            if (world.getFlowerGrowth(entity)) |growth| {
                isSuper = growth.isSuper;
                isRotten = growth.isRotten;
            }
            const superOffset: f32 = if (isSuper) 0.5 else 0.0;
            if (flowerCount < flowerList.len) {
                flowerList[flowerCount] = .{
                    .entity = entity,
                    .gridX = gridPos.x + superOffset,
                    .gridY = gridPos.y + superOffset,
                    .sortKey = gridPos.x + gridPos.y + superOffset * 2,
                    .isRotten = isRotten,
                    .isSuper = isSuper,
                };
                flowerCount += 1;
            }
        }
    }

    std.mem.sort(FlowerRenderData, flowerList[0..flowerCount], {}, compareFlowers);

    // Cell under the mouse, for the rotten-flower hover hint.
    const mouseIso = utils.xyToIso(rl.getMousePosition().x, rl.getMousePosition().y, 32, 32, gridOffset.x, gridOffset.y, gridScale);
    const hoverX: f32 = @floor(mouseIso.x);
    const hoverY: f32 = @floor(mouseIso.y);

    // Ground shadows first as one same-texture pass (scaled with how grown the
    // flower is, and with the whole block for SUPER flowers). Keeping them out
    // of the sprite loop avoids a texture switch per flower.
    for (flowerList[0..flowerCount]) |flowerData| {
        if (world.getFlowerGrowth(flowerData.entity)) |growth| {
            const growthFrac = growth.state / 4.0;
            const shadowMul: f32 = if (flowerData.isSuper) 2.0 else 1.0;
            drawGroundShadow(flowerData.gridX, flowerData.gridY, gridOffset, gridScale, (0.34 + 0.14 * growthFrac) * shadowMul, 0.22);
        }
    }

    for (flowerList[0..flowerCount]) |flowerData| {
        if (world.getFlowerGrowth(flowerData.entity)) |growth| {
            if (world.getSprite(flowerData.entity)) |sprite| {
                const source = rl.Rectangle.init(growth.state * sprite.width, 0, sprite.width, sprite.height);

                // Grown flowers are taller → they sway more. Per-flower phase from
                // grid position keeps the meadow from swaying in lockstep.
                const growthFrac = growth.state / 4.0;
                const phase = flowerData.gridX * 1.7 + flowerData.gridY * 0.9;
                const sway = @sin(time * 0.9 + phase) * 2.6 * growthFrac;

                if (flowerData.isRotten) {
                    // Withered: grayscale, a touch darker and slumped, no sway.
                    // Hovering brightens it and shows a clear-me ring so the
                    // player learns it's clickable.
                    const anchorX = flowerData.gridX - (if (flowerData.isSuper) @as(f32, 0.5) else 0.0);
                    const anchorY = flowerData.gridY - (if (flowerData.isSuper) @as(f32, 0.5) else 0.0);
                    const span: f32 = if (flowerData.isSuper) 2 else 1;
                    const hovered = hoverX >= anchorX and hoverX < anchorX + span and hoverY >= anchorY and hoverY < anchorY + span;
                    const dim: f32 = if (hovered) 1.0 else 0.7;
                    const tint = rl.Color.init(
                        @intFromFloat(@as(f32, @floatFromInt(worldTint.r)) * dim),
                        @intFromFloat(@as(f32, @floatFromInt(worldTint.g)) * dim),
                        @intFromFloat(@as(f32, @floatFromInt(worldTint.b)) * dim),
                        worldTint.a,
                    );
                    if (hovered) drawClearHint(flowerData.gridX, flowerData.gridY, gridOffset, gridScale, time);
                    const sh = grayscaleShader();
                    if (sh) |shader| rl.beginShaderMode(shader);
                    drawSpriteAtGridPosition(sprite.texture, flowerData.gridX, flowerData.gridY, source, sprite.scale * 0.92, tint, gridOffset, gridScale, 0);
                    if (sh != null) rl.endShaderMode();
                    continue;
                }

                if (growth.state == 4 and growth.hasPollen) {
                    // Pollen glow breathes and stays bright (untinted) so ready
                    // flowers pop, even at night.
                    const glowPulse = 0.1 + 0.05 * @sin(time * 3.0 + phase);
                    drawSpriteAtGridPosition(sprite.texture, flowerData.gridX, flowerData.gridY, source, sprite.scale + glowPulse, theme.CatppuccinMocha.Color.pollenGlow, gridOffset, gridScale, sway);
                }

                drawSpriteAtGridPosition(sprite.texture, flowerData.gridX, flowerData.gridY, source, sprite.scale, worldTint, gridOffset, gridScale, sway);
            }
        }
    }

    buildBeeRenderList(world);

    if (cachedBeeTexture == null) {
        var beeIter = world.iterateBees();
        if (beeIter.next()) |firstBee| {
            if (world.getSprite(firstBee)) |sprite| {
                cachedBeeTexture = sprite.texture;
            }
        }
    }

    if (cachedBeeTexture) |texture| {
        const pollenColor = theme.CatppuccinMocha.Color.yellow;

        // Bees draw in three same-texture passes (shadows, glows, sprites) so
        // the whole swarm stays in a few render batches. Interleaving them
        // per-bee forces a texture switch per draw and, past a few thousand
        // bees, thousands of full batch flushes per frame.

        // Pass 1 — ground shadows. They stay near the resting baseline and
        // shrink/fade as the bee floats higher, selling the vertical motion.
        if (discTexture(&shadowDiscTex, SHADOW_DENSITY)) |disc| {
            for (0..beeRenderCount) |i| {
                const bee = beeRenderList[i];
                const phase = @as(f32, @floatFromInt(i)) * 0.7;
                const bob = @sin(time * 2.0 + phase) * 2.2 * bee.scale;
                const cx = bee.x + 16 * bee.scale;
                const lift = std.math.clamp(-bob / (3.0 * bee.scale), -1.0, 1.0);
                const shadowScale = 1.0 - 0.25 * lift;
                const alpha: u8 = @intFromFloat(60 * (1.0 - 0.35 * lift));
                drawDisc(disc, cx, bee.y + 26 * bee.scale, 8.5 * bee.scale * shadowScale, 3.2 * bee.scale * shadowScale, rl.Color.init(0, 0, 0, alpha));
            }
        }

        // Pass 2 — warm glow on pollen-carriers so laden bees are easy to track.
        if (discTexture(&glowDiscTex, GLOW_DENSITY)) |disc| {
            for (0..beeRenderCount) |i| {
                const bee = beeRenderList[i];
                if (!bee.carryingPollen) continue;
                const phase = @as(f32, @floatFromInt(i)) * 0.7;
                const bob = @sin(time * 2.0 + phase) * 2.2 * bee.scale;
                const cx = bee.x + 16 * bee.scale;
                const r = 16 * bee.scale;
                drawDisc(disc, cx, bee.y + bob + 14 * bee.scale, r, r, rl.Color.init(255, 226, 120, 90));
            }
        }

        // Pass 3 — the bees themselves. Slow float bob + fast wing "buzz"
        // scale flutter = alive, cozy bees.
        for (0..beeRenderCount) |i| {
            const bee = beeRenderList[i];
            const phase = @as(f32, @floatFromInt(i)) * 0.7;
            const bob = @sin(time * 2.0 + phase) * 2.2 * bee.scale;
            const buzz = 1.0 + 0.06 * @sin(time * 26.0 + phase);
            const drawScale = bee.scale * buzz;

            const base = if (bee.carryingPollen) pollenColor else bee.color;
            const color = rl.colorTint(base, worldTint);
            rl.drawTextureEx(texture, rl.Vector2.init(bee.x, bee.y + bob), 0, drawScale, color);
        }
    }
}

/// Soft translucent ground shadow at an isometric grid cell's surface centre.
fn drawGroundShadow(gridX: f32, gridY: f32, gridOffset: rl.Vector2, gridScale: f32, radiusScale: f32, alphaScale: f32) void {
    const tilePos = utils.isoToXY(gridX, gridY, 32, 32, gridOffset.x, gridOffset.y, gridScale);
    const cx = tilePos.x + 16 * gridScale;
    const cy = tilePos.y + 8 * gridScale;
    const rx = 26 * radiusScale * (gridScale / 3.0);
    const ry = rx * 0.5;
    drawEllipseSoft(cx, cy, rx, ry, @intFromFloat(alphaScale * 255));
}

/// Isometric rings that expand from the hive and fade out, repeating forever
/// (think "elixir collector" aura). Higher levels reach further and run more
/// staggered rings, so leveling Aura reads on the meadow at a glance.
fn drawAuraPulse(gridX: f32, gridY: f32, gridOffset: rl.Vector2, gridScale: f32, level: u16, reachTiles: f32, time: f32) void {
    const tilePos = utils.isoToXY(gridX, gridY, 32, 32, gridOffset.x, gridOffset.y, gridScale);
    const cx = tilePos.x + 16 * gridScale;
    const cy = tilePos.y + 8 * gridScale;

    const period: f32 = 2.6;
    // A circle of radius r (tiles) in grid space projects to an ellipse whose
    // horizontal semi-axis is r*sqrt(2)*halfTileWidth — matches labs.isInAura.
    const maxRx = reachTiles * std.math.sqrt2 * 16 * gridScale;
    const rings: u32 = @min(@as(u32, level), 3);
    // Lavender reads far better than mauve against the green meadow.
    const base = theme.CatppuccinMocha.Color.lavender;

    var i: u32 = 0;
    while (i < rings) : (i += 1) {
        const phase = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(rings));
        const t = @mod(time / period + phase, 1.0);
        const eased = @sqrt(t); // fast start, slows as it fades
        const rx = maxRx * eased;
        const ry = rx * 0.5;
        const alpha: f32 = (1.0 - t) * 255.0;
        if (alpha < 6 or rx < 2) continue;
        const a: u8 = @intFromFloat(alpha);
        // Faint fill + a thick ring (segmented so thickness scales with zoom).
        rl.drawEllipse(@intFromFloat(cx), @intFromFloat(cy), rx, ry, rl.Color.init(base.r, base.g, base.b, a / 6));
        drawEllipseRing(cx, cy, rx, ry, @max(2.0, 2.0 * gridScale), rl.Color.init(base.r, base.g, base.b, a));
    }
}

fn drawEllipseRing(cx: f32, cy: f32, rx: f32, ry: f32, thick: f32, color: rl.Color) void {
    const segments: u32 = 48;
    var prev = rl.Vector2.init(cx + rx, cy);
    var k: u32 = 1;
    while (k <= segments) : (k += 1) {
        const ang = @as(f32, @floatFromInt(k)) / @as(f32, @floatFromInt(segments)) * std.math.tau;
        const p = rl.Vector2.init(cx + rx * @cos(ang), cy + ry * @sin(ang));
        rl.drawLineEx(prev, p, thick, color);
        prev = p;
    }
}

fn drawEllipseSoft(cx: f32, cy: f32, rx: f32, ry: f32, alpha: u8) void {
    if (discTexture(&shadowDiscTex, SHADOW_DENSITY)) |disc| {
        drawDisc(disc, cx, cy, rx, ry, rl.Color.init(0, 0, 0, alpha));
    } else {
        rl.drawEllipse(@intFromFloat(cx), @intFromFloat(cy), rx, ry, rl.Color.init(0, 0, 0, alpha));
    }
}

/// One textured quad: the soft disc stretched to an ellipse centred at (cx, cy).
fn drawDisc(disc: rl.Texture, cx: f32, cy: f32, rx: f32, ry: f32, tint: rl.Color) void {
    const source = rl.Rectangle.init(0, 0, @floatFromInt(disc.width), @floatFromInt(disc.height));
    const destination = rl.Rectangle.init(cx - rx, cy - ry, rx * 2, ry * 2);
    rl.drawTexturePro(disc, source, destination, rl.Vector2.init(0, 0), 0, tint);
}

fn buildBeeRenderList(world: *World) void {
    beeRenderCount = 0;

    var beeIter = world.iterateBees();
    while (beeIter.next()) |entity| {
        if (beeRenderCount >= MAX_BEES) break;

        if (world.getPosition(entity)) |position| {
            if (position.x < -FRUSTUM_MARGIN or position.x > cachedScreenWidth + FRUSTUM_MARGIN or
                position.y < -FRUSTUM_MARGIN or position.y > cachedScreenHeight + FRUSTUM_MARGIN)
            {
                continue;
            }

            if (world.getScaleSync(entity)) |scaleSync| {
                if (world.getBeeAI(entity)) |beeAI| {
                    if (world.getLifespan(entity)) |lifespan| {
                        if (lifespan.isDead()) continue;
                    }

                    beeRenderList[beeRenderCount] = .{
                        .x = position.x,
                        .y = position.y,
                        .scale = scaleSync.effectiveScale,
                        .carryingPollen = beeAI.carryingPollen,
                        .color = beeAI.beeType.getColor(),
                    };
                    beeRenderCount += 1;
                }
            }
        }
    }
}

fn drawSpriteAtGridPosition(texture: rl.Texture, i: f32, j: f32, sourceRect: rl.Rectangle, scale: f32, color: rl.Color, gridOffset: rl.Vector2, gridScale: f32, swayDeg: f32) void {
    const tilePosition = utils.isoToXY(i, j, 32, 32, gridOffset.x, gridOffset.y, gridScale);
    const effectiveScale = scale * (gridScale / 3.0);
    const tileWidth = 32 * gridScale;
    const tileHeight = 32 * gridScale;

    const destW = sourceRect.width * effectiveScale;
    const destH = sourceRect.height * effectiveScale;
    const centeredX = tilePosition.x + (tileWidth - destW) / 2.0;
    const centeredY = tilePosition.y + (tileHeight * 0.25) - destH;

    // Pivot the sway around the flower's base (bottom-centre) so it bends like a
    // stem in the breeze rather than sliding.
    const destination = rl.Rectangle.init(centeredX + destW / 2.0, centeredY + destH, destW, destH);
    const origin = rl.Vector2.init(destW / 2.0, destH);
    rl.drawTexturePro(texture, sourceRect, destination, origin, swayDeg, color);
}

fn drawBeehiveAtGridPosition(texture: rl.Texture, i: f32, j: f32, width: f32, height: f32, scale: f32, gridOffset: rl.Vector2, gridScale: f32, tint: rl.Color) void {
    const tilePosition = utils.isoToXY(i, j, 32, 32, gridOffset.x, gridOffset.y, gridScale);
    const effectiveScale = scale * (gridScale / 3.0);
    const tileWidth = 32 * gridScale;
    const tileHeight = 32 * gridScale;

    const centeredX = tilePosition.x + (tileWidth - width * effectiveScale) / 2.0;
    const centeredY = tilePosition.y + (tileHeight * 0.5) - (height * effectiveScale);
    const source = rl.Rectangle.init(0, 0, width, height);
    const destination = rl.Rectangle.init(centeredX, centeredY, width * effectiveScale, height * effectiveScale);

    rl.drawTexturePro(texture, source, destination, rl.Vector2.init(0, 0), 0, tint);
}

/// Pulsing ring on the ground under a hovered rotten flower: "click to clear".
fn drawClearHint(gridX: f32, gridY: f32, gridOffset: rl.Vector2, gridScale: f32, time: f32) void {
    const tilePos = utils.isoToXY(gridX, gridY, 32, 32, gridOffset.x, gridOffset.y, gridScale);
    const cx = tilePos.x + 16 * gridScale;
    const cy = tilePos.y + 8 * gridScale;
    const pulse = 1.0 + 0.08 * @sin(time * 5.0);
    const rx = 15 * gridScale / 3.0 * 3.0 * pulse;
    drawEllipseRing(cx, cy, rx, rx * 0.5, @max(1.5, 1.2 * gridScale), rl.Color.init(243, 139, 168, 220));
}
