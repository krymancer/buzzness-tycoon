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
    isDying: bool,
    isSuper: bool,
};

fn compareFlowers(context: void, a: FlowerRenderData, b: FlowerRenderData) bool {
    _ = context;
    return a.sortKey < b.sortKey;
}

const MAX_BEES: usize = 16384;
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
            var isDying = false;
            if (world.getLifespan(entity)) |lifespan| {
                if (lifespan.isDead()) continue;
                const timeRemaining = lifespan.timeSpan - lifespan.totalTimeAlive;
                isDying = timeRemaining <= 5.0 and timeRemaining > 0;
            }
            // A SUPER flower anchors at the block's top-left cell but is drawn
            // at the 2x2 block's centre, sorted with the block's front edge.
            var isSuper = false;
            if (world.getFlowerGrowth(entity)) |growth| isSuper = growth.isSuper;
            const superOffset: f32 = if (isSuper) 0.5 else 0.0;
            if (flowerCount < flowerList.len) {
                flowerList[flowerCount] = .{
                    .entity = entity,
                    .gridX = gridPos.x + superOffset,
                    .gridY = gridPos.y + superOffset,
                    .sortKey = gridPos.x + gridPos.y + superOffset * 2,
                    .isDying = isDying,
                    .isSuper = isSuper,
                };
                flowerCount += 1;
            }
        }
    }

    std.mem.sort(FlowerRenderData, flowerList[0..flowerCount], {}, compareFlowers);

    for (flowerList[0..flowerCount]) |flowerData| {
        if (world.getFlowerGrowth(flowerData.entity)) |growth| {
            if (world.getSprite(flowerData.entity)) |sprite| {
                const source = rl.Rectangle.init(growth.state * sprite.width, 0, sprite.width, sprite.height);

                // Grown flowers are taller → they sway more. Per-flower phase from
                // grid position keeps the meadow from swaying in lockstep.
                const growthFrac = growth.state / 4.0;
                const phase = flowerData.gridX * 1.7 + flowerData.gridY * 0.9;
                const sway = @sin(time * 0.9 + phase) * 2.6 * growthFrac;

                // Ground shadow, scaled with how grown the flower is (and with
                // the whole block for SUPER flowers).
                const shadowMul: f32 = if (flowerData.isSuper) 2.0 else 1.0;
                drawGroundShadow(flowerData.gridX, flowerData.gridY, gridOffset, gridScale, (0.34 + 0.14 * growthFrac) * shadowMul, 0.22);

                if (growth.state == 4 and growth.hasPollen) {
                    // Pollen glow breathes and stays bright (untinted) so ready
                    // flowers pop, even at night.
                    const glowPulse = 0.1 + 0.05 * @sin(time * 3.0 + phase);
                    drawSpriteAtGridPosition(sprite.texture, flowerData.gridX, flowerData.gridY, source, sprite.scale + glowPulse, theme.CatppuccinMocha.Color.pollenGlow, gridOffset, gridScale, sway);
                }

                drawSpriteAtGridPosition(sprite.texture, flowerData.gridX, flowerData.gridY, source, sprite.scale, worldTint, gridOffset, gridScale, sway);

                if (flowerData.isDying) {
                    drawRebirthBubble(flowerData.gridX, flowerData.gridY, gridOffset, gridScale, time);
                }
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
        for (0..beeRenderCount) |i| {
            const bee = beeRenderList[i];
            const phase = @as(f32, @floatFromInt(i)) * 0.7;

            // Slow float bob + fast wing "buzz" scale flutter = alive, cozy bees.
            const bob = @sin(time * 2.0 + phase) * 2.2 * bee.scale;
            const buzz = 1.0 + 0.06 * @sin(time * 26.0 + phase);
            const drawScale = bee.scale * buzz;
            const cx = bee.x + 16 * bee.scale;

            // Ground shadow stays near the resting baseline; it shrinks and fades
            // as the bee floats higher, selling the vertical motion.
            const lift = std.math.clamp(-bob / (3.0 * bee.scale), -1.0, 1.0);
            const shadowScale = 1.0 - 0.25 * lift;
            drawEllipseSoft(cx, bee.y + 26 * bee.scale, 8.5 * bee.scale * shadowScale, 3.2 * bee.scale * shadowScale, @intFromFloat(60 * (1.0 - 0.35 * lift)));

            // Pollen-carriers get a warm glow so laden bees are easy to track.
            if (bee.carryingPollen) {
                rl.drawCircleGradient(rl.Vector2.init(cx, bee.y + bob + 14 * bee.scale), 16 * bee.scale, rl.Color.init(255, 226, 120, 90), rl.Color.init(255, 226, 120, 0));
            }

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
    rl.drawEllipse(@intFromFloat(cx), @intFromFloat(cy), rx, ry, rl.Color.init(0, 0, 0, alpha));
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

// A wilting flower can be saved by clicking it — shown as a soft, floating
// "care" heart rather than a clinical green plus, to match the cozy mood.
fn drawRebirthBubble(gridX: f32, gridY: f32, gridOffset: rl.Vector2, gridScale: f32, time: f32) void {
    const tilePosition = utils.isoToXY(gridX, gridY, 32, 32, gridOffset.x, gridOffset.y, gridScale);
    const tileWidth = 32 * gridScale;

    const bubbleRadius: f32 = 18 * (gridScale / 3.0);
    const bx = tilePosition.x + tileWidth / 2;
    // Gentle vertical bob so it feels like it's floating up, asking to be saved.
    const by = tilePosition.y - bubbleRadius * 1.5 + @sin(time * 2.5) * 3.0 * (gridScale / 3.0);

    const beat = 1.0 + @sin(time * 3.0) * 0.12; // soft heartbeat
    const s = bubbleRadius * 0.95 * beat;

    const rose = rl.Color.init(245, 128, 160, 255);
    const roseDeep = rl.Color.init(224, 96, 134, 255);

    // Warm halo.
    rl.drawCircleGradient(rl.Vector2.init(bx, by), s * 2.6, rl.Color.init(245, 150, 175, 90), rl.Color.init(245, 150, 175, 0));

    // Heart = two lobes + a downward point. A faint deeper outline underlay
    // gives it a little edge without a stroke pass.
    drawHeart(bx, by, s * 1.12, roseDeep);
    drawHeart(bx, by, s, rose);

    // Glossy highlight dab.
    rl.drawCircleV(rl.Vector2.init(bx - s * 0.34, by - s * 0.32), s * 0.17, rl.Color.init(255, 235, 240, 220));
}

/// Filled heart centred at (cx, cy). The bottom point is drawn as two triangles
/// with both windings so it renders regardless of cull state.
fn drawHeart(cx: f32, cy: f32, s: f32, color: rl.Color) void {
    rl.drawCircleV(rl.Vector2.init(cx - s * 0.45, cy - s * 0.28), s * 0.5, color);
    rl.drawCircleV(rl.Vector2.init(cx + s * 0.45, cy - s * 0.28), s * 0.5, color);
    const l = rl.Vector2.init(cx - s * 0.92, cy - s * 0.02);
    const r = rl.Vector2.init(cx + s * 0.92, cy - s * 0.02);
    const tip = rl.Vector2.init(cx, cy + s * 1.02);
    rl.drawTriangle(l, tip, r, color);
    rl.drawTriangle(l, r, tip, color);
}

pub fn getBubbleHitArea(gridX: f32, gridY: f32, gridOffset: rl.Vector2, gridScale: f32) struct { x: f32, y: f32, radius: f32 } {
    const tilePosition = utils.isoToXY(gridX, gridY, 32, 32, gridOffset.x, gridOffset.y, gridScale);
    const tileWidth = 32 * gridScale;
    const bubbleRadius: f32 = 18 * (gridScale / 3.0);
    const bubbleX = tilePosition.x + tileWidth / 2;
    const bubbleY = tilePosition.y - bubbleRadius * 1.5;

    return .{ .x = bubbleX, .y = bubbleY, .radius = bubbleRadius * 2.5 };
}

pub fn isFlowerDying(world: *World, entity: u32) bool {
    if (world.getFlowerGrowth(entity)) |growth| {
        if (growth.state < 4) return false;
    } else {
        return false;
    }

    if (world.getLifespan(entity)) |lifespan| {
        const timeRemaining = lifespan.timeSpan - lifespan.totalTimeAlive;
        return timeRemaining <= 5.0 and timeRemaining > 0;
    }
    return false;
}
