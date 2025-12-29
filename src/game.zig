const rl = @import("raylib");
const rg = @import("raygui");
const std = @import("std");

const Grid = @import("grid.zig").Grid;
const Textures = @import("textures.zig").Textures;
const Flowers = @import("textures.zig").Flowers;
const assets = @import("assets.zig");
const utils = @import("utils.zig");

const Resources = @import("resources.zig").Resources;
const UI = @import("ui.zig").UI;
const Metrics = @import("metrics.zig").Metrics;

const World = @import("ecs/world.zig").World;
const Entity = @import("ecs/entity.zig").Entity;
const components = @import("ecs/components.zig");
const FlowerType = components.FlowerType;

const lifespan_system = @import("ecs/systems/lifespan_system.zig");
const flower_growth_system = @import("ecs/systems/flower_growth_system.zig");
const bee_ai_system = @import("ecs/systems/bee_ai_system.zig");
const scale_sync_system = @import("ecs/systems/scale_sync_system.zig");
const flower_spawning_system = @import("ecs/systems/flower_spawning_system.zig");
const render_system = @import("ecs/systems/render_system.zig");

// Helper to convert texture Flowers enum to component FlowerType
fn flowersToFlowerType(flower: Flowers) FlowerType {
    return switch (flower) {
        .rose => .rose,
        .tulip => .tulip,
        .dandelion => .dandelion,
    };
}

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

