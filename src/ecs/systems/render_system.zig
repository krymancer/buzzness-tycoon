const rl = @import("raylib");
const std = @import("std");
const World = @import("../world.zig").World;
const utils = @import("../../utils.zig");
const theme = @import("../../theme.zig");

const FlowerRenderData = struct {
    entity: u32,
    gridX: f32,
    gridY: f32,
    sortKey: f32,
    isDying: bool,
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

pub fn draw(world: *World, gridOffset: rl.Vector2, gridScale: f32) !void {
    cachedScreenWidth = @floatFromInt(rl.getScreenWidth());
    cachedScreenHeight = @floatFromInt(rl.getScreenHeight());

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
        drawBeehiveAtGridPosition(bh.texture, bh.gridX, bh.gridY, bh.width, bh.height, bh.scale, gridOffset, gridScale);
    }

    const time = @as(f32, @floatCast(rl.getTime()));

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
            if (flowerCount < flowerList.len) {
                flowerList[flowerCount] = .{
                    .entity = entity,
                    .gridX = gridPos.x,
                    .gridY = gridPos.y,
                    .sortKey = gridPos.x + gridPos.y,
                    .isDying = isDying,
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

                if (growth.state == 4 and growth.hasPollen) {
                    drawSpriteAtGridPosition(sprite.texture, flowerData.gridX, flowerData.gridY, source, sprite.scale + 0.1, theme.CatppuccinMocha.Color.pollenGlow, gridOffset, gridScale);
                }

                drawSpriteAtGridPosition(sprite.texture, flowerData.gridX, flowerData.gridY, source, sprite.scale, rl.Color.white, gridOffset, gridScale);

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
            const color = if (bee.carryingPollen) pollenColor else bee.color;
            rl.drawTextureEx(texture, rl.Vector2.init(bee.x, bee.y), 0, bee.scale, color);
        }
    }
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

fn drawSpriteAtGridPosition(texture: rl.Texture, i: f32, j: f32, sourceRect: rl.Rectangle, scale: f32, color: rl.Color, gridOffset: rl.Vector2, gridScale: f32) void {
    const tilePosition = utils.isoToXY(i, j, 32, 32, gridOffset.x, gridOffset.y, gridScale);
    const effectiveScale = scale * (gridScale / 3.0);
    const tileWidth = 32 * gridScale;
    const tileHeight = 32 * gridScale;

    const centeredX = tilePosition.x + (tileWidth - sourceRect.width * effectiveScale) / 2.0;
    const centeredY = tilePosition.y + (tileHeight * 0.25) - (sourceRect.height * effectiveScale);
    const destination = rl.Rectangle.init(centeredX, centeredY, sourceRect.width * effectiveScale, sourceRect.height * effectiveScale);

    rl.drawTexturePro(texture, sourceRect, destination, rl.Vector2.init(0, 0), 0, color);
}

fn drawBeehiveAtGridPosition(texture: rl.Texture, i: f32, j: f32, width: f32, height: f32, scale: f32, gridOffset: rl.Vector2, gridScale: f32) void {
    const tilePosition = utils.isoToXY(i, j, 32, 32, gridOffset.x, gridOffset.y, gridScale);
    const effectiveScale = scale * (gridScale / 3.0);
    const tileWidth = 32 * gridScale;
    const tileHeight = 32 * gridScale;

    const centeredX = tilePosition.x + (tileWidth - width * effectiveScale) / 2.0;
    const centeredY = tilePosition.y + (tileHeight * 0.5) - (height * effectiveScale);
    const source = rl.Rectangle.init(0, 0, width, height);
    const destination = rl.Rectangle.init(centeredX, centeredY, width * effectiveScale, height * effectiveScale);

    rl.drawTexturePro(texture, source, destination, rl.Vector2.init(0, 0), 0, rl.Color.white);
}

fn drawRebirthBubble(gridX: f32, gridY: f32, gridOffset: rl.Vector2, gridScale: f32, time: f32) void {
    const tilePosition = utils.isoToXY(gridX, gridY, 32, 32, gridOffset.x, gridOffset.y, gridScale);
    const tileWidth = 32 * gridScale;

    const bubbleRadius: f32 = 18 * (gridScale / 3.0);
    const bubbleX = tilePosition.x + tileWidth / 2;
    const bubbleY = tilePosition.y - bubbleRadius * 1.5;

    const t = time * 4.0;
    const pulse = 1.0 + @sin(t) * 0.25;
    const animatedRadius = bubbleRadius * pulse;

    rl.drawCircle(@intFromFloat(bubbleX), @intFromFloat(bubbleY), animatedRadius + 8, rl.Color.init(0xa6, 0xe3, 0xa1, 40));
    rl.drawCircle(@intFromFloat(bubbleX), @intFromFloat(bubbleY), animatedRadius + 4, rl.Color.init(0xa6, 0xe3, 0xa1, 80));
    rl.drawCircle(@intFromFloat(bubbleX), @intFromFloat(bubbleY), animatedRadius, theme.CatppuccinMocha.Color.green);

    const ringPulse = 1.0 + @sin(t * 1.5) * 0.3;
    const ringRadius = animatedRadius * ringPulse;
    rl.drawCircleLines(@intFromFloat(bubbleX), @intFromFloat(bubbleY), ringRadius + 2, rl.Color.white);

    const plusSize: i32 = @intFromFloat(animatedRadius * 0.5);
    const cx: i32 = @intFromFloat(bubbleX);
    const cy: i32 = @intFromFloat(bubbleY);
    rl.drawLine(cx - plusSize, cy, cx + plusSize, cy, rl.Color.white);
    rl.drawLine(cx, cy - plusSize, cx, cy + plusSize, rl.Color.white);
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
