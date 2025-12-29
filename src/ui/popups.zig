const rl = @import("raylib");
const rg = @import("raygui");
const std = @import("std");

const Textures = @import("../textures.zig").Textures;
const Flowers = @import("../textures.zig").Flowers;
const World = @import("../ecs/world.zig").World;
const components = @import("../ecs/components.zig");
const FlowerType = components.FlowerType;

/// Actions that can be triggered from the tile popup
pub const TilePopupAction = enum {
    none,
    close,
    buy_bee,
    upgrade_beehive,
    upgrade_flower,
    plant_rose,
    plant_tulip,
    plant_dandelion,
};

/// Context needed to draw the tile popup
pub const TilePopupContext = struct {
    screenWidth: f32,
    screenHeight: f32,
    tileX: i32,
    tileY: i32,
    gridWidth: usize,
    gridHeight: usize,
    honey: f32,
    beeCount: usize,
    beehiveUpgradeCost: f32,
    textures: *const Textures,
    world: *World,
};

fn flowerTypeToFlowers(flowerType: FlowerType) Flowers {
    return switch (flowerType) {
        .rose => .rose,
        .tulip => .tulip,
        .dandelion => .dandelion,
    };
}

fn getFlowerName(flowerType: FlowerType) [:0]const u8 {
    return switch (flowerType) {
        .rose => "Rose",
        .tulip => "Tulip",
        .dandelion => "Dandelion",
    };
}

/// Draw the tile popup and return any action triggered
pub fn draw(ctx: TilePopupContext) TilePopupAction {
    // Draw semi-transparent overlay
    rl.drawRectangle(0, 0, @intFromFloat(ctx.screenWidth), @intFromFloat(ctx.screenHeight), rl.Color.init(0, 0, 0, 150));

    // Check tile state first to determine popup type
    const centerTileX = @as(i32, @intCast((ctx.gridWidth - 1) / 2));
    const centerTileY = @as(i32, @intCast((ctx.gridHeight - 1) / 2));
    const isBeehiveTile = (ctx.tileX == centerTileX and ctx.tileY == centerTileY);
    const flowerEntity = ctx.world.getFlowerAtGrid(ctx.tileX, ctx.tileY);
    const hasFlower = flowerEntity != null;

    // Popup dimensions - height varies based on content
    const popupWidth: f32 = 300;
    const popupHeight: f32 = if (isBeehiveTile) 320 else 280;
    const popupX: f32 = (ctx.screenWidth - popupWidth) / 2;
    const popupY: f32 = (ctx.screenHeight - popupHeight) / 2;

    // Draw popup panel background
    rl.drawRectangleRounded(
        rl.Rectangle.init(popupX, popupY, popupWidth, popupHeight),
        0.1,
        10,
        rl.Color.init(0x31, 0x32, 0x44, 0xff), // surface0
    );
    rl.drawRectangleRoundedLines(
        rl.Rectangle.init(popupX, popupY, popupWidth, popupHeight),
        0.1,
        10,
        rl.Color.init(0x45, 0x47, 0x5a, 0xff), // surface1
    );

    const buttonWidth: f32 = 250;
    const buttonHeight: f32 = 40;
    const buttonX = popupX + (popupWidth - buttonWidth) / 2;

    if (isBeehiveTile) {
        return drawBeehivePopup(ctx, popupX, popupY, popupWidth, buttonX, buttonWidth, buttonHeight);
    } else if (hasFlower) {
        return drawFlowerPopup(ctx, flowerEntity.?, popupX, popupY, popupWidth, buttonX, buttonWidth, buttonHeight);
    } else {
        return drawPlantingPopup(ctx, popupX, popupY, popupWidth, buttonX, buttonWidth, buttonHeight);
    }
}

