const rl = @import("raylib");
const std = @import("std");

const Grid = @import("grid.zig").Grid;
const Textures = @import("textures.zig").Textures;
const Flowers = @import("textures.zig").Flowers;
const assets = @import("assets.zig");
const theme = @import("theme.zig");
const actions = @import("actions.zig");

const Resources = @import("resources.zig").Resources;
const ui = @import("ui.zig");
const Metrics = @import("metrics.zig").Metrics;
const spawners = @import("spawners.zig");
const floating_text = @import("floating_text.zig");
const upgrade_tree = @import("upgrade_tree.zig");
const labs = @import("labs.zig");
const prestige_mod = @import("prestige.zig");

const World = @import("ecs/world.zig").World;
const components = @import("ecs/components.zig");

const lifespan_system = @import("ecs/systems/lifespan_system.zig");
const flower_growth_system = @import("ecs/systems/flower_growth_system.zig");
const bee_ai_system = @import("ecs/systems/bee_ai_system.zig");
const scale_sync_system = @import("ecs/systems/scale_sync_system.zig");
const flower_spawning_system = @import("ecs/systems/flower_spawning_system.zig");
const render_system = @import("ecs/systems/render_system.zig");

pub const GameState = enum {
    title_screen,
    playing,
};

pub const Game = struct {
    const INITIAL_GRID_WIDTH = 17;
    const INITIAL_GRID_HEIGHT = 17;
    const FLOWER_SPAWN_CHANCE = 30;

    width: f32,
    height: f32,

    gridWidth: usize,
    gridHeight: usize,

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

    floatingTexts: floating_text.Manager,
    upgradeTree: upgrade_tree.State,
    showTree: bool,
    labs: labs.LabState,
    prestige: prestige_mod.PrestigeState,
    showPrestigeDialog: bool,

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

    // Game state
    state: GameState,

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
        const grid = try Grid.init(INITIAL_GRID_WIDTH, INITIAL_GRID_HEIGHT, width - ui.side_panel.PANEL_WIDTH, height);

        var world = World.init(allocator);

        // Spawn beehive at center
        _ = try spawners.spawnBeehive(&world, &textures, INITIAL_GRID_WIDTH, INITIAL_GRID_HEIGHT);

        // Spawn initial flowers
        for (0..grid.width) |i| {
            for (0..grid.height) |j| {
                // Skip beehive center tile
                if (i == (INITIAL_GRID_WIDTH - 1) / 2 and j == (INITIAL_GRID_HEIGHT - 1) / 2) {
                    continue;
                }

                const shouldHaveFlower = rl.getRandomValue(1, 100) <= FLOWER_SPAWN_CHANCE;
                if (shouldHaveFlower) {
                    _ = try spawners.spawnRandomFlower(&world, &textures, @intCast(i), @intCast(j));
                }
            }
        }

        // Spawn initial bees
        for (0..5) |_| {
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
            .floatingTexts = floating_text.Manager.init(allocator),
            .upgradeTree = upgrade_tree.State.init(allocator),
            .showTree = false,
            .labs = .{},
            .prestige = .{},
            .showPrestigeDialog = false,

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

            .state = .title_screen,

            .width = width,
            .height = height,
            .gridWidth = INITIAL_GRID_WIDTH,
            .gridHeight = INITIAL_GRID_HEIGHT,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.grid.deinit();
        self.textures.deinit();
        self.hud.deinit();
        self.world.deinit();
        self.metrics.deinit();
        self.floatingTexts.deinit();
        self.upgradeTree.deinit();
        ui.title_screen.deinit();

        rl.closeWindow();
        rl.unloadImage(self.windowIcon);
    }

    pub fn run(self: *@This()) !void {
        while (!rl.windowShouldClose() and !self.shouldExit) {
            self.handleCommonInput();
            switch (self.state) {
                .title_screen => self.drawTitleScreen(),
                .playing => {
                    self.handlePlayingInput();
                    try self.update();
                    try self.draw();
                },
            }
        }
    }

    /// Handle input common to all game states (fullscreen, window resize)
    fn handleCommonInput(self: *@This()) void {
        // Alt+Enter to toggle fullscreen
        if (rl.isKeyPressed(rl.KeyboardKey.enter) and rl.isKeyDown(rl.KeyboardKey.left_alt)) {
            const wasFullscreen = rl.isWindowFullscreen();
            rl.toggleFullscreen();
            if (wasFullscreen) {
                rl.setWindowSize(1280, 720);
                const monitor = rl.getCurrentMonitor();
                const monitorWidth = rl.getMonitorWidth(monitor);
                const monitorHeight = rl.getMonitorHeight(monitor);
                rl.setWindowPosition(@divFloor(monitorWidth - 1280, 2), @divFloor(monitorHeight - 720, 2));
            }
        }

        // Update dimensions if window size changed
        const currentWidth: f32 = @floatFromInt(rl.getScreenWidth());
        const currentHeight: f32 = @floatFromInt(rl.getScreenHeight());
        if (currentWidth != self.width or currentHeight != self.height) {
            self.width = currentWidth;
            self.height = currentHeight;
        }
    }

    fn drawTitleScreen(self: *@This()) void {
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(theme.CatppuccinMocha.Color.base);

        const action = ui.title_screen.draw(self.width, self.height);
        switch (action) {
            .play => self.state = .playing,
            .quit => self.shouldExit = true,
            .none => {},
        }
    }

    /// Handle input specific to playing state
    fn handlePlayingInput(self: *@This()) void {
        // Update grid viewport and bee positions when window resizes
        const currentWidth: f32 = @floatFromInt(rl.getScreenWidth());
        const currentHeight: f32 = @floatFromInt(rl.getScreenHeight());
        if (currentWidth != self.width or currentHeight != self.height) {
            const oldOffset = self.grid.offset;
            self.grid.updateViewport(currentWidth - ui.side_panel.PANEL_WIDTH, currentHeight);
            const offsetDelta = rl.Vector2{
                .x = self.grid.offset.x - oldOffset.x,
                .y = self.grid.offset.y - oldOffset.y,
            };
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
            if (self.showPrestigeDialog) {
                self.showPrestigeDialog = false;
                return;
            } else if (self.showTree) {
                self.showTree = false;
                return;
            } else if (self.showTilePopup) {
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

        // Block input when popup, pause menu, tree, or prestige dialog is open
        if (self.showTilePopup or self.showPauseMenu or self.showTree or self.showPrestigeDialog) {
            return;
        }

        // Lab hotkeys
        if (rl.isKeyPressed(rl.KeyboardKey.b)) {
            _ = self.labs.tryActivateBurst(self.upgradeTree.hasEffect(.lab_burst));
        }
        if (rl.isKeyPressed(rl.KeyboardKey.m)) {
            if (self.labs.tryActivateBloom(self.upgradeTree.hasEffect(.lab_bloom))) {
                self.triggerBloom();
            }
        }

        const mousePos = rl.getMousePosition();
        const mouseInPanel = ui.side_panel.isMouseInPanel(mousePos, self.width);

        if (rl.isMouseButtonPressed(rl.MouseButton.left) and !mouseInPanel) {
            self.isDragging = true;
            self.lastMousePos = mousePos;
            self.clickStartPos = mousePos;
        }

        if (rl.isMouseButtonReleased(rl.MouseButton.left)) {
            if (!mouseInPanel) {
                self.handleMouseClick(mousePos);
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
            self.grid.zoom(wheelMove * 0.3);
        }
    }

    fn handleMouseClick(self: *@This(), mousePos: rl.Vector2) void {
        const dragDistance = @sqrt((mousePos.x - self.clickStartPos.x) * (mousePos.x - self.clickStartPos.x) +
            (mousePos.y - self.clickStartPos.y) * (mousePos.y - self.clickStartPos.y));

        if (dragDistance >= 5.0) return;

        // Check if we clicked on a rebirth bubble
        var flowerIter = self.world.iterateFlowers();
        while (flowerIter.next()) |entity| {
            if (render_system.isFlowerDying(&self.world, entity)) {
                if (self.world.getGridPosition(entity)) |gridPos| {
                    const bubble = render_system.getBubbleHitArea(gridPos.x, gridPos.y, self.grid.offset, self.grid.scale);
                    const dx = mousePos.x - bubble.x;
                    const dy = mousePos.y - bubble.y;
                    if (dx * dx + dy * dy <= bubble.radius * bubble.radius) {
                        self.rebirthFlower(entity);
                        return;
                    }
                }
            }
        }

        // Check if we clicked on a tile
        if (self.grid.getHoveredTile()) |tile| {
            // Beehive tile: side panel handles all hive actions, skip popup
            const centerX = @as(i32, @intCast((self.gridWidth - 1) / 2));
            const centerY = @as(i32, @intCast((self.gridHeight - 1) / 2));
            if (tile.x == centerX and tile.y == centerY) return;

            if (self.world.getFlowerAtGrid(tile.x, tile.y)) |flowerEntity| {
                if (!render_system.isFlowerDying(&self.world, flowerEntity)) {
                    if (self.resources.canUseGrowthBoost()) {
                        self.boostFlowerGrowth(flowerEntity);
                        return;
                    }
                }
            }
            self.selectedTileX = tile.x;
            self.selectedTileY = tile.y;
            self.showTilePopup = true;
            self.popupJustOpened = true;
        }
    }

    pub fn update(self: *@This()) !void {
        // Skip game updates when paused
        if (self.isPaused) {
            return;
        }

        const deltaTime = rl.getFrameTime();

        // Update growth boost cooldown
        self.resources.updateCooldown(deltaTime);
        self.resources.tickRate(deltaTime);
        self.labs.update(deltaTime);

        try lifespan_system.update(&self.world, deltaTime);
        try flower_growth_system.update(&self.world, deltaTime);
        try bee_ai_system.update(&self.world, deltaTime, self.grid.offset, self.grid.scale, self.gridWidth, self.gridHeight, self.textures);
        try flower_spawning_system.update(&self.world, deltaTime, self.grid.offset, self.grid.scale, self.gridWidth, self.gridHeight, self.textures);
        scale_sync_system.update(&self.world, self.grid.scale);

        // Get beehive honey conversion factor
        const honeyFactor = self.getBeehiveHoneyFactor();

        // Get counts directly from HashMap sizes - O(1) instead of O(n) iteration
        self.cachedBeeCount = self.world.entityToBeeAI.count();
        self.cachedFlowerCount = self.world.entityToFlowerGrowth.count();

        // Convert pollen to honey - iterate only pollenCollectors
        // This is necessary for honey conversion but we've reduced per-entity work
        var frameHoneyGain: f32 = 0;
        var iter = self.world.entityToPollenCollector.iterator();
        while (iter.next()) |entry| {
            const entity = entry.key_ptr.*;
            const index = entry.value_ptr.*;
            const collector = &self.world.pollenCollectors.items[index];

            if (collector.pollenCollected > 0) {
                // Check if bee is not carrying pollen (has deposited)
                if (self.world.getBeeAI(entity)) |beeAI| {
                    if (!beeAI.carryingPollen) {
                        const newHoney = collector.pollenCollected * honeyFactor * self.labs.honeyMultiplier() * self.prestige.globalMul();
                        self.resources.addHoney(newHoney);
                        frameHoneyGain += newHoney;
                        self.prestige.trackHoney(newHoney);
                        collector.pollenCollected = 0;
                    }
                }
            }
        }

        if (frameHoneyGain > 0) {
            const centerX: f32 = @floatFromInt((self.gridWidth - 1) / 2);
            const centerY: f32 = @floatFromInt((self.gridHeight - 1) / 2);
            try self.floatingTexts.spawn(centerX, centerY, frameHoneyGain);
        }
        self.floatingTexts.update(deltaTime);

        try self.world.processDestroyQueue();
    }

    pub fn draw(self: *@This()) !void {
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(theme.CatppuccinMocha.Color.base);

        self.grid.draw();

        try render_system.draw(&self.world, self.grid.offset, self.grid.scale);

        self.floatingTexts.draw(self.grid.offset, self.grid.scale);

        // Draw HUD
        const honeyFactor = self.getBeehiveHoneyFactor();
        self.hud.draw(&self.resources, self.cachedBeeCount, honeyFactor);

        self.drawLabsWidget();

        // Draw side panel (shop)
        const sideCtx = ui.SidePanelContext{
            .screenWidth = self.width,
            .screenHeight = self.height,
            .resources = &self.resources,
            .beeCount = self.cachedBeeCount,
            .beehiveFactor = honeyFactor,
            .treeState = &self.upgradeTree,
            .prestige = &self.prestige,
            .textures = &self.textures,
        };
        const sideAction = ui.side_panel.draw(sideCtx);
        if (!self.showTilePopup and !self.showPauseMenu and !self.showTree and !self.showPrestigeDialog) {
            switch (sideAction) {
                .none => {},
                .open_tree => self.showTree = true,
                .open_prestige => self.showPrestigeDialog = true,
                .buy => |act| {
                    var handler = self.createActionHandler();
                    const result = try handler.handlePopupAction(act, 0, 0);
                    if (result.beeCountDelta != 0) {
                        self.cachedBeeCount = @intCast(@as(i64, @intCast(self.cachedBeeCount)) + result.beeCountDelta);
                    }
                },
            }
        }

        if (self.showPrestigeDialog) {
            try self.drawAndHandlePrestigeDialog();
        }

        if (self.showTree) {
            const treeCtx = ui.TreeContext{
                .screenWidth = self.width,
                .screenHeight = self.height,
                .state = &self.upgradeTree,
                .resources = &self.resources,
            };
            const treeAction = ui.tree_view.draw(treeCtx);
            switch (treeAction) {
                .none => {},
                .close => self.showTree = false,
                .purchase => |nid| try self.purchaseUpgrade(nid),
            }
        }

        const fpsX = @as(i32, @intFromFloat(self.width - ui.side_panel.PANEL_WIDTH - 100));
        rl.drawFPS(fpsX, 10);

        // Draw frame time
        const frameTime = rl.getFrameTime() * 1000.0;
        rl.drawText(rl.textFormat("%.2f ms", .{frameTime}), fpsX, 30, 20, rl.Color.white);

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
                    .gridWidth = self.gridWidth,
                    .gridHeight = self.gridHeight,
                    .resources = &self.resources,
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

    fn createActionHandler(self: *@This()) actions.ActionHandler {
        return actions.ActionHandler{
            .world = &self.world,
            .resources = &self.resources,
            .grid = &self.grid,
            .textures = &self.textures,
            .beehiveUpgradeCost = &self.beehiveUpgradeCost,
        };
    }

    fn handleTilePopup(self: *@This()) !void {
        const ctx = ui.TilePopupContext{
            .screenWidth = self.width,
            .screenHeight = self.height,
            .tileX = self.selectedTileX,
            .tileY = self.selectedTileY,
            .gridWidth = self.gridWidth,
            .gridHeight = self.gridHeight,
            .resources = &self.resources,
            .beeCount = self.cachedBeeCount,
            .beehiveUpgradeCost = self.beehiveUpgradeCost,
            .textures = &self.textures,
            .world = &self.world,
        };

        const action = ui.popups.draw(ctx);
        var handler = self.createActionHandler();
        const result = try handler.handlePopupAction(action, self.selectedTileX, self.selectedTileY);

        if (result.closePopup) {
            self.showTilePopup = false;
        }
        if (result.beeCountDelta != 0) {
            self.cachedBeeCount = @intCast(@as(i64, @intCast(self.cachedBeeCount)) + result.beeCountDelta);
        }
        if (result.flowerCountDelta != 0) {
            self.cachedFlowerCount = @intCast(@as(i64, @intCast(self.cachedFlowerCount)) + result.flowerCountDelta);
        }
    }

    fn getBeehiveHoneyFactor(self: *@This()) f32 {
        var handler = self.createActionHandler();
        return handler.getBeehiveHoneyFactor();
    }

    fn rebirthFlower(self: *@This(), entity: u32) void {
        var handler = self.createActionHandler();
        handler.rebirthFlower(entity);
    }

    fn boostFlowerGrowth(self: *@This(), entity: u32) void {
        var handler = self.createActionHandler();
        handler.boostFlowerGrowth(entity);
    }

    fn drawLabsWidget(self: *@This()) void {
        const auraOn = self.upgradeTree.hasEffect(.lab_aura);
        const burstUnlocked = self.upgradeTree.hasEffect(.lab_burst);
        const bloomUnlocked = self.upgradeTree.hasEffect(.lab_bloom);
        if (!auraOn and !burstUnlocked and !bloomUnlocked) return;

        var y: i32 = 130;
        if (auraOn) {
            rl.drawText(rl.textFormat("Aura: x%.2f", .{self.labs.auraMul}), 10, y, 14, theme.CatppuccinMocha.Color.mauve);
            y += 18;
        }
        if (burstUnlocked) {
            const txt = if (self.labs.burstRemaining > 0)
                rl.textFormat("[B] Burst: ACTIVE %.1fs", .{self.labs.burstRemaining})
            else if (self.labs.burstCooldown > 0)
                rl.textFormat("[B] Burst: %.1fs", .{self.labs.burstCooldown})
            else
                rl.textFormat("[B] Burst: READY", .{});
            rl.drawText(txt, 10, y, 14, theme.CatppuccinMocha.Color.red);
            y += 18;
        }
        if (bloomUnlocked) {
            const txt = if (self.labs.bloomCooldown > 0)
                rl.textFormat("[M] Bloom: %.1fs", .{self.labs.bloomCooldown})
            else
                rl.textFormat("[M] Bloom: READY", .{});
            rl.drawText(txt, 10, y, 14, theme.CatppuccinMocha.Color.pink);
            y += 18;
        }
    }

    fn drawAndHandlePrestigeDialog(self: *@This()) !void {
        const rg = @import("raygui");
        rl.drawRectangle(0, 0, @intFromFloat(self.width), @intFromFloat(self.height), theme.CatppuccinMocha.Color.modalOverlay);

        const popupW: f32 = 420;
        const popupH: f32 = 260;
        const popupX: f32 = (self.width - popupW) / 2;
        const popupY: f32 = (self.height - popupH) / 2;

        rl.drawRectangleRounded(rl.Rectangle.init(popupX, popupY, popupW, popupH), 0.05, 10, theme.CatppuccinMocha.Color.surface0);
        rl.drawRectangleRoundedLines(rl.Rectangle.init(popupX, popupY, popupW, popupH), 0.05, 10, theme.CatppuccinMocha.Color.mauve);

        const title = "Prestige";
        const titleX = @as(i32, @intFromFloat(popupX + popupW / 2)) - @divFloor(rl.measureText(title, 28), 2);
        rl.drawText(title, titleX, @as(i32, @intFromFloat(popupY + 16)), 28, theme.CatppuccinMocha.Color.mauve);

        const gain = self.prestige.gainFromReset();
        const newTotal = self.prestige.royalJelly + gain;
        const newMul = 1.0 + 0.1 * @as(f32, @floatFromInt(newTotal));

        const line1 = rl.textFormat("This run: %.0f honey", .{self.prestige.thisRunHoney});
        rl.drawText(line1, @as(i32, @intFromFloat(popupX + 24)), @as(i32, @intFromFloat(popupY + 60)), 16, theme.CatppuccinMocha.Color.text);

        const line2 = rl.textFormat("Royal Jelly gained: +%d", .{gain});
        rl.drawText(line2, @as(i32, @intFromFloat(popupX + 24)), @as(i32, @intFromFloat(popupY + 88)), 16, theme.CatppuccinMocha.Color.pink);

        const line3 = rl.textFormat("New multiplier: x%.2f  (was x%.2f)", .{ newMul, self.prestige.globalMul() });
        rl.drawText(line3, @as(i32, @intFromFloat(popupX + 24)), @as(i32, @intFromFloat(popupY + 116)), 16, theme.CatppuccinMocha.Color.yellow);

        const warn = "Resets honey, tree, labs, grid, bees.";
        rl.drawText(warn, @as(i32, @intFromFloat(popupX + 24)), @as(i32, @intFromFloat(popupY + 150)), 14, theme.CatppuccinMocha.Color.red);

        const btnW: f32 = 160;
        const btnH: f32 = 40;
        const btnY = popupY + popupH - btnH - 16;

        if (rg.button(rl.Rectangle.init(popupX + 24, btnY, btnW, btnH), "Cancel")) {
            self.showPrestigeDialog = false;
        }
        const confirmRect = rl.Rectangle.init(popupX + popupW - btnW - 24, btnY, btnW, btnH);
        if (gain == 0) rg.setState(@intFromEnum(rg.State.disabled));
        if (rg.button(confirmRect, "Confirm") and gain > 0) {
            try self.doPrestige(gain);
            self.showPrestigeDialog = false;
        }
        rg.setState(@intFromEnum(rg.State.normal));
    }

    fn doPrestige(self: *@This(), gain: u32) !void {
        self.prestige.resetRun(gain);

        // Reset world: full teardown + respawn
        self.world.deinit();
        self.world = World.init(self.allocator);

        self.gridWidth = INITIAL_GRID_WIDTH;
        self.gridHeight = INITIAL_GRID_HEIGHT;
        self.grid.width = INITIAL_GRID_WIDTH;
        self.grid.height = INITIAL_GRID_HEIGHT;
        self.grid.updateOffset();

        _ = try spawners.spawnBeehive(&self.world, &self.textures, INITIAL_GRID_WIDTH, INITIAL_GRID_HEIGHT);
        for (0..INITIAL_GRID_WIDTH) |i| {
            for (0..INITIAL_GRID_HEIGHT) |j| {
                if (i == (INITIAL_GRID_WIDTH - 1) / 2 and j == (INITIAL_GRID_HEIGHT - 1) / 2) continue;
                if (rl.getRandomValue(1, 100) <= FLOWER_SPAWN_CHANCE) {
                    _ = try spawners.spawnRandomFlower(&self.world, &self.textures, @intCast(i), @intCast(j));
                }
            }
        }
        for (0..5) |_| {
            _ = try spawners.spawnBee(&self.world, &self.grid, &self.textures);
        }

        self.resources = Resources.init();
        self.labs = .{};

        self.upgradeTree.deinit();
        self.upgradeTree = upgrade_tree.State.init(self.allocator);

        self.beehiveUpgradeCost = 20.0;
        self.cachedBeeCount = self.world.entityToBeeAI.count();
        self.cachedFlowerCount = self.world.entityToFlowerGrowth.count();
        self.floatingTexts.items.clearRetainingCapacity();
    }

    fn triggerBloom(self: *@This()) void {
        var it = self.world.entityToFlowerGrowth.iterator();
        while (it.next()) |entry| {
            const g = &self.world.flowerGrowths.items[entry.value_ptr.*];
            g.state = 4;
            g.hasPollen = true;
        }
    }

    fn expandGrid(self: *@This()) !void {
        const oldOffset = self.grid.offset;

        self.gridWidth += 2;
        self.gridHeight += 2;
        self.grid.width = self.gridWidth;
        self.grid.height = self.gridHeight;
        self.grid.updateOffset();

        // Shift all existing grid positions by +1,+1 so old center aligns with new center
        var gpIt = self.world.entityToGridPosition.iterator();
        while (gpIt.next()) |entry| {
            const gp = &self.world.gridPositions.items[entry.value_ptr.*];
            gp.x += 1.0;
            gp.y += 1.0;
        }

        // Shift bee pixel positions by the grid offset delta
        const offsetDelta = rl.Vector2{
            .x = self.grid.offset.x - oldOffset.x,
            .y = self.grid.offset.y - oldOffset.y,
        };
        var beeIter = self.world.iterateBees();
        while (beeIter.next()) |entity| {
            if (self.world.getPosition(entity)) |pos| {
                pos.x += offsetDelta.x;
                pos.y += offsetDelta.y;
            }
        }

        // Spawn flowers on new outer ring (30% chance per tile, keep existing center)
        const maxX = self.gridWidth - 1;
        const maxY = self.gridHeight - 1;
        for (0..self.gridWidth) |i| {
            if (rl.getRandomValue(1, 100) <= FLOWER_SPAWN_CHANCE) {
                _ = try spawners.spawnRandomFlower(&self.world, &self.textures, @intCast(i), 0);
            }
            if (rl.getRandomValue(1, 100) <= FLOWER_SPAWN_CHANCE) {
                _ = try spawners.spawnRandomFlower(&self.world, &self.textures, @intCast(i), @intCast(maxY));
            }
        }
        for (1..maxY) |j| {
            if (rl.getRandomValue(1, 100) <= FLOWER_SPAWN_CHANCE) {
                _ = try spawners.spawnRandomFlower(&self.world, &self.textures, 0, @intCast(j));
            }
            if (rl.getRandomValue(1, 100) <= FLOWER_SPAWN_CHANCE) {
                _ = try spawners.spawnRandomFlower(&self.world, &self.textures, @intCast(maxX), @intCast(j));
            }
        }

        self.cachedFlowerCount = self.world.entityToFlowerGrowth.count();
    }

    fn purchaseUpgrade(self: *@This(), nodeId: upgrade_tree.NodeId) !void {
        if (self.upgradeTree.isPurchased(nodeId)) return;
        const node = upgrade_tree.findNode(nodeId) orelse return;
        if (!self.upgradeTree.isUnlocked(node)) return;
        if (!self.resources.spendHoney(node.cost)) return;

        switch (node.effect) {
            .honey_factor_mul => {
                var it = self.world.entityToBeehive.keyIterator();
                if (it.next()) |e| {
                    if (self.world.getBeehive(e.*)) |bh| bh.honeyConversionFactor *= node.value;
                }
            },
            .storage_add => self.resources.honeyCapacity += node.value,
            .growth_cd_sub => self.resources.growthBoostMaxCooldown = @max(2.0, self.resources.growthBoostMaxCooldown - node.value),
            .bee_unlock_swift, .bee_unlock_efficient, .bee_unlock_gardener => {},
            .grid_expand => try self.expandGrid(),
            .lab_aura => self.labs.auraMul = labs.AURA_MUL,
            .lab_burst, .lab_bloom => {}, // unlock only, activation via hotkey
            .prestige_unlock => self.prestige.hasUnlockedPrestige = true,
        }

        try self.upgradeTree.markPurchased(nodeId);
    }
};