pub const Game = struct {
    const GRID_WIDTH = 17;
    const GRID_HEIGHT = 17;
    const FLOWER_SPAWN_CHANCE = 30;

    width: f32,
    height: f32,

    windowIcon: rl.Image,

    textures: Textures,
    grid: Grid,

    world: World,

    resources: Resources,
    ui: UI,

    cameraOffset: rl.Vector2,
    isDragging: bool,
    lastMousePos: rl.Vector2,

    beehiveUpgradeCost: f32,
    cachedBeeCount: usize,
    cachedFlowerCount: usize,

    metrics: Metrics,

    // Flower planting popup state
    showPlantPopup: bool,
    selectedTileX: i32,
    selectedTileY: i32,
    clickStartPos: rl.Vector2,

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !@This() {
        const rand = std.crypto.random;
        rl.setRandomSeed(rand.int(u32));

        const monitor = rl.getCurrentMonitor();
        const screenWidth = rl.getMonitorWidth(monitor);
        const screenHeight = rl.getMonitorHeight(monitor);

        rl.initWindow(screenWidth, screenHeight, "Buzzness Tycoon");
        rl.toggleFullscreen();
        const windowIcon = try assets.loadImageFromMemory(assets.bee_png);
        rl.setWindowIcon(windowIcon);

        const width: f32 = @floatFromInt(rl.getScreenWidth());
        const height: f32 = @floatFromInt(rl.getScreenHeight());

        const textures = try Textures.init();
        const grid = try Grid.init(GRID_WIDTH, GRID_HEIGHT, width, height);

        var world = World.init(allocator);

        const centerX: f32 = @floatFromInt((GRID_WIDTH - 1) / 2);
        const centerY: f32 = @floatFromInt((GRID_HEIGHT - 1) / 2);

        const beehiveEntity = try world.createEntity();
        try world.addGridPosition(beehiveEntity, components.GridPosition.init(centerX, centerY));
        try world.addSprite(beehiveEntity, components.Sprite.init(textures.beehive, 32, 32, 2));
        try world.addBeehive(beehiveEntity, components.Beehive.init());

        for (0..grid.width) |i| {
            for (0..grid.height) |j| {
                // Skip beehive center tile
                if (i == (GRID_WIDTH - 1) / 2 and j == (GRID_HEIGHT - 1) / 2) {
                    continue;
                }

                const shouldHaveFlower = rl.getRandomValue(1, 100) <= FLOWER_SPAWN_CHANCE;
                if (shouldHaveFlower) {
                    const x = rl.getRandomValue(1, 3);
                    var flowerType: Flowers = undefined;
                    if (x == 1) {
                        flowerType = Flowers.rose;
                    }
                    if (x == 2) {
                        flowerType = Flowers.dandelion;
                    }
                    if (x == 3) {
                        flowerType = Flowers.tulip;
                    }

                    const flowerTexture = textures.getFlowerTexture(flowerType);
                    const gridI: f32 = @as(f32, @floatFromInt(i));
                    const gridJ: f32 = @as(f32, @floatFromInt(j));

                    const flowerEntity = try world.createEntity();
                    try world.addGridPosition(flowerEntity, components.GridPosition.init(gridI, gridJ));
                    try world.addSprite(flowerEntity, components.Sprite.init(flowerTexture, 32, 32, 2));
                    try world.addFlowerGrowth(flowerEntity, components.FlowerGrowth.init(flowersToFlowerType(flowerType)));
                    try world.addLifespan(flowerEntity, components.Lifespan.init(@floatFromInt(rl.getRandomValue(60, 120))));

                    // Register flower in spatial lookup
                    world.registerFlowerAtGrid(@intCast(i), @intCast(j), flowerEntity);
                }
            }
        }

        for (0..100) |_| {
            const randomPos = grid.getRandomPositionInBounds();

            const beeEntity = try world.createEntity();
            try world.addPosition(beeEntity, components.Position.init(randomPos.x, randomPos.y));
            try world.addSprite(beeEntity, components.Sprite.init(textures.bee, 32, 32, 1));
            try world.addBeeAI(beeEntity, components.BeeAI.init());
            try world.addLifespan(beeEntity, components.Lifespan.init(@floatFromInt(rl.getRandomValue(60, 140))));
            try world.addPollenCollector(beeEntity, components.PollenCollector.init());
            try world.addScaleSync(beeEntity, components.ScaleSync.init(1));

            if (world.getScaleSync(beeEntity)) |scaleSync| {
                scaleSync.updateFromGrid(1, grid.scale);
            }
        }

        return .{
            .allocator = allocator,
            .windowIcon = windowIcon,

            .textures = textures,
            .grid = grid,
            .world = world,

            .resources = Resources.init(),
            .ui = UI.init(),
            .metrics = Metrics.init(),

            .cameraOffset = rl.Vector2.init(0, 0),
            .isDragging = false,
            .lastMousePos = rl.Vector2.init(0, 0),

            .beehiveUpgradeCost = 20.0,
            .cachedBeeCount = 0,
            .cachedFlowerCount = 0,

            .showPlantPopup = false,
            .selectedTileX = 0,
            .selectedTileY = 0,
            .clickStartPos = rl.Vector2.init(0, 0),

            .width = width,
            .height = height,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.grid.deinit();
        self.textures.deinit();
        self.ui.deinit();
        self.world.deinit();
        self.metrics.deinit();

        rl.closeWindow();
        rl.unloadImage(self.windowIcon);

        self.resources.deinit();
    }

    pub fn run(self: *@This()) !void {
        while (!rl.windowShouldClose()) {
            self.input();
            try self.update();
            try self.draw();
        }
    }

    pub fn input(self: *@This()) void {
        // Alt+Enter to toggle fullscreen
        if (rl.isKeyPressed(rl.KeyboardKey.enter) and rl.isKeyDown(rl.KeyboardKey.left_alt)) {
            const wasFullscreen = rl.isWindowFullscreen();
            rl.toggleFullscreen();

            // When exiting fullscreen, resize window to 1280x720 and center it
            if (wasFullscreen) {
                rl.setWindowSize(1280, 720);
                const monitor = rl.getCurrentMonitor();
                const monitorWidth = rl.getMonitorWidth(monitor);
                const monitorHeight = rl.getMonitorHeight(monitor);
                rl.setWindowPosition(@divFloor(monitorWidth - 1280, 2), @divFloor(monitorHeight - 720, 2));
            }
        }

        // Update viewport if window size changed
        const currentWidth: f32 = @floatFromInt(rl.getScreenWidth());
        const currentHeight: f32 = @floatFromInt(rl.getScreenHeight());
        if (currentWidth != self.width or currentHeight != self.height) {
            self.width = currentWidth;
            self.height = currentHeight;
            self.grid.updateViewport(self.width, self.height);
        }

        // Close popup with Escape
        if (self.showPlantPopup and rl.isKeyPressed(rl.KeyboardKey.escape)) {
            self.showPlantPopup = false;
            return;
        }

        // Block input when popup is open
        if (self.showPlantPopup) {
            return;
        }

        const mousePos = rl.getMousePosition();

        if (rl.isMouseButtonPressed(rl.MouseButton.left)) {
            self.isDragging = true;
            self.lastMousePos = mousePos;
            self.clickStartPos = mousePos;
        }

        if (rl.isMouseButtonReleased(rl.MouseButton.left)) {
            // Check if this was a click (not a drag) - mouse didn't move much
            const dragDistance = @sqrt((mousePos.x - self.clickStartPos.x) * (mousePos.x - self.clickStartPos.x) + (mousePos.y - self.clickStartPos.y) * (mousePos.y - self.clickStartPos.y));

            if (dragDistance < 5.0) {
                // This is a click - check if we clicked on a tile
                if (self.grid.getHoveredTile()) |tile| {
                    self.selectedTileX = tile.x;
                    self.selectedTileY = tile.y;
                    self.showPlantPopup = true;
                }
            }

            self.isDragging = false;
        }

        if (self.isDragging) {
            const mouseDelta = rl.Vector2.init(mousePos.x - self.lastMousePos.x, mousePos.y - self.lastMousePos.y);

            self.cameraOffset.x += mouseDelta.x;
            self.cameraOffset.y += mouseDelta.y;

            self.grid.offset.x += mouseDelta.x;
            self.grid.offset.y += mouseDelta.y;

            self.lastMousePos = mousePos;
        }

        const wheelMove = rl.getMouseWheelMove();
        if (wheelMove != 0.0) {
            const zoomSpeed = 0.3;
            const zoomDelta = wheelMove * zoomSpeed;
            self.grid.zoom(zoomDelta);
        }
    }

    pub fn update(self: *@This()) !void {
        const deltaTime = rl.getFrameTime();

        try lifespan_system.update(&self.world, deltaTime);
        try flower_growth_system.update(&self.world, deltaTime);
        try bee_ai_system.update(&self.world, deltaTime, self.grid.offset, self.grid.scale, GRID_WIDTH, GRID_HEIGHT, self.textures);
        try flower_spawning_system.update(&self.world, deltaTime, self.grid.offset, self.grid.scale, GRID_WIDTH, GRID_HEIGHT, self.textures);
        scale_sync_system.update(&self.world, self.grid.scale);

        // Get beehive honey conversion factor
        var honeyFactor: f32 = 1.0;
        var beehiveIter = self.world.entityToBeehive.keyIterator();
        if (beehiveIter.next()) |beehiveEntity| {
            if (self.world.getBeehive(beehiveEntity.*)) |beehive| {
                honeyFactor = beehive.honeyConversionFactor;
            }
        }

        // Count bees and convert honey in single pass
        self.cachedBeeCount = 0;
        var beeIter = self.world.iterateBees();
        while (beeIter.next()) |entity| {
            self.cachedBeeCount += 1;

            if (self.world.getPollenCollector(entity)) |collector| {
                if (self.world.getBeeAI(entity)) |beeAI| {
                    // Convert pollen to honey when bee has deposited (not carrying anymore)
                    if (!beeAI.carryingPollen and collector.pollenCollected > 0) {
                        const newHoney = collector.pollenCollected * honeyFactor;
                        self.resources.addHoney(newHoney);
                        collector.pollenCollected = 0;
                    }
                }
            }
        }

        // Count flowers
        self.cachedFlowerCount = 0;
        var flowerIter = self.world.iterateFlowers();
        while (flowerIter.next()) |_| {
            self.cachedFlowerCount += 1;
        }

        try self.world.processDestroyQueue();
    }

    pub fn draw(self: *@This()) !void {
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.init(0x1e, 0x1e, 0x2e, 0xff));

        self.grid.draw();

        try render_system.draw(&self.world, self.grid.offset, self.grid.scale);

        // Get beehive honey conversion factor for UI
        var honeyFactor: f32 = 1.0;
        var beehiveIterForUI = self.world.entityToBeehive.keyIterator();
        if (beehiveIterForUI.next()) |beehiveEntity| {
            if (self.world.getBeehive(beehiveEntity.*)) |beehive| {
                honeyFactor = beehive.honeyConversionFactor;
            }
        }

        const uiActions = self.ui.draw(self.resources.honey, self.cachedBeeCount, honeyFactor, self.beehiveUpgradeCost);

        // Handle buy bee button
        if (uiActions.buyBee) {
            if (self.resources.spendHoney(10.0)) {
                const randomPos = self.grid.getRandomPositionInBounds();

                const beeEntity = try self.world.createEntity();
                try self.world.addPosition(beeEntity, components.Position.init(randomPos.x, randomPos.y));
                try self.world.addSprite(beeEntity, components.Sprite.init(self.textures.bee, 32, 32, 1));
                try self.world.addBeeAI(beeEntity, components.BeeAI.init());
                try self.world.addLifespan(beeEntity, components.Lifespan.init(@floatFromInt(rl.getRandomValue(60, 140))));
                try self.world.addPollenCollector(beeEntity, components.PollenCollector.init());
                try self.world.addScaleSync(beeEntity, components.ScaleSync.init(1));

                if (self.world.getScaleSync(beeEntity)) |scaleSync| {
                    scaleSync.updateFromGrid(1, self.grid.scale);
                }

                self.cachedBeeCount += 1; // Update cache
            }
        }

        // Handle upgrade beehive button
        if (uiActions.upgradeBeehive) {
            if (self.resources.spendHoney(self.beehiveUpgradeCost)) {
                var beehiveIter2 = self.world.entityToBeehive.keyIterator();
                if (beehiveIter2.next()) |beehiveEntity| {
                    if (self.world.getBeehive(beehiveEntity.*)) |beehive| {
                        beehive.honeyConversionFactor *= 2.0;
                        self.beehiveUpgradeCost *= 2.0;
                    }
                }
            }
        }

        rl.drawFPS(@as(i32, @intFromFloat(self.width - 100)), 10);

        // Draw frame time
        const frameTime = rl.getFrameTime() * 1000.0; // Convert to milliseconds
        rl.drawText(rl.textFormat("%.2f ms", .{frameTime}), @as(i32, @intFromFloat(self.width - 100)), 30, 20, rl.Color.white);

        // Draw flower planting popup
        if (self.showPlantPopup) {
            try self.drawPlantPopup();
        }

        // Log metrics
        const fps: f32 = @floatFromInt(rl.getFPS());
        self.metrics.log(fps, frameTime, self.cachedBeeCount, self.cachedFlowerCount);
    }

    fn drawPlantPopup(self: *@This()) !void {
        // Draw semi-transparent overlay
        rl.drawRectangle(0, 0, @intFromFloat(self.width), @intFromFloat(self.height), rl.Color.init(0, 0, 0, 150));

        // Popup dimensions
        const popupWidth: f32 = 300;
        const popupHeight: f32 = 280;
        const popupX: f32 = (self.width - popupWidth) / 2;
        const popupY: f32 = (self.height - popupHeight) / 2;

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

        // Check tile state
        const centerTileX = @as(i32, @intCast((GRID_WIDTH - 1) / 2));
        const centerTileY = @as(i32, @intCast((GRID_HEIGHT - 1) / 2));
        const isBeehiveTile = (self.selectedTileX == centerTileX and self.selectedTileY == centerTileY);
        const flowerEntity = self.world.getFlowerAtGrid(self.selectedTileX, self.selectedTileY);
        const hasFlower = flowerEntity != null;

        // Icon settings - show fully grown flower (state 4, frame at x=128)
        const frameSize: f32 = 32; // Each frame is 32x32
        const fullyGrownFrame: f32 = 4; // State 4 = fully grown
        const iconSize: f32 = 32;
        const iconPadding: f32 = 8;
        const sourceRect = rl.Rectangle.init(fullyGrownFrame * frameSize, 0, frameSize, frameSize);

        const buttonWidth: f32 = 250;
        const buttonHeight: f32 = 40;
        const buttonX = popupX + (popupWidth - buttonWidth) / 2;

        if (isBeehiveTile) {
            // Beehive tile - just show message and close button
            const titleText = "Beehive Tile";
            const titleX = @as(i32, @intFromFloat(popupX + popupWidth / 2)) - @divFloor(rl.measureText(titleText, 24), 2);
            rl.drawText(titleText, titleX, @as(i32, @intFromFloat(popupY + 15)), 24, rl.Color.init(0xcd, 0xd6, 0xf4, 0xff));

            const tileInfoText = rl.textFormat("Tile: (%d, %d)", .{ self.selectedTileX, self.selectedTileY });
            const tileInfoX = @as(i32, @intFromFloat(popupX + popupWidth / 2)) - @divFloor(rl.measureText(tileInfoText, 16), 2);
            rl.drawText(tileInfoText, tileInfoX, @as(i32, @intFromFloat(popupY + 45)), 16, rl.Color.init(0xa6, 0xad, 0xc8, 0xff));

            const msgText = "Cannot plant here!";
            const msgX = @as(i32, @intFromFloat(popupX + popupWidth / 2)) - @divFloor(rl.measureText(msgText, 18), 2);
            rl.drawText(msgText, msgX, @as(i32, @intFromFloat(popupY + 100)), 18, rl.Color.init(0xf3, 0x8b, 0xa8, 0xff)); // red

            if (rg.button(rl.Rectangle.init(buttonX, popupY + 200, buttonWidth, buttonHeight), "Close")) {
                self.showPlantPopup = false;
            }
        } else if (hasFlower) {
            // Show flower info and upgrade option
            if (self.world.getFlowerGrowth(flowerEntity.?)) |growth| {
                const flowerName = getFlowerName(growth.flowerType);
                const titleX = @as(i32, @intFromFloat(popupX + popupWidth / 2)) - @divFloor(rl.measureText(flowerName, 24), 2);
                rl.drawText(flowerName, titleX, @as(i32, @intFromFloat(popupY + 15)), 24, rl.Color.init(0xcd, 0xd6, 0xf4, 0xff));

                // Draw large flower icon
                const largeIconSize: f32 = 64;
                const largeIconX = popupX + (popupWidth - largeIconSize) / 2;
                const largeIconY = popupY + 50;
                const largeDest = rl.Rectangle.init(largeIconX, largeIconY, largeIconSize, largeIconSize);
                const flowerTexture = self.textures.getFlowerTexture(flowerTypeToFlowers(growth.flowerType));
                rl.drawTexturePro(flowerTexture, sourceRect, largeDest, rl.Vector2.init(0, 0), 0, rl.Color.white);

                // Show current multiplier
                const multiplierText = rl.textFormat("Pollen Multiplier: %.1fx", .{growth.pollenMultiplier});
                const multiplierX = @as(i32, @intFromFloat(popupX + popupWidth / 2)) - @divFloor(rl.measureText(multiplierText, 18), 2);
                rl.drawText(multiplierText, multiplierX, @as(i32, @intFromFloat(popupY + 125)), 18, rl.Color.init(0xf9, 0xe2, 0xaf, 0xff)); // yellow

                // Upgrade button
                const upgradeCost = 20.0 * growth.pollenMultiplier; // Cost increases with level
                const canAffordUpgrade = self.resources.honey >= upgradeCost;
                const buttonStartY = popupY + 160;

                if (!canAffordUpgrade) {
                    rg.setState(@intFromEnum(rg.State.disabled));
                }
                const upgradeText = rl.textFormat("Upgrade to %.1fx (%.0f Honey)", .{ growth.pollenMultiplier + 0.5, upgradeCost });
                if (rg.button(rl.Rectangle.init(buttonX, buttonStartY, buttonWidth, buttonHeight), upgradeText) and canAffordUpgrade) {
                    if (self.resources.spendHoney(upgradeCost)) {
                        growth.pollenMultiplier += 0.5;
                    }
                }
                rg.setState(@intFromEnum(rg.State.normal));

                // Close button
                if (rg.button(rl.Rectangle.init(buttonX, buttonStartY + 50, buttonWidth, buttonHeight), "Close")) {
                    self.showPlantPopup = false;
                }
            }
        } else {
            // Empty tile - show planting options
            const titleText = "Plant a Flower";
            const titleX = @as(i32, @intFromFloat(popupX + popupWidth / 2)) - @divFloor(rl.measureText(titleText, 24), 2);
            rl.drawText(titleText, titleX, @as(i32, @intFromFloat(popupY + 15)), 24, rl.Color.init(0xcd, 0xd6, 0xf4, 0xff));

            const tileInfoText = rl.textFormat("Tile: (%d, %d)", .{ self.selectedTileX, self.selectedTileY });
            const tileInfoX = @as(i32, @intFromFloat(popupX + popupWidth / 2)) - @divFloor(rl.measureText(tileInfoText, 16), 2);
            rl.drawText(tileInfoText, tileInfoX, @as(i32, @intFromFloat(popupY + 45)), 16, rl.Color.init(0xa6, 0xad, 0xc8, 0xff));

            const buttonStartY = popupY + 80;
            const buttonSpacing: f32 = 50;

            // Rose button (10 honey)
            const roseCost: f32 = 10.0;
            const canAffordRose = self.resources.honey >= roseCost;
            if (!canAffordRose) {
                rg.setState(@intFromEnum(rg.State.disabled));
            }
            if (rg.button(rl.Rectangle.init(buttonX, buttonStartY, buttonWidth, buttonHeight), "      Rose (10 Honey)") and canAffordRose) {
                try self.plantFlower(Flowers.rose, roseCost);
            }
            rg.setState(@intFromEnum(rg.State.normal));
            // Draw rose icon
            const roseIconX = buttonX + iconPadding;
            const roseIconY = buttonStartY + (buttonHeight - iconSize) / 2;
            const roseDest = rl.Rectangle.init(roseIconX, roseIconY, iconSize, iconSize);
            rl.drawTexturePro(self.textures.rose, sourceRect, roseDest, rl.Vector2.init(0, 0), 0, rl.Color.white);

            // Tulip button (15 honey)
            const tulipCost: f32 = 15.0;
            const canAffordTulip = self.resources.honey >= tulipCost;
            if (!canAffordTulip) {
                rg.setState(@intFromEnum(rg.State.disabled));
            }
            if (rg.button(rl.Rectangle.init(buttonX, buttonStartY + buttonSpacing, buttonWidth, buttonHeight), "      Tulip (15 Honey)") and canAffordTulip) {
                try self.plantFlower(Flowers.tulip, tulipCost);
            }
            rg.setState(@intFromEnum(rg.State.normal));
            // Draw tulip icon
            const tulipIconX = buttonX + iconPadding;
            const tulipIconY = buttonStartY + buttonSpacing + (buttonHeight - iconSize) / 2;
            const tulipDest = rl.Rectangle.init(tulipIconX, tulipIconY, iconSize, iconSize);
            rl.drawTexturePro(self.textures.tulip, sourceRect, tulipDest, rl.Vector2.init(0, 0), 0, rl.Color.white);

            // Dandelion button (5 honey)
            const dandelionCost: f32 = 5.0;
            const canAffordDandelion = self.resources.honey >= dandelionCost;
            if (!canAffordDandelion) {
                rg.setState(@intFromEnum(rg.State.disabled));
            }
            if (rg.button(rl.Rectangle.init(buttonX, buttonStartY + buttonSpacing * 2, buttonWidth, buttonHeight), "      Dandelion (5 Honey)") and canAffordDandelion) {
                try self.plantFlower(Flowers.dandelion, dandelionCost);
            }
            rg.setState(@intFromEnum(rg.State.normal));
            // Draw dandelion icon
            const dandelionIconX = buttonX + iconPadding;
            const dandelionIconY = buttonStartY + buttonSpacing * 2 + (buttonHeight - iconSize) / 2;
            const dandelionDest = rl.Rectangle.init(dandelionIconX, dandelionIconY, iconSize, iconSize);
            rl.drawTexturePro(self.textures.dandelion, sourceRect, dandelionDest, rl.Vector2.init(0, 0), 0, rl.Color.white);

            // Cancel button
            if (rg.button(rl.Rectangle.init(buttonX, buttonStartY + buttonSpacing * 3, buttonWidth, buttonHeight), "Cancel")) {
                self.showPlantPopup = false;
            }
        }
    }

    fn plantFlower(self: *@This(), flowerType: Flowers, cost: f32) !void {
        if (!self.resources.spendHoney(cost)) {
            return;
        }

        const flowerTexture = self.textures.getFlowerTexture(flowerType);
        const gridX: f32 = @floatFromInt(self.selectedTileX);
        const gridY: f32 = @floatFromInt(self.selectedTileY);

        const flowerEntity = try self.world.createEntity();
        try self.world.addGridPosition(flowerEntity, components.GridPosition.init(gridX, gridY));
        try self.world.addSprite(flowerEntity, components.Sprite.init(flowerTexture, 32, 32, 2));
        try self.world.addFlowerGrowth(flowerEntity, components.FlowerGrowth.init(flowersToFlowerType(flowerType)));
        try self.world.addLifespan(flowerEntity, components.Lifespan.init(@floatFromInt(rl.getRandomValue(60, 120))));

        // Register flower in spatial lookup
        self.world.registerFlowerAtGrid(self.selectedTileX, self.selectedTileY, flowerEntity);

        self.cachedFlowerCount += 1;
        self.showPlantPopup = false;
    }
};