fn drawBeehivePopup(
    ctx: TilePopupContext,
    popupX: f32,
    popupY: f32,
    popupWidth: f32,
    buttonX: f32,
    buttonWidth: f32,
    buttonHeight: f32,
) TilePopupAction {
    const titleText = "Beehive";
    const titleX = @as(i32, @intFromFloat(popupX + popupWidth / 2)) - @divFloor(rl.measureText(titleText, 24), 2);
    rl.drawText(titleText, titleX, @as(i32, @intFromFloat(popupY + 15)), 24, rl.Color.init(0xcd, 0xd6, 0xf4, 0xff));

    // Draw beehive icon
    const largeIconSize: f32 = 64;
    const largeIconX = popupX + (popupWidth - largeIconSize) / 2;
    const largeIconY = popupY + 45;
    const largeDest = rl.Rectangle.init(largeIconX, largeIconY, largeIconSize, largeIconSize);
    rl.drawTexturePro(ctx.textures.beehive, rl.Rectangle.init(0, 0, 32, 32), largeDest, rl.Vector2.init(0, 0), 0, rl.Color.white);

    // Get beehive data
    var honeyFactor: f32 = 1.0;
    var beehiveIter = ctx.world.entityToBeehive.keyIterator();
    if (beehiveIter.next()) |beehiveEntity| {
        if (ctx.world.getBeehive(beehiveEntity.*)) |beehive| {
            honeyFactor = beehive.honeyConversionFactor;
        }
    }

    // Show current honey conversion factor
    const factorText = rl.textFormat("Honey Conversion: %.1fx", .{honeyFactor});
    const factorX = @as(i32, @intFromFloat(popupX + popupWidth / 2)) - @divFloor(rl.measureText(factorText, 18), 2);
    rl.drawText(factorText, factorX, @as(i32, @intFromFloat(popupY + 115)), 18, rl.Color.init(0xf9, 0xe2, 0xaf, 0xff));

    // Show bee count
    const beeCountText = rl.textFormat("Bees: %d", .{ctx.beeCount});
    const beeCountX = @as(i32, @intFromFloat(popupX + popupWidth / 2)) - @divFloor(rl.measureText(beeCountText, 16), 2);
    rl.drawText(beeCountText, beeCountX, @as(i32, @intFromFloat(popupY + 140)), 16, rl.Color.init(0xa6, 0xad, 0xc8, 0xff));

    const buttonStartY = popupY + 170;
    const buttonSpacing: f32 = 45;

    // Upgrade beehive button
    const canAffordUpgrade = ctx.honey >= ctx.beehiveUpgradeCost;
    if (!canAffordUpgrade) {
        rg.setState(@intFromEnum(rg.State.disabled));
    }
    const upgradeText = rl.textFormat("Upgrade to %.1fx (%.0f Honey)", .{ honeyFactor * 2.0, ctx.beehiveUpgradeCost });
    if (rg.button(rl.Rectangle.init(buttonX, buttonStartY, buttonWidth, buttonHeight), upgradeText) and canAffordUpgrade) {
        rg.setState(@intFromEnum(rg.State.normal));
        return .upgrade_beehive;
    }
    rg.setState(@intFromEnum(rg.State.normal));

    // Buy bee button
    const beeCost: f32 = 10.0;
    const canAffordBee = ctx.honey >= beeCost;
    if (!canAffordBee) {
        rg.setState(@intFromEnum(rg.State.disabled));
    }
    if (rg.button(rl.Rectangle.init(buttonX, buttonStartY + buttonSpacing, buttonWidth, buttonHeight), "Buy Bee (10 Honey)") and canAffordBee) {
        rg.setState(@intFromEnum(rg.State.normal));
        return .buy_bee;
    }
    rg.setState(@intFromEnum(rg.State.normal));

    // Close button
    if (rg.button(rl.Rectangle.init(buttonX, buttonStartY + buttonSpacing * 2, buttonWidth, buttonHeight), "Close")) {
        return .close;
    }

    return .none;
}

