const rl = @import("raylib");
const text = @import("../text.zig");
const rg = @import("raygui");
const std = @import("std");

const theme = @import("../theme.zig");
const format = @import("../format.zig");
const Textures = @import("../textures.zig").Textures;
const Flowers = @import("../textures.zig").Flowers;
const World = @import("../ecs/world.zig").World;
const Resources = @import("../resources.zig").Resources;
const components = @import("../ecs/components.zig");
const FlowerType = components.FlowerType;
const locale = @import("../localization.zig");

/// Actions that can be triggered from the tile popup
pub const TilePopupAction = enum {
    none,
    close,
    buy_worker_bee,
    buy_swift_bee,
    buy_efficient_bee,
    buy_gardener_bee,
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
    resources: *const Resources,
    beeCount: usize,
    beehiveUpgradeCost: f32,
    textures: *const Textures,
    world: *World,
    // Whether the Instant Grow tree node is owned; hides the grow-cooldown
    // upgrade button while the ability itself is still locked.
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
        .rose => locale.tr("Rose", "Rosa"),
        .tulip => locale.tr("Tulip", "Tulipa"),
        .dandelion => locale.tr("Dandelion", "Dente-de-leão"),
    };
}

/// Draw the tile popup and return any action triggered
pub fn draw(ctx: TilePopupContext) TilePopupAction {
    // Draw semi-transparent overlay
    rl.drawRectangle(0, 0, @intFromFloat(ctx.screenWidth), @intFromFloat(ctx.screenHeight), theme.CatppuccinMocha.Color.modalOverlay);

    // Check tile state first to determine popup type
    const centerTileX = @as(i32, @intCast((ctx.gridWidth - 1) / 2));
    const centerTileY = @as(i32, @intCast((ctx.gridHeight - 1) / 2));
    const isBeehiveTile = (ctx.tileX == centerTileX and ctx.tileY == centerTileY);
    const flowerEntity = ctx.world.getFlowerAtGrid(ctx.tileX, ctx.tileY);
    const hasFlower = flowerEntity != null;

    // Popup dimensions - height varies based on content
    const popupWidth: f32 = 380;
    const popupHeight: f32 = if (isBeehiveTile) 560 else 280;
    const popupX: f32 = (ctx.screenWidth - popupWidth) / 2;
    const popupY: f32 = (ctx.screenHeight - popupHeight) / 2;

    // Draw popup panel background
    rl.drawRectangleRounded(
        rl.Rectangle.init(popupX, popupY, popupWidth, popupHeight),
        0.1,
        10,
        theme.CatppuccinMocha.Color.surface0,
    );
    rl.drawRectangleRoundedLines(
        rl.Rectangle.init(popupX, popupY, popupWidth, popupHeight),
        0.1,
        10,
        theme.CatppuccinMocha.Color.surface1,
    );

    const buttonWidth: f32 = 330;
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
    _: f32, // buttonHeight unused - using smallButtonHeight
) TilePopupAction {
    const spawners = @import("../spawners.zig");

    const titleText = locale.tr("Beehive", "Colmeia");
    const titleX = @as(i32, @intFromFloat(popupX + popupWidth / 2)) - @divFloor(text.measure(titleText, 24), 2);
    text.draw(titleText, titleX, @as(i32, @intFromFloat(popupY + 15)), 24, theme.CatppuccinMocha.Color.text);

    // Draw beehive icon
    const largeIconSize: f32 = 48;
    const largeIconX = popupX + (popupWidth - largeIconSize) / 2;
    const largeIconY = popupY + 40;
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

    // Compact info section
    const infoY = popupY + 95;
    const factorText = rl.textFormat(locale.tr("Honey: %.1fx | Bees: %d", "Mel: %.1fx | Abelhas: %d"), .{ honeyFactor, ctx.beeCount });
    const factorX = @as(i32, @intFromFloat(popupX + popupWidth / 2)) - @divFloor(text.measure(factorText, 18), 2);
    text.draw(factorText, factorX, @as(i32, @intFromFloat(infoY)), 18, theme.CatppuccinMocha.Color.yellow);

    const buttonStartY = popupY + 120;
    const buttonSpacing: f32 = 38;
    const smallButtonHeight: f32 = 32;

    // Upgrade beehive button
    const canAffordUpgrade = ctx.resources.honey >= ctx.beehiveUpgradeCost;
    if (!canAffordUpgrade) {
        rg.setState(@intFromEnum(rg.State.disabled));
    }
    const upgradeText = rl.textFormat(locale.tr("Honey %.1fx (%.0f)", "Mel %.1fx (%.0f)"), .{ honeyFactor * 2.0, ctx.beehiveUpgradeCost });
    if (rg.button(rl.Rectangle.init(buttonX, buttonStartY, buttonWidth, smallButtonHeight), upgradeText) and canAffordUpgrade) {
        rg.setState(@intFromEnum(rg.State.normal));
        return .upgrade_beehive;
    }
    rg.setState(@intFromEnum(rg.State.normal));

    // Section header for bees
    const beeHeaderY = buttonStartY + buttonSpacing + 5;
    const beeHeaderText = locale.tr("-- Buy Bees --", "-- Comprar Abelhas --");
    const beeHeaderX = @as(i32, @intFromFloat(popupX + popupWidth / 2)) - @divFloor(text.measure(beeHeaderText, 18), 2);
    text.draw(beeHeaderText, beeHeaderX, @as(i32, @intFromFloat(beeHeaderY)), 18, theme.CatppuccinMocha.Color.subtext0);

    const beeButtonStartY = beeHeaderY + 20;

    // Worker Bee button
    const workerCost = spawners.BEE_TYPE_COSTS.worker;
    const canAffordWorker = ctx.resources.honey >= workerCost;
    if (!canAffordWorker) {
        rg.setState(@intFromEnum(rg.State.disabled));
    }
    if (rg.button(rl.Rectangle.init(buttonX, beeButtonStartY, buttonWidth, smallButtonHeight), rl.textFormat(locale.tr("Worker Bee (%.0f)", "Abelha Operária (%.0f)"), .{workerCost})) and canAffordWorker) {
        rg.setState(@intFromEnum(rg.State.normal));
        return .buy_worker_bee;
    }
    rg.setState(@intFromEnum(rg.State.normal));

    // Swift Bee button (blue)
    const swiftCost = spawners.BEE_TYPE_COSTS.swift;
    const canAffordSwift = ctx.resources.honey >= swiftCost;
    if (!canAffordSwift) {
        rg.setState(@intFromEnum(rg.State.disabled));
    }
    if (rg.button(rl.Rectangle.init(buttonX, beeButtonStartY + buttonSpacing, buttonWidth, smallButtonHeight), rl.textFormat(locale.tr("Swift Bee 2x Speed (%.0f)", "Abelha Veloz 2x (%.0f)"), .{swiftCost})) and canAffordSwift) {
        rg.setState(@intFromEnum(rg.State.normal));
        return .buy_swift_bee;
    }
    rg.setState(@intFromEnum(rg.State.normal));

    // Efficient Bee button (green)
    const efficientCost = spawners.BEE_TYPE_COSTS.efficient;
    const canAffordEfficient = ctx.resources.honey >= efficientCost;
    if (!canAffordEfficient) {
        rg.setState(@intFromEnum(rg.State.disabled));
    }
    if (rg.button(rl.Rectangle.init(buttonX, beeButtonStartY + buttonSpacing * 2, buttonWidth, smallButtonHeight), rl.textFormat(locale.tr("Efficient Bee 2x Pollen (%.0f)", "Abelha Eficiente 2x Pólen (%.0f)"), .{efficientCost})) and canAffordEfficient) {
        rg.setState(@intFromEnum(rg.State.normal));
        return .buy_efficient_bee;
    }
    rg.setState(@intFromEnum(rg.State.normal));

    // Gardener Bee button (pink)
    const gardenerCost = spawners.BEE_TYPE_COSTS.gardener;
    const canAffordGardener = ctx.resources.honey >= gardenerCost;
    if (!canAffordGardener) {
        rg.setState(@intFromEnum(rg.State.disabled));
    }
    if (rg.button(rl.Rectangle.init(buttonX, beeButtonStartY + buttonSpacing * 3, buttonWidth, smallButtonHeight), rl.textFormat(locale.tr("Gardener Bee Plants (%.0f)", "Abelha Jardineira (%.0f)"), .{gardenerCost})) and canAffordGardener) {
        rg.setState(@intFromEnum(rg.State.normal));
        return .buy_gardener_bee;
    }
    rg.setState(@intFromEnum(rg.State.normal));

    // Close button
    if (rg.button(rl.Rectangle.init(buttonX, beeButtonStartY + buttonSpacing * 4, buttonWidth, smallButtonHeight), locale.tr("Close", "Fechar"))) {
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
        const titleX = @as(i32, @intFromFloat(popupX + popupWidth / 2)) - @divFloor(text.measure(flowerName, 24), 2);
        text.draw(flowerName, titleX, @as(i32, @intFromFloat(popupY + 15)), 24, theme.CatppuccinMocha.Color.text);

        // Draw large flower icon
        const largeIconSize: f32 = 64;
        const largeIconX = popupX + (popupWidth - largeIconSize) / 2;
        const largeIconY = popupY + 50;
        const largeDest = rl.Rectangle.init(largeIconX, largeIconY, largeIconSize, largeIconSize);
        const flowerTexture = ctx.textures.getFlowerTexture(flowerTypeToFlowers(growth.flowerType));
        rl.drawTexturePro(flowerTexture, sourceRect, largeDest, rl.Vector2.init(0, 0), 0, rl.Color.white);

        // Show current multiplier
        const multiplierText = rl.textFormat(locale.tr("Pollen Multiplier: %.1fx", "Multiplicador de pólen: %.1fx"), .{growth.pollenMultiplier});
        const multiplierX = @as(i32, @intFromFloat(popupX + popupWidth / 2)) - @divFloor(text.measure(multiplierText, 18), 2);
        text.draw(multiplierText, multiplierX, @as(i32, @intFromFloat(popupY + 125)), 18, theme.CatppuccinMocha.Color.yellow);

        // Upgrade button
        const upgradeCost = 20.0 * growth.pollenMultiplier;
        const canAffordUpgrade = ctx.resources.honey >= upgradeCost;
        const buttonStartY = popupY + 160;

        if (!canAffordUpgrade) {
            rg.setState(@intFromEnum(rg.State.disabled));
        }
        var cbuf: [32]u8 = undefined;
        const cstr = format.formatShort(upgradeCost, &cbuf);
        const upgradeText = rl.textFormat(locale.tr("Upgrade to %.1fx (%s Honey)", "Melhorar para %.1fx (%s Mel)"), .{ growth.pollenMultiplier + 0.5, cstr.ptr });
        if (rg.button(rl.Rectangle.init(buttonX, buttonStartY, buttonWidth, buttonHeight), upgradeText) and canAffordUpgrade) {
            rg.setState(@intFromEnum(rg.State.normal));
            return .upgrade_flower;
        }
        rg.setState(@intFromEnum(rg.State.normal));

        // Close button
        if (rg.button(rl.Rectangle.init(buttonX, buttonStartY + 50, buttonWidth, buttonHeight), locale.tr("Close", "Fechar"))) {
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

    const titleText = locale.tr("Plant a Flower", "Plantar uma Flor");
    const titleX = @as(i32, @intFromFloat(popupX + popupWidth / 2)) - @divFloor(text.measure(titleText, 24), 2);
    text.draw(titleText, titleX, @as(i32, @intFromFloat(popupY + 15)), 24, theme.CatppuccinMocha.Color.text);

    const tileInfoText = rl.textFormat(locale.tr("Tile: (%d, %d)", "Bloco: (%d, %d)"), .{ ctx.tileX, ctx.tileY });
    const tileInfoX = @as(i32, @intFromFloat(popupX + popupWidth / 2)) - @divFloor(text.measure(tileInfoText, 16), 2);
    text.draw(tileInfoText, tileInfoX, @as(i32, @intFromFloat(popupY + 45)), 16, theme.CatppuccinMocha.Color.subtext0);

    const buttonStartY = popupY + 80;
    const buttonSpacing: f32 = 50;

    // Rose button (10 honey)
    const roseCost: f32 = 10.0;
    const canAffordRose = ctx.resources.honey >= roseCost;
    if (!canAffordRose) {
        rg.setState(@intFromEnum(rg.State.disabled));
    }
    if (rg.button(rl.Rectangle.init(buttonX, buttonStartY, buttonWidth, buttonHeight), locale.tr("      Rose (10 Honey)", "      Rosa (10 Mel)")) and canAffordRose) {
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
    const canAffordTulip = ctx.resources.honey >= tulipCost;
    if (!canAffordTulip) {
        rg.setState(@intFromEnum(rg.State.disabled));
    }
    if (rg.button(rl.Rectangle.init(buttonX, buttonStartY + buttonSpacing, buttonWidth, buttonHeight), locale.tr("      Tulip (15 Honey)", "      Tulipa (15 Mel)")) and canAffordTulip) {
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
    const canAffordDandelion = ctx.resources.honey >= dandelionCost;
    if (!canAffordDandelion) {
        rg.setState(@intFromEnum(rg.State.disabled));
    }
    if (rg.button(rl.Rectangle.init(buttonX, buttonStartY + buttonSpacing * 2, buttonWidth, buttonHeight), locale.tr("      Dandelion (5 Honey)", "      Dente-de-leão (5 Mel)")) and canAffordDandelion) {
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
    if (rg.button(rl.Rectangle.init(buttonX, buttonStartY + buttonSpacing * 3, buttonWidth, buttonHeight), locale.tr("Cancel", "Cancelar"))) {
        return .close;
    }

    return .none;
}
