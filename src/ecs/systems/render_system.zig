const rl = @import("raylib");
const std = @import("std");
const World = @import("../world.zig").World;
const utils = @import("../../utils.zig");

const FlowerRenderData = struct {
    entity: u32,
    gridX: f32,
    gridY: f32,
    sortKey: f32,
};

fn compareFlowers(context: void, a: FlowerRenderData, b: FlowerRenderData) bool {
    _ = context;
    return a.sortKey < b.sortKey;
}

// Pre-allocated bee render data to avoid per-frame allocations
const MAX_BEES: usize = 16384;
const BeeRenderData = struct {
    x: f32,
    y: f32,
    scale: f32,
    carryingPollen: bool,
};
var beeRenderList: [MAX_BEES]BeeRenderData = undefined;
var beeRenderCount: usize = 0;

// Cached screen dimensions for frustum culling
var cachedScreenWidth: f32 = 0;
var cachedScreenHeight: f32 = 0;
const FRUSTUM_MARGIN: f32 = 50.0;

pub fn draw(world: *World, gridOffset: rl.Vector2, gridScale: f32) !void {
    // Update cached screen dimensions
    cachedScreenWidth = @floatFromInt(rl.getScreenWidth());
    cachedScreenHeight = @floatFromInt(rl.getScreenHeight());

    var beehiveIter = world.entityToBeehive.keyIterator();
    while (beehiveIter.next()) |entity| {
        if (world.getGridPosition(entity.*)) |gridPos| {
            if (world.getSprite(entity.*)) |sprite| {
                drawBeehiveAtGridPosition(sprite.texture, gridPos.x, gridPos.y, sprite.width, sprite.height, sprite.scale, gridOffset, gridScale);
            }
        }
    }

    var flowerList: [512]FlowerRenderData = undefined;
    var flowerCount: usize = 0;

    var flowerIter = world.iterateFlowers();
    while (flowerIter.next()) |entity| {
        if (world.getGridPosition(entity)) |gridPos| {
            if (world.getLifespan(entity)) |lifespan| {
                if (lifespan.isDead()) continue;
            }
            if (flowerCount < flowerList.len) {
                flowerList[flowerCount] = .{
                    .entity = entity,
                    .gridX = gridPos.x,
                    .gridY = gridPos.y,
                    .sortKey = gridPos.x + gridPos.y,
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
                    drawSpriteAtGridPosition(sprite.texture, flowerData.gridX, flowerData.gridY, source, sprite.scale + 0.1, rl.Color.init(255, 255, 100, 128), gridOffset, gridScale);
                }

                drawSpriteAtGridPosition(sprite.texture, flowerData.gridX, flowerData.gridY, source, sprite.scale, rl.Color.white, gridOffset, gridScale);
            }
        }
    }

    // Build bee render list with frustum culling
    buildBeeRenderList(world);

    // Get bee texture once for all bees (they all use the same texture)
    var beeTexture: ?rl.Texture = null;
    var beeIter = world.iterateBees();
    if (beeIter.next()) |firstBee| {
        if (world.getSprite(firstBee)) |sprite| {
            beeTexture = sprite.texture;
        }
    }

    // Batch draw all bees - same texture, minimizes state changes
    if (beeTexture) |texture| {
        for (0..beeRenderCount) |i| {
            const bee = beeRenderList[i];
            const color = if (bee.carryingPollen) rl.Color.yellow else rl.Color.white;
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
            // Frustum culling - skip bees outside screen
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
