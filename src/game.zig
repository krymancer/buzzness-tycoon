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
const Sky = @import("sky.zig").Sky;
const Ambient = @import("ambient.zig").Ambient;
const clock = @import("clock.zig");
const Audio = @import("audio.zig").Audio;
const text = @import("text.zig");
const locale = @import("localization.zig");
const save = @import("save.zig");

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
    sky: Sky,
    ambient: Ambient,
    audio: Audio,

    world: World,

    resources: Resources,
    hud: ui.Hud,

    cameraOffset: rl.Vector2,
    isDragging: bool,
    lastMousePos: rl.Vector2,

    beehiveUpgradeCost: f32,
    cachedBeeCount: usize,
    cachedFlowerCount: usize,
    cachedHoneyFactor: f32,

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
    io: std.Io,
    env: *std.process.Environ.Map,
    savePath: []u8,
    autosaveTimer: f32,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, env: *std.process.Environ.Map) !@This() {
        locale.detectFromEnvironment(env);
        // Seed raylib's RNG from the wall clock (std.crypto.random was removed in 0.16;
        // time is now read through an Io clock).
        const nowTs = std.Io.Clock.now(.real, io);
        const seed: u96 = @bitCast(nowTs.nanoseconds);
        rl.setRandomSeed(@truncate(seed));

        // Monitor queries only work once GLFW is up, so open a default-size
        // window first, then size it to the monitor. (Querying before
        // initWindow returns 0 on raylib 6 → an 800x450 fallback window.)
        // Render at native pixel density on high-DPI displays (macOS Retina
        // renders blurry at quarter resolution without this).
        rl.setConfigFlags(.{ .window_highdpi = true });
        rl.initWindow(1280, 720, "Buzzness Tycoon");
        rl.setExitKey(rl.KeyboardKey.null); // Disable default ESC closing the window
        rl.setWindowState(.{ .window_resizable = true });
        // Dev: BT_WINDOWED runs in a plain window (no fullscreen takeover) so
        // the game can be launched/screenshotted without hijacking the desktop.
        if (env.get("BT_WINDOWED") == null) {
            const monitor = rl.getCurrentMonitor();
            const mw = rl.getMonitorWidth(monitor);
            const mh = rl.getMonitorHeight(monitor);
            if (mw > 0 and mh > 0) rl.setWindowSize(mw, mh);
            rl.toggleFullscreen();
        } else {
            // Dev: BT_W/BT_H override the windowed size (e.g. 1920x1080 for
            // store screenshots); default to the handy 1366x820 work size.
            // When overridden we drop the WM decorations and pin to (0,0) so the
            // window can occupy the full monitor height without a title bar
            // clamping it (needed for pixel-exact 16:9 captures).
            const hasSize = env.get("BT_W") != null or env.get("BT_H") != null;
            const sw = if (env.get("BT_W")) |s| (std.fmt.parseInt(i32, s, 10) catch 1366) else 1366;
            const sh = if (env.get("BT_H")) |s| (std.fmt.parseInt(i32, s, 10) catch 820) else 820;
            if (hasSize) rl.setWindowState(.{ .window_undecorated = true });
            rl.setWindowSize(sw, sh);
            if (hasSize) rl.setWindowPosition(0, 0);
        }
        if (env.get("BT_PHASE")) |p| {
            Sky.phaseOverride = std.fmt.parseFloat(f32, p) catch null;
        }
        if (env.get("BT_DAYLEN")) |d| {
            Sky.dayLengthOverride = std.fmt.parseFloat(f32, d) catch null;
        }
        // Capture mode drives the clock at a fixed 30fps step so a slow PNG
        // dump still yields smooth, real-time-paced video.
        if (env.get("BT_CAPTURE") != null) clock.fixedDt = 1.0 / 30.0;
        const windowIcon = try assets.loadImageFromMemory(assets.bee_png);
        rl.setWindowIcon(windowIcon);

        // Load the shared UI font (needs the GL context from initWindow).
        text.load();

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
        for (0..8) |_| {
            _ = try spawners.spawnBee(&world, &grid, &textures);
        }

        const savePath = try save.path(allocator, env);
        errdefer allocator.free(savePath);

        var game: @This() = .{
            .allocator = allocator,
            .io = io,
            .windowIcon = windowIcon,

            .textures = textures,
            .grid = grid,
            .sky = Sky.init(),
            .ambient = Ambient.init(),
            .audio = Audio.init(allocator),
            .world = world,

            .resources = Resources.init(),
            .hud = ui.Hud.init(),
            .metrics = Metrics.init(io),
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
            .cachedHoneyFactor = 1.0,

            .showTilePopup = false,
            .popupJustOpened = false,
            .selectedTileX = 0,
            .selectedTileY = 0,
            .clickStartPos = rl.Vector2.init(0, 0),

            .showPauseMenu = false,
            .isPaused = false,
            .shouldExit = false,

            .state = if (env.get("BT_AUTOPLAY") != null) .playing else .title_screen,
            .env = env,
            .savePath = savePath,
            .autosaveTimer = 0,

            .width = width,
            .height = height,
            .gridWidth = INITIAL_GRID_WIDTH,
            .gridHeight = INITIAL_GRID_HEIGHT,
        };

        game.loadProgress() catch |err| switch (err) {
            error.FileNotFound => {},
            else => std.debug.print("Could not load save '{s}': {}\n", .{ savePath, err }),
        };
        return game;
    }

    pub fn deinit(self: *@This()) void {
        self.grid.deinit();
        self.textures.deinit();
        self.hud.deinit();
        self.world.deinit();
        self.metrics.deinit();
        self.floatingTexts.deinit();
        self.upgradeTree.deinit();
        self.audio.deinit();
        self.allocator.free(self.savePath);
        text.unload();
        ui.title_screen.deinit();

        rl.closeWindow();
        rl.unloadImage(self.windowIcon);
    }

    pub fn run(self: *@This()) !void {
        defer self.saveProgress() catch |err| std.debug.print("Could not save progress: {}\n", .{err});
        // Dev: BT_SHOOT=N renders N frames, writes a screenshot, then exits.
        const shootAt: ?u32 = blk: {
            const v = self.env.get("BT_SHOOT") orelse break :blk null;
            break :blk std.fmt.parseInt(u32, v, 10) catch null;
        };
        // Dev/trailer: BT_CAPTURE=N renders N frames at 30fps, dumping each to
        // steam/art/frames/cap_XXXXX.png (assembled into a video by ffmpeg).
        const captureN: ?u32 = blk: {
            const v = self.env.get("BT_CAPTURE") orelse break :blk null;
            break :blk std.fmt.parseInt(u32, v, 10) catch null;
        };
        if (shootAt != null) rl.setTargetFPS(60);
        if (captureN != null) rl.setTargetFPS(30);
        var frame: u32 = 0;

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

            frame += 1;
            clock.advance();
            if (captureN) |n| {
                var buf: [96]u8 = undefined;
                const path = std.fmt.bufPrintZ(&buf, "steam/art/frames/cap_{d:0>5}.png", .{frame}) catch unreachable;
                rl.takeScreenshot(path);
                if (frame >= n) self.shouldExit = true;
            }
            if (shootAt) |n| {
                if (frame >= n) {
                    rl.takeScreenshot("bt_shot.png");
                    self.shouldExit = true;
                }
            }
        }
    }

    /// Handle input common to all game states (fullscreen, window resize)
    fn handleCommonInput(self: *@This()) void {
        // Keep the ambient audio bed looping in every state, and allow muting.
        self.audio.update(clock.frameTime());
        if (rl.isKeyPressed(rl.KeyboardKey.n)) self.audio.toggleMute();

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

        // Cozy animated sky behind the title, with a subtle darkening wash so
        // the menu text stays readable.
        self.sky.drawBackground(self.width, self.height);
        self.sky.drawCelestial(self.width, self.height);
        rl.drawRectangle(0, 0, @intFromFloat(self.width), @intFromFloat(self.height), rl.Color.init(20, 20, 40, 90));

        const action = ui.title_screen.draw(self.width, self.height);
        switch (action) {
            .play => self.state = .playing,
            .quit => self.shouldExit = true,
            .toggle_language => locale.toggle(),
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
                self.saveProgress() catch |err| std.debug.print("Could not save progress: {}\n", .{err});
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

        // Generous threshold so a small hand-wobble during a click still counts
        // as a click, not a camera drag.
        if (dragDistance >= 12.0) return;

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

        const deltaTime = clock.frameTime();

        self.autosaveTimer += deltaTime;
        if (self.autosaveTimer >= 10.0) {
            self.saveProgress() catch |err| std.debug.print("Could not autosave progress: {}\n", .{err});
            self.autosaveTimer = 0;
        }

        self.resources.updateCooldown(deltaTime);
        self.resources.tickRate(deltaTime);
        self.labs.update(deltaTime);

        // Cache honey factor once per frame (draw re-uses this — no double lookup).
        self.cachedHoneyFactor = self.getBeehiveHoneyFactor();

        try lifespan_system.update(&self.world, deltaTime);
        try flower_growth_system.update(&self.world, deltaTime);

        var frameHoneyGain: f32 = 0;
        try bee_ai_system.update(.{
            .world = &self.world,
            .deltaTime = deltaTime,
            .gridOffset = self.grid.offset,
            .gridScale = self.grid.scale,
            .gridWidth = self.gridWidth,
            .gridHeight = self.gridHeight,
            .texturesRef = self.textures,
            .resources = &self.resources,
            .labs = &self.labs,
            .prestige = &self.prestige,
            .honeyFactor = self.cachedHoneyFactor,
            .frameHoneyGain = &frameHoneyGain,
        });
        try flower_spawning_system.update(&self.world, deltaTime, self.grid.offset, self.grid.scale, self.gridWidth, self.gridHeight, self.textures);
        scale_sync_system.update(&self.world, self.grid.scale);

        self.cachedBeeCount = self.world.entityToBeeAI.count();
        self.cachedFlowerCount = self.world.entityToFlowerGrowth.count();

        if (frameHoneyGain > 0) {
            const centerX: f32 = @floatFromInt((self.gridWidth - 1) / 2);
            const centerY: f32 = @floatFromInt((self.gridHeight - 1) / 2);
            try self.floatingTexts.spawn(centerX, centerY, frameHoneyGain);
            self.audio.playCollect();
        }
        self.floatingTexts.update(deltaTime);
        self.ambient.update(deltaTime, self.width - ui.side_panel.PANEL_WIDTH, self.height);

        try self.world.processDestroyQueue();
    }

    pub fn draw(self: *@This()) !void {
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(theme.CatppuccinMocha.Color.base);

        // Cozy animated sky behind everything.
        self.sky.drawBackground(self.width, self.height);

        self.grid.draw(self.sky.worldTint());

        try render_system.draw(&self.world, self.grid.offset, self.grid.scale, self.sky.worldTint());

        self.floatingTexts.draw(self.grid.offset, self.grid.scale);

        // Ambient day/night light wash + vignette over the whole meadow.
        self.sky.drawAmbientOverlay(self.width, self.height);

        // Sun/moon on top of the wash so they stay bright and crisp.
        self.sky.drawCelestial(self.width, self.height);

        // Floating pollen dust / fireflies over the light wash so they glow.
        self.ambient.draw(self.sky.nightFactor());

        // Draw HUD (reuses this frame's cached factor)
        const honeyFactor = self.cachedHoneyFactor;
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

        // Dev FPS/frametime readout. BT_HIDE_DEBUG suppresses it for clean
        // store screenshots. (frameTime is still computed below for metrics.)
        if (self.env.get("BT_HIDE_DEBUG") == null) {
            const fpsX = @as(i32, @intFromFloat(self.width - ui.side_panel.PANEL_WIDTH - 100));
            rl.drawFPS(fpsX, 10);
            text.draw(rl.textFormat("%.2f ms", .{rl.getFrameTime() * 1000.0}), fpsX, 30, 20, rl.Color.white);
        }

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
                .toggle_language => locale.toggle(),
                .none => {},
            }
        }

        // Log metrics
        const fps: f32 = @floatFromInt(rl.getFPS());
        self.metrics.log(fps, rl.getFrameTime() * 1000.0, self.cachedBeeCount, self.cachedFlowerCount);
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
            text.draw(rl.textFormat("Aura: x%.2f", .{self.labs.auraMul}), 10, y, 18, theme.CatppuccinMocha.Color.mauve);
            y += 23;
        }
        if (burstUnlocked) {
            const txt = if (self.labs.burstRemaining > 0)
                rl.textFormat(locale.tr("[B] Burst: ACTIVE %.1fs", "[B] Explosão: ATIVA %.1fs"), .{self.labs.burstRemaining})
            else if (self.labs.burstCooldown > 0)
                rl.textFormat(locale.tr("[B] Burst: %.1fs", "[B] Explosão: %.1fs"), .{self.labs.burstCooldown})
            else
                rl.textFormat(locale.tr("[B] Burst: READY", "[B] Explosão: PRONTA"), .{});
            text.draw(txt, 10, y, 18, theme.CatppuccinMocha.Color.red);
            y += 23;
        }
        if (bloomUnlocked) {
            const txt = if (self.labs.bloomCooldown > 0)
                rl.textFormat(locale.tr("[M] Bloom: %.1fs", "[M] Florescer: %.1fs"), .{self.labs.bloomCooldown})
            else
                rl.textFormat(locale.tr("[M] Bloom: READY", "[M] Florescer: PRONTO"), .{});
            text.draw(txt, 10, y, 18, theme.CatppuccinMocha.Color.pink);
            y += 23;
        }
    }

    fn drawAndHandlePrestigeDialog(self: *@This()) !void {
        const rg = @import("raygui");
        rl.drawRectangle(0, 0, @intFromFloat(self.width), @intFromFloat(self.height), theme.CatppuccinMocha.Color.modalOverlay);

        const popupW: f32 = 520;
        const popupH: f32 = 260;
        const popupX: f32 = (self.width - popupW) / 2;
        const popupY: f32 = (self.height - popupH) / 2;

        rl.drawRectangleRounded(rl.Rectangle.init(popupX, popupY, popupW, popupH), 0.05, 10, theme.CatppuccinMocha.Color.surface0);
        rl.drawRectangleRoundedLines(rl.Rectangle.init(popupX, popupY, popupW, popupH), 0.05, 10, theme.CatppuccinMocha.Color.mauve);

        const title = locale.tr("Prestige", "Prestígio");
        const titleX = @as(i32, @intFromFloat(popupX + popupW / 2)) - @divFloor(text.measure(title, 28), 2);
        text.draw(title, titleX, @as(i32, @intFromFloat(popupY + 16)), 28, theme.CatppuccinMocha.Color.mauve);

        const gain = self.prestige.gainFromReset();
        const newTotal = self.prestige.royalJelly + gain;
        const newMul = 1.0 + 0.1 * @as(f32, @floatFromInt(newTotal));

        const line1 = rl.textFormat(locale.tr("This run: %.0f honey", "Nesta partida: %.0f mel"), .{self.prestige.thisRunHoney});
        text.draw(line1, @as(i32, @intFromFloat(popupX + 24)), @as(i32, @intFromFloat(popupY + 60)), 16, theme.CatppuccinMocha.Color.text);

        const line2 = rl.textFormat(locale.tr("Royal Jelly gained: +%d", "Geleia Real recebida: +%d"), .{gain});
        text.draw(line2, @as(i32, @intFromFloat(popupX + 24)), @as(i32, @intFromFloat(popupY + 88)), 16, theme.CatppuccinMocha.Color.pink);

        const line3 = rl.textFormat(locale.tr("New multiplier: x%.2f  (was x%.2f)", "Novo multiplicador: x%.2f  (antes x%.2f)"), .{ newMul, self.prestige.globalMul() });
        text.draw(line3, @as(i32, @intFromFloat(popupX + 24)), @as(i32, @intFromFloat(popupY + 116)), 16, theme.CatppuccinMocha.Color.yellow);

        const warn = locale.tr("Resets honey, tree, labs, grid, bees.", "Reinicia mel, árvore, labs, grade e abelhas.");
        text.draw(warn, @as(i32, @intFromFloat(popupX + 24)), @as(i32, @intFromFloat(popupY + 150)), 16, theme.CatppuccinMocha.Color.red);

        const btnW: f32 = 160;
        const btnH: f32 = 40;
        const btnY = popupY + popupH - btnH - 16;

        if (rg.button(rl.Rectangle.init(popupX + 24, btnY, btnW, btnH), locale.tr("Cancel", "Cancelar"))) {
            self.showPrestigeDialog = false;
        }
        const confirmRect = rl.Rectangle.init(popupX + popupW - btnW - 24, btnY, btnW, btnH);
        if (gain == 0) rg.setState(@intFromEnum(rg.State.disabled));
        if (rg.button(confirmRect, locale.tr("Confirm", "Confirmar")) and gain > 0) {
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

        // Module-level caches hold stale entity IDs across the rebuild.
        bee_ai_system.resetCaches();
        render_system.resetCaches();

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
        for (0..8) |_| {
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

        // Shift cached target coords on locked bees so they don't chase stale tiles.
        var beeAiIt = self.world.entityToBeeAI.iterator();
        while (beeAiIt.next()) |entry| {
            const ai = &self.world.beeAIs.items[entry.value_ptr.*];
            if (ai.targetLocked) {
                ai.targetGridX += 1.0;
                ai.targetGridY += 1.0;
            }
        }

        // Cached beehive grid coords shifted — invalidate so caches refresh.
        bee_ai_system.resetCaches();
        render_system.resetCaches();

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
            .bee_unlock_worker, .bee_unlock_swift, .bee_unlock_efficient, .bee_unlock_gardener => {},
            .grid_expand => try self.expandGrid(),
            .lab_aura => self.labs.auraMul = labs.AURA_MUL,
            .lab_burst, .lab_bloom => {}, // unlock only, activation via hotkey
            .prestige_unlock => self.prestige.hasUnlockedPrestige = true,
        }

        try self.upgradeTree.markPurchased(nodeId);
    }

    fn saveProgress(self: *@This()) !void {
        var data = save.Data{
            .language = @intFromEnum(locale.current()),
            .honey = self.resources.honey,
            .honey_capacity = self.resources.honeyCapacity,
            .storage_level = self.resources.storageLevel,
            .honey_per_sec = self.resources.honeyPerSec,
            .growth_cooldown = self.resources.growthBoostCooldown,
            .growth_max_cooldown = self.resources.growthBoostMaxCooldown,
            .growth_level = self.resources.growthBoostLevel,
            .beehive_factor = self.getBeehiveHoneyFactor(),
            .beehive_upgrade_cost = self.beehiveUpgradeCost,
            .grid_width = self.gridWidth,
            .grid_height = self.gridHeight,
            .royal_jelly = self.prestige.royalJelly,
            .this_run_honey = self.prestige.thisRunHoney,
            .prestige_unlocked = self.prestige.hasUnlockedPrestige,
            .aura_multiplier = self.labs.auraMul,
            .burst_remaining = self.labs.burstRemaining,
            .burst_cooldown = self.labs.burstCooldown,
            .bloom_cooldown = self.labs.bloomCooldown,
        };
        defer data.deinit(self.allocator);

        var upgrade_it = self.upgradeTree.purchased.keyIterator();
        while (upgrade_it.next()) |id| {
            if (id.* < data.purchased.len) data.purchased[id.*] = true;
        }

        var bee_it = self.world.iterateBees();
        while (bee_it.next()) |entity| {
            const ai = self.world.getBeeAI(entity) orelse continue;
            const index: usize = @intFromEnum(ai.beeType);
            if (index < data.bee_counts.len and data.bee_counts[index] < save.MAX_BEES_PER_TYPE) {
                data.bee_counts[index] += 1;
            }
        }

        var flower_it = self.world.iterateFlowers();
        while (flower_it.next()) |entity| {
            const grid_pos = self.world.getGridPosition(entity) orelse continue;
            const growth = self.world.getFlowerGrowth(entity) orelse continue;
            const lifespan = self.world.getLifespan(entity) orelse continue;
            if (data.flowers.items.len >= save.MAX_FLOWERS) break;
            try data.flowers.append(self.allocator, .{
                .flower_type = @intFromEnum(growth.flowerType),
                .x = @intFromFloat(grid_pos.x),
                .y = @intFromFloat(grid_pos.y),
                .state = growth.state,
                .growth_time_alive = growth.timeAlive,
                .growth_rate = growth.growthRate,
                .growth_threshold = growth.growthThreshold,
                .has_pollen = growth.hasPollen,
                .pollen_cooldown = growth.pollenCooldown,
                .pollen_multiplier = growth.pollenMultiplier,
                .lifespan_time_alive = lifespan.timeAlive,
                .lifespan_total_time_alive = lifespan.totalTimeAlive,
                .lifespan_time_span = lifespan.timeSpan,
            });
        }

        try save.write(self.io, self.savePath, &data);
    }

    fn loadProgress(self: *@This()) !void {
        var data = try save.read(self.allocator, self.io, self.savePath);
        defer data.deinit(self.allocator);

        if (data.grid_width < INITIAL_GRID_WIDTH or data.grid_height < INITIAL_GRID_HEIGHT or
            data.grid_width != data.grid_height or data.grid_width > 127 or data.grid_width % 2 == 0)
        {
            return error.InvalidSave;
        }

        var total_bees: u32 = 0;
        for (data.bee_counts) |count| {
            total_bees = std.math.add(u32, total_bees, count) catch return error.SaveTooLarge;
            if (total_bees > save.MAX_BEES_PER_TYPE) return error.SaveTooLarge;
        }

        locale.set(switch (data.language) {
            1 => .portuguese_br,
            else => .english,
        });

        self.world.deinit();
        self.world = World.init(self.allocator);
        bee_ai_system.resetCaches();
        render_system.resetCaches();

        self.gridWidth = data.grid_width;
        self.gridHeight = data.grid_height;
        self.grid.width = data.grid_width;
        self.grid.height = data.grid_height;
        self.grid.updateOffset();

        const hive = try spawners.spawnBeehive(&self.world, &self.textures, self.gridWidth, self.gridHeight);
        if (self.world.getBeehive(hive)) |beehive| {
            beehive.honeyConversionFactor = finiteAtLeast(data.beehive_factor, 1.0, 1.0);
        }

        for (data.flowers.items) |flower| {
            if (flower.x < 0 or flower.y < 0 or
                flower.x >= @as(i32, @intCast(self.gridWidth)) or flower.y >= @as(i32, @intCast(self.gridHeight))) continue;
            const flower_type: components.FlowerType = switch (flower.flower_type) {
                0 => .rose,
                1 => .tulip,
                2 => .dandelion,
                else => continue,
            };
            const entity = try spawners.spawnFlower(&self.world, &self.textures, spawners.flowerTypeToFlowers(flower_type), flower.x, flower.y);
            if (self.world.getFlowerGrowth(entity)) |growth| {
                growth.state = finiteInRange(flower.state, 0, 4, 0);
                growth.timeAlive = finiteAtLeast(flower.growth_time_alive, 0, 0);
                growth.growthRate = finiteAtLeast(flower.growth_rate, 0.01, 1);
                growth.growthThreshold = finiteAtLeast(flower.growth_threshold, 0.01, 35);
                growth.hasPollen = flower.has_pollen;
                growth.pollenCooldown = finiteAtLeast(flower.pollen_cooldown, 0, 0);
                growth.pollenMultiplier = finiteAtLeast(flower.pollen_multiplier, 0.1, 1);
            }
            if (self.world.getLifespan(entity)) |lifespan| {
                lifespan.timeAlive = finiteAtLeast(flower.lifespan_time_alive, 0, 0);
                lifespan.totalTimeAlive = finiteAtLeast(flower.lifespan_total_time_alive, 0, 0);
                lifespan.timeSpan = finiteAtLeast(flower.lifespan_time_span, 1, 60);
            }
        }

        for (data.bee_counts, 0..) |count, index| {
            const bee_type: components.BeeType = switch (index) {
                0 => .worker,
                1 => .swift,
                2 => .efficient,
                3 => .gardener,
                else => unreachable,
            };
            for (0..count) |_| {
                _ = try spawners.spawnBeeWithType(&self.world, &self.grid, &self.textures, bee_type);
            }
        }

        self.resources.honey = finiteAtLeast(data.honey, 0, 100);
        self.resources.honeyCapacity = finiteAtLeast(data.honey_capacity, 1, 500);
        self.resources.storageLevel = @max(1, data.storage_level);
        self.resources.honeyPerSec = finiteAtLeast(data.honey_per_sec, 0, 0);
        self.resources.honeyThisSecond = 0;
        self.resources.rateWindowTimer = 0;
        self.resources.growthBoostCooldown = finiteAtLeast(data.growth_cooldown, 0, 0);
        self.resources.growthBoostMaxCooldown = finiteAtLeast(data.growth_max_cooldown, 2, 10);
        self.resources.growthBoostLevel = @max(1, data.growth_level);
        self.beehiveUpgradeCost = finiteAtLeast(data.beehive_upgrade_cost, 1, 20);

        self.upgradeTree.deinit();
        self.upgradeTree = upgrade_tree.State.init(self.allocator);
        for (data.purchased, 0..) |purchased, id| {
            if (purchased and upgrade_tree.findNode(@intCast(id)) != null) {
                try self.upgradeTree.markPurchased(@intCast(id));
            }
        }

        self.prestige.royalJelly = data.royal_jelly;
        self.prestige.thisRunHoney = finiteAtLeast(data.this_run_honey, 0, 0);
        self.prestige.hasUnlockedPrestige = data.prestige_unlocked or self.upgradeTree.hasEffect(.prestige_unlock);
        self.labs.auraMul = finiteAtLeast(data.aura_multiplier, 1, 1);
        self.labs.burstRemaining = finiteAtLeast(data.burst_remaining, 0, 0);
        self.labs.burstCooldown = finiteAtLeast(data.burst_cooldown, 0, 0);
        self.labs.bloomCooldown = finiteAtLeast(data.bloom_cooldown, 0, 0);

        self.cachedBeeCount = self.world.entityToBeeAI.count();
        self.cachedFlowerCount = self.world.entityToFlowerGrowth.count();
        self.cachedHoneyFactor = self.getBeehiveHoneyFactor();
        self.floatingTexts.items.clearRetainingCapacity();
        self.autosaveTimer = 0;
    }

    fn finiteAtLeast(value: f32, minimum: f32, fallback: f32) f32 {
        if (!std.math.isFinite(value)) return fallback;
        return @max(minimum, value);
    }

    fn finiteInRange(value: f32, minimum: f32, maximum: f32, fallback: f32) f32 {
        if (!std.math.isFinite(value)) return fallback;
        return std.math.clamp(value, minimum, maximum);
    }
};
