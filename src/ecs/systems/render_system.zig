const rl = @import("raylib");
const World = @import("../world.zig").World;
const utils = @import("../../utils.zig");

pub fn draw(world: *World, gridOffset: rl.Vector2, gridScale: f32) !void {
    // Draw beehive first (so it's behind other entities)
    var beehiveIter = world.entityToBeehive.keyIterator();
    while (beehiveIter.next()) |entity| {
        if (world.getGridPosition(entity.*)) |gridPos| {
            if (world.getSprite(entity.*)) |sprite| {
                drawBeehiveAtGridPosition(
                    sprite.texture,
                    gridPos.x,
                    gridPos.y,
                    sprite.width,
                    sprite.height,
                    sprite.scale,
                    gridOffset,
                    gridScale,
                );
            }
        }
    }

    var flowerIter = world.iterateFlowers();
    while (flowerIter.next()) |entity| {
        if (world.getFlowerGrowth(entity)) |growth| {
            if (world.getGridPosition(entity)) |gridPos| {
                if (world.getSprite(entity)) |sprite| {
                    if (world.getLifespan(entity)) |lifespan| {
                        if (lifespan.isDead()) {
                            continue;
                        }
                    }

                    const source = rl.Rectangle.init(growth.state * sprite.width, 0, sprite.width, sprite.height);

                    if (growth.state == 4 and growth.hasPollen) {
                        drawSpriteAtGridPosition(
                            sprite.texture,
                            gridPos.x,
                            gridPos.y,
                            source,
                            sprite.scale + 0.1,
                            rl.Color.init(255, 255, 100, 128),
                            gridOffset,
                            gridScale,
                        );
                    }

                    drawSpriteAtGridPosition(
                        sprite.texture,
                        gridPos.x,
                        gridPos.y,
                        source,
                        sprite.scale,
                        rl.Color.white,
                        gridOffset,
                        gridScale,
                    );
                }
            }
        }
    }

    var beeIter = world.iterateBees();
    while (beeIter.next()) |entity| {
        if (world.getPosition(entity)) |position| {
            // Frustum culling - skip bees that are off-screen
            const screenWidth: f32 = @floatFromInt(rl.getScreenWidth());
            const screenHeight: f32 = @floatFromInt(rl.getScreenHeight());
            const margin: f32 = 50.0; // Small margin to avoid popping
            if (position.x < -margin or position.x > screenWidth + margin or
                position.y < -margin or position.y > screenHeight + margin)
            {
                continue;
            }

            if (world.getSprite(entity)) |sprite| {
                if (world.getScaleSync(entity)) |scaleSync| {
                    if (world.getBeeAI(entity)) |beeAI| {
                        if (world.getLifespan(entity)) |lifespan| {
                            if (lifespan.isDead()) {
                                continue;
                            }
                        }

                        const color = if (beeAI.carryingPollen) rl.Color.yellow else rl.Color.white;
                        rl.drawTextureEx(sprite.texture, position.toVector2(), 0, scaleSync.effectiveScale, color);
                    }
                }
            }
        }
    }
}

fn drawSpriteAtGridPosition(
    texture: rl.Texture,
    i: f32,
    j: f32,
    sourceRect: rl.Rectangle,
    scale: f32,
    color: rl.Color,
    gridOffset: rl.Vector2,
    gridScale: f32,
) void {
    const tilePosition = utils.isoToXY(i, j, 32, 32, gridOffset.x, gridOffset.y, gridScale);
    const effectiveScale = scale * (gridScale / 3.0);

    const tileWidth = 32 * gridScale;
    const tileHeight = 32 * gridScale;

    const centeredX = tilePosition.x + (tileWidth - sourceRect.width * effectiveScale) / 2.0;
    const centeredY = tilePosition.y + (tileHeight * 0.25) - (sourceRect.height * effectiveScale);

    const destination = rl.Rectangle.init(centeredX, centeredY, sourceRect.width * effectiveScale, sourceRect.height * effectiveScale);

    rl.drawTexturePro(texture, sourceRect, destination, rl.Vector2.init(0, 0), 0, color);
}

fn drawBeehiveAtGridPosition(
    texture: rl.Texture,
    i: f32,
    j: f32,
    width: f32,
    height: f32,
    scale: f32,
    gridOffset: rl.Vector2,
    gridScale: f32,
) void {
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
