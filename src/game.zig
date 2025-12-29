const rl = @import("raylib");
const std = @import("std");

const Grid = @import("grid.zig").Grid;
const Textures = @import("textures.zig").Textures;
const Flowers = @import("textures.zig").Flowers;
const assets = @import("assets.zig");

const Resources = @import("resources.zig").Resources;
const ui = @import("ui.zig");
const Metrics = @import("metrics.zig").Metrics;
const spawners = @import("spawners.zig");

const World = @import("ecs/world.zig").World;
const components = @import("ecs/components.zig");

const lifespan_system = @import("ecs/systems/lifespan_system.zig");
const flower_growth_system = @import("ecs/systems/flower_growth_system.zig");
const bee_ai_system = @import("ecs/systems/bee_ai_system.zig");
const scale_sync_system = @import("ecs/systems/scale_sync_system.zig");
const flower_spawning_system = @import("ecs/systems/flower_spawning_system.zig");
const render_system = @import("ecs/systems/render_system.zig");

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
    hud: ui.Hud,

    cameraOffset: rl.Vector2,
    isDragging: bool,
    lastMousePos: rl.Vector2,

    beehiveUpgradeCost: f32,
    cachedBeeCount: usize,
    cachedFlowerCount: usize,

    metrics: Metrics,

    // Tile popup state
    showTilePopup: bool,
    popupJustOpened: bool, // Prevents click-through on popup open frame
    selectedTileX: i32,
    selectedTileY: i32,
    clickStartPos: rl.Vector2,

    // Pause menu state
    showPauseMenu: bool,
    isPaused: bool,
    shouldExit: bool,

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !@This() {
        const rand = std.crypto.random;
        rl.setRandomSeed(rand.int(u32));

        const monitor = rl.getCurrentMonitor();
        const screenWidth = rl.getMonitorWidth(monitor);
        const screenHeight = rl.getMonitorHeight(monitor);

        rl.initWindow(screenWidth, screenHeight, "Buzzness Tycoon");
        rl.setExitKey(rl.KeyboardKey.null); // Disable default ESC closing the window
        rl.setWindowState(.{ .window_resizable = true });
        rl.toggleFullscreen();
        const windowIcon = try assets.loadImageFromMemory(assets.bee_png);
        rl.setWindowIcon(windowIcon);

        const width: f32 = @floatFromInt(rl.getScreenWidth());
        const height: f32 = @floatFromInt(rl.getScreenHeight());

        const textures = try Textures.init();
        const grid = try Grid.init(GRID_WIDTH, GRID_HEIGHT, width, height);

        var world = World.init(allocator);

        // Spawn beehive at center
        _ = try spawners.spawnBeehive(&world, &textures, GRID_WIDTH, GRID_HEIGHT);

        // Spawn initial flowers
        for (0..grid.width) |i| {
            for (0..grid.height) |j| {
                // Skip beehive center tile
                if (i == (GRID_WIDTH - 1) / 2 and j == (GRID_HEIGHT - 1) / 2) {
                    continue;
                }

                const shouldHaveFlower = rl.getRandomValue(1, 100) <= FLOWER_SPAWN_CHANCE;
                if (shouldHaveFlower) {
                    _ = try spawners.spawnRandomFlower(&world, &textures, @intCast(i), @intCast(j));
                }
            }
        }

        // Spawn initial bees
        for (0..10000) |_| {
            _ = try spawners.spawnBee(&world, &grid, &textures);
        }

        return .{
            .allocator = allocator,
            .windowIcon = windowIcon,

            .textures = textures,
            .grid = grid,
            .world = world,

            .resources = Resources.init(),
            .hud = ui.Hud.init(),
            .metrics = Metrics.init(),

            .cameraOffset = rl.Vector2.init(0, 0),
            .isDragging = false,
            .lastMousePos = rl.Vector2.init(0, 0),

            .beehiveUpgradeCost = 20.0,
            .cachedBeeCount = 0,
            .cachedFlowerCount = 0,

            .showTilePopup = false,
            .popupJustOpened = false,
            .selectedTileX = 0,
            .selectedTileY = 0,
            .clickStartPos = rl.Vector2.init(0, 0),

            .showPauseMenu = false,
            .isPaused = false,
            .shouldExit = false,

            .width = width,
            .height = height,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.grid.deinit();
        self.textures.deinit();
        self.hud.deinit();
        self.world.deinit();
        self.metrics.deinit();

        rl.closeWindow();
        rl.unloadImage(self.windowIcon);
    }

    pub fn run(self: *@This()) !void {
        while (!rl.windowShouldClose() and !self.shouldExit) {
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

            // Save old offset before updating viewport
            const oldOffset = self.grid.offset;
            self.grid.updateViewport(self.width, self.height);

            // Calculate how much the grid offset changed
            const offsetDelta = rl.Vector2{
                .x = self.grid.offset.x - oldOffset.x,
                .y = self.grid.offset.y - oldOffset.y,
            };

            // Update all bee positions by the offset delta so they stay relative to the grid
            var beeIter = self.world.iterateBees();
            while (beeIter.next()) |entity| {
                if (self.world.getPosition(entity)) |pos| {
                    pos.x += offsetDelta.x;
                    pos.y += offsetDelta.y;
                }
            }
        }

        // Handle Escape key - close popups first, then show/hide pause menu
        if (rl.isKeyPressed(rl.KeyboardKey.escape)) {
            if (self.showTilePopup) {
                self.showTilePopup = false;
                return;
            } else if (self.showPauseMenu) {
                self.showPauseMenu = false;
                self.isPaused = false;
                return;
            } else {
                self.showPauseMenu = true;
                self.isPaused = true;
                return;
            }
        }

        // Block input when popup or pause menu is open
        if (self.showTilePopup or self.showPauseMenu) {
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
                    self.showTilePopup = true;
                    self.popupJustOpened = true; // Prevent click-through
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
        // Skip game updates when paused
        if (self.isPaused) {
            return;
        }

        const deltaTime = rl.getFrameTime();

        try lifespan_system.update(&self.world, deltaTime);
        try flower_growth_system.update(&self.world, deltaTime);
        try bee_ai_system.update(&self.world, deltaTime, self.grid.offset, self.grid.scale, GRID_WIDTH, GRID_HEIGHT, self.textures);
        try flower_spawning_system.update(&self.world, deltaTime, self.grid.offset, self.grid.scale, GRID_WIDTH, GRID_HEIGHT, self.textures);
        scale_sync_system.update(&self.world, self.grid.scale);

        // Get beehive honey conversion factor
        const honeyFactor = self.getBeehiveHoneyFactor();

        // Get counts directly from HashMap sizes - O(1) instead of O(n) iteration
        self.cachedBeeCount = self.world.entityToBeeAI.count();
        self.cachedFlowerCount = self.world.entityToFlowerGrowth.count();

        // Convert pollen to honey - iterate only pollenCollectors
        // This is necessary for honey conversion but we've reduced per-entity work
        var iter = self.world.entityToPollenCollector.iterator();
        while (iter.next()) |entry| {
            const entity = entry.key_ptr.*;
            const index = entry.value_ptr.*;
            const collector = &self.world.pollenCollectors.items[index];

            if (collector.pollenCollected > 0) {
                // Check if bee is not carrying pollen (has deposited)
                if (self.world.getBeeAI(entity)) |beeAI| {
                    if (!beeAI.carryingPollen) {
                        const newHoney = collector.pollenCollected * honeyFactor;
                        self.resources.addHoney(newHoney);
                        collector.pollenCollected = 0;
                    }
                }
            }
        }

        try self.world.processDestroyQueue();
    }

    pub fn draw(self: *@This()) !void {
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.init(0x1e, 0x1e, 0x2e, 0xff));

        self.grid.draw();

        try render_system.draw(&self.world, self.grid.offset, self.grid.scale);

        // Draw HUD
        const honeyFactor = self.getBeehiveHoneyFactor();
        self.hud.draw(self.resources.honey, self.cachedBeeCount, honeyFactor);

        rl.drawFPS(@as(i32, @intFromFloat(self.width - 100)), 10);

        // Draw frame time
        const frameTime = rl.getFrameTime() * 1000.0;
        rl.drawText(rl.textFormat("%.2f ms", .{frameTime}), @as(i32, @intFromFloat(self.width - 100)), 30, 20, rl.Color.white);

        // Draw tile popup
        if (self.showTilePopup) {
            // Skip processing actions on the frame the popup was opened
            // to prevent click-through
            if (self.popupJustOpened) {
                self.popupJustOpened = false;
                // Still draw the popup, just don't process actions
                const ctx = ui.TilePopupContext{
                    .screenWidth = self.width,
                    .screenHeight = self.height,
                    .tileX = self.selectedTileX,
                    .tileY = self.selectedTileY,
                    .gridWidth = GRID_WIDTH,
                    .gridHeight = GRID_HEIGHT,
                    .honey = self.resources.honey,
                    .beeCount = self.cachedBeeCount,
                    .beehiveUpgradeCost = self.beehiveUpgradeCost,
                    .textures = &self.textures,
                    .world = &self.world,
                };
                _ = ui.popups.draw(ctx);
            } else {
                try self.handleTilePopup();
            }
        }

        // Draw pause menu
        if (self.showPauseMenu) {
            const action = ui.pause_menu.draw(self.width, self.height);
            switch (action) {
                .continue_game => {
                    self.showPauseMenu = false;
                    self.isPaused = false;
                },
                .exit_game => {
                    self.shouldExit = true;
                },
                .none => {},
            }
        }

        // Log metrics
        const fps: f32 = @floatFromInt(rl.getFPS());
        self.metrics.log(fps, frameTime, self.cachedBeeCount, self.cachedFlowerCount);
    }

    fn handleTilePopup(self: *@This()) !void {
        const ctx = ui.TilePopupContext{
            .screenWidth = self.width,
            .screenHeight = self.height,
            .tileX = self.selectedTileX,
            .tileY = self.selectedTileY,
            .gridWidth = GRID_WIDTH,
            .gridHeight = GRID_HEIGHT,
            .honey = self.resources.honey,
            .beeCount = self.cachedBeeCount,
            .beehiveUpgradeCost = self.beehiveUpgradeCost,
            .textures = &self.textures,
            .world = &self.world,
        };

        const action = ui.popups.draw(ctx);

        switch (action) {
            .close => {
                self.showTilePopup = false;
            },
            .buy_bee => {
                if (self.resources.spendHoney(spawners.BEE_COST)) {
                    _ = try spawners.spawnBee(&self.world, &self.grid, &self.textures);
                    self.cachedBeeCount += 1;
                }
            },
            .upgrade_beehive => {
                if (self.resources.spendHoney(self.beehiveUpgradeCost)) {
                    var beehiveIter = self.world.entityToBeehive.keyIterator();
                    if (beehiveIter.next()) |beehiveEntity| {
                        if (self.world.getBeehive(beehiveEntity.*)) |beehive| {
                            beehive.honeyConversionFactor *= 2.0;
                            self.beehiveUpgradeCost *= 2.0;
                        }
                    }
                }
            },
            .upgrade_flower => {
                if (self.world.getFlowerAtGrid(self.selectedTileX, self.selectedTileY)) |flowerEntity| {
                    if (self.world.getFlowerGrowth(flowerEntity)) |growth| {
                        const upgradeCost = 20.0 * growth.pollenMultiplier;
                        if (self.resources.spendHoney(upgradeCost)) {
                            growth.pollenMultiplier += 0.5;
                        }
                    }
                }
            },
            .plant_rose => {
                if (self.resources.spendHoney(spawners.FLOWER_COSTS.rose)) {
                    _ = try spawners.spawnFlower(&self.world, &self.textures, .rose, self.selectedTileX, self.selectedTileY);
                    self.cachedFlowerCount += 1;
                    self.showTilePopup = false;
                }
            },
            .plant_tulip => {
                if (self.resources.spendHoney(spawners.FLOWER_COSTS.tulip)) {
                    _ = try spawners.spawnFlower(&self.world, &self.textures, .tulip, self.selectedTileX, self.selectedTileY);
                    self.cachedFlowerCount += 1;
                    self.showTilePopup = false;
                }
            },
            .plant_dandelion => {
                if (self.resources.spendHoney(spawners.FLOWER_COSTS.dandelion)) {
                    _ = try spawners.spawnFlower(&self.world, &self.textures, .dandelion, self.selectedTileX, self.selectedTileY);
                    self.cachedFlowerCount += 1;
                    self.showTilePopup = false;
                }
            },
            .none => {},
        }
    }

    fn getBeehiveHoneyFactor(self: *@This()) f32 {
        var beehiveIter = self.world.entityToBeehive.keyIterator();
        if (beehiveIter.next()) |beehiveEntity| {
            if (self.world.getBeehive(beehiveEntity.*)) |beehive| {
                return beehive.honeyConversionFactor;
            }
        }
        return 1.0;
    }
};