fn drawFlowerPopup(
    ctx: TilePopupContext,
    flowerEntity: u32,
    popupX: f32,
    popupY: f32,
    popupWidth: f32,
    buttonX: f32,
    buttonWidth: f32,
    buttonHeight: f32,
) TilePopupAction {
    // Icon settings - show fully grown flower (state 4, frame at x=128)
    const frameSize: f32 = 32;
    const fullyGrownFrame: f32 = 4;
    const sourceRect = rl.Rectangle.init(fullyGrownFrame * frameSize, 0, frameSize, frameSize);

    if (ctx.world.getFlowerGrowth(flowerEntity)) |growth| {
        const flowerName = getFlowerName(growth.flowerType);
        const titleX = @as(i32, @intFromFloat(popupX + popupWidth / 2)) - @divFloor(rl.measureText(flowerName, 24), 2);
        rl.drawText(flowerName, titleX, @as(i32, @intFromFloat(popupY + 15)), 24, rl.Color.init(0xcd, 0xd6, 0xf4, 0xff));

        // Draw large flower icon
        const largeIconSize: f32 = 64;
        const largeIconX = popupX + (popupWidth - largeIconSize) / 2;
        const largeIconY = popupY + 50;
        const largeDest = rl.Rectangle.init(largeIconX, largeIconY, largeIconSize, largeIconSize);
        const flowerTexture = ctx.textures.getFlowerTexture(flowerTypeToFlowers(growth.flowerType));
        rl.drawTexturePro(flowerTexture, sourceRect, largeDest, rl.Vector2.init(0, 0), 0, rl.Color.white);

        // Show current multiplier
        const multiplierText = rl.textFormat("Pollen Multiplier: %.1fx", .{growth.pollenMultiplier});
        const multiplierX = @as(i32, @intFromFloat(popupX + popupWidth / 2)) - @divFloor(rl.measureText(multiplierText, 18), 2);
        rl.drawText(multiplierText, multiplierX, @as(i32, @intFromFloat(popupY + 125)), 18, rl.Color.init(0xf9, 0xe2, 0xaf, 0xff));

        // Upgrade button
        const upgradeCost = 20.0 * growth.pollenMultiplier;
        const canAffordUpgrade = ctx.honey >= upgradeCost;
        const buttonStartY = popupY + 160;

        if (!canAffordUpgrade) {
            rg.setState(@intFromEnum(rg.State.disabled));
        }
        const upgradeText = rl.textFormat("Upgrade to %.1fx (%.0f Honey)", .{ growth.pollenMultiplier + 0.5, upgradeCost });
        if (rg.button(rl.Rectangle.init(buttonX, buttonStartY, buttonWidth, buttonHeight), upgradeText) and canAffordUpgrade) {
            rg.setState(@intFromEnum(rg.State.normal));
            return .upgrade_flower;
        }
        rg.setState(@intFromEnum(rg.State.normal));

        // Close button
        if (rg.button(rl.Rectangle.init(buttonX, buttonStartY + 50, buttonWidth, buttonHeight), "Close")) {
            return .close;
        }
    }

    return .none;
}

fn drawPlantingPopup(
    ctx: TilePopupContext,
    popupX: f32,
    popupY: f32,
    popupWidth: f32,
    buttonX: f32,
    buttonWidth: f32,
    buttonHeight: f32,
) TilePopupAction {
    // Icon settings
    const frameSize: f32 = 32;
    const fullyGrownFrame: f32 = 4;
    const iconSize: f32 = 32;
    const iconPadding: f32 = 8;
    const sourceRect = rl.Rectangle.init(fullyGrownFrame * frameSize, 0, frameSize, frameSize);

    const titleText = "Plant a Flower";
    const titleX = @as(i32, @intFromFloat(popupX + popupWidth / 2)) - @divFloor(rl.measureText(titleText, 24), 2);
    rl.drawText(titleText, titleX, @as(i32, @intFromFloat(popupY + 15)), 24, rl.Color.init(0xcd, 0xd6, 0xf4, 0xff));

    const tileInfoText = rl.textFormat("Tile: (%d, %d)", .{ ctx.tileX, ctx.tileY });
    const tileInfoX = @as(i32, @intFromFloat(popupX + popupWidth / 2)) - @divFloor(rl.measureText(tileInfoText, 16), 2);
    rl.drawText(tileInfoText, tileInfoX, @as(i32, @intFromFloat(popupY + 45)), 16, rl.Color.init(0xa6, 0xad, 0xc8, 0xff));

    const buttonStartY = popupY + 80;
    const buttonSpacing: f32 = 50;

    // Rose button (10 honey)
    const roseCost: f32 = 10.0;
    const canAffordRose = ctx.honey >= roseCost;
    if (!canAffordRose) {
        rg.setState(@intFromEnum(rg.State.disabled));
    }
    if (rg.button(rl.Rectangle.init(buttonX, buttonStartY, buttonWidth, buttonHeight), "      Rose (10 Honey)") and canAffordRose) {
        rg.setState(@intFromEnum(rg.State.normal));
        return .plant_rose;
    }
    rg.setState(@intFromEnum(rg.State.normal));
    // Draw rose icon
    const roseIconX = buttonX + iconPadding;
    const roseIconY = buttonStartY + (buttonHeight - iconSize) / 2;
    const roseDest = rl.Rectangle.init(roseIconX, roseIconY, iconSize, iconSize);
    rl.drawTexturePro(ctx.textures.rose, sourceRect, roseDest, rl.Vector2.init(0, 0), 0, rl.Color.white);

    // Tulip button (15 honey)
    const tulipCost: f32 = 15.0;
    const canAffordTulip = ctx.honey >= tulipCost;
    if (!canAffordTulip) {
        rg.setState(@intFromEnum(rg.State.disabled));
    }
    if (rg.button(rl.Rectangle.init(buttonX, buttonStartY + buttonSpacing, buttonWidth, buttonHeight), "      Tulip (15 Honey)") and canAffordTulip) {
        rg.setState(@intFromEnum(rg.State.normal));
        return .plant_tulip;
    }
    rg.setState(@intFromEnum(rg.State.normal));
    // Draw tulip icon
    const tulipIconX = buttonX + iconPadding;
    const tulipIconY = buttonStartY + buttonSpacing + (buttonHeight - iconSize) / 2;
    const tulipDest = rl.Rectangle.init(tulipIconX, tulipIconY, iconSize, iconSize);
    rl.drawTexturePro(ctx.textures.tulip, sourceRect, tulipDest, rl.Vector2.init(0, 0), 0, rl.Color.white);

    // Dandelion button (5 honey)
    const dandelionCost: f32 = 5.0;
    const canAffordDandelion = ctx.honey >= dandelionCost;
    if (!canAffordDandelion) {
        rg.setState(@intFromEnum(rg.State.disabled));
    }
    if (rg.button(rl.Rectangle.init(buttonX, buttonStartY + buttonSpacing * 2, buttonWidth, buttonHeight), "      Dandelion (5 Honey)") and canAffordDandelion) {
        rg.setState(@intFromEnum(rg.State.normal));
        return .plant_dandelion;
    }
    rg.setState(@intFromEnum(rg.State.normal));
    // Draw dandelion icon
    const dandelionIconX = buttonX + iconPadding;
    const dandelionIconY = buttonStartY + buttonSpacing * 2 + (buttonHeight - iconSize) / 2;
    const dandelionDest = rl.Rectangle.init(dandelionIconX, dandelionIconY, iconSize, iconSize);
    rl.drawTexturePro(ctx.textures.dandelion, sourceRect, dandelionDest, rl.Vector2.init(0, 0), 0, rl.Color.white);

    // Cancel button
    if (rg.button(rl.Rectangle.init(buttonX, buttonStartY + buttonSpacing * 3, buttonWidth, buttonHeight), "Cancel")) {
        return .close;
    }

    return .none;
}
