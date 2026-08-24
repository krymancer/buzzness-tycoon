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
const utils = @import("utils.zig");
const ui_scale = @import("ui_scale.zig");
const settings = @import("settings.zig");
const input = @import("input.zig");
const widgets = @import("ui/widgets.zig");

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
    /// How far outside the meadow (in tiles) saved bee cells may sit; bees
    /// that wandered further are folded back to this rim on save/load.
    const BEE_CELL_MARGIN: i32 = 8;

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

    cachedBeeCount: usize,
    cachedBeeTypeCounts: [4]usize,
    cachedFlowerCount: usize,
    cachedHoneyFactor: f32,

    metrics: Metrics,

    floatingTexts: floating_text.Manager,
    upgradeTree: upgrade_tree.State,
    showTree: bool,
    showOptions: bool,
    plantMenu: ui.plant_menu.State,
    labs: labs.LabState,
    prestige: prestige_mod.PrestigeState,
    showPrestigeDialog: bool,

    // Tile popup state
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
    /// True when a save was loaded at startup (title shows Continue/New Game).
    hasSavedGame: bool,
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
        // Normal runs apply the saved window mode after the save loads (below).
        const useSavedWindowMode = env.get("BT_WINDOWED") == null;
        if (!useSavedWindowMode) {
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
        // The game draws its own pointer (input.drawCursor) for mouse and
        // gamepad alike; hide the OS cursor over the window.
        rl.hideCursor();

        // Load the shared UI font (needs the GL context from initWindow).
        text.load();

        // Dev: BT_UI_SCALE pins the UI scale (bypasses auto-fit + preference).
        if (env.get("BT_UI_SCALE")) |s| {
            ui_scale.setOverride(std.fmt.parseFloat(f32, s) catch null);
        }
        ui_scale.refresh();

        const width: f32 = ui_scale.width();
        const height: f32 = ui_scale.height();

        const textures = try Textures.init();
        const grid = try Grid.init(INITIAL_GRID_WIDTH, INITIAL_GRID_HEIGHT, width, height);

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
            // Dev: BT_OPEN_TREE starts with the upgrade tree open (screenshots).
            .showTree = env.get("BT_OPEN_TREE") != null,
            // Dev: BT_OPEN_OPTIONS starts with the options panel open.
            .showOptions = env.get("BT_OPEN_OPTIONS") != null,
            // Dev: BT_OPEN_PLANT=x,y starts with the plant chooser open on a tile.
            .plantMenu = blk: {
                var st: ui.plant_menu.State = .{};
                if (env.get("BT_OPEN_PLANT")) |v| {
                    var it = std.mem.splitScalar(u8, v, ',');
                    const xs = it.next() orelse "0";
                    const ys = it.next() orelse "0";
                    st.openAt(std.fmt.parseInt(i32, xs, 10) catch 0, std.fmt.parseInt(i32, ys, 10) catch 0);
                }
                break :blk st;
            },
            .labs = .{},
            .prestige = .{},
            .showPrestigeDialog = false,

            .cameraOffset = rl.Vector2.init(0, 0),
            .isDragging = false,
            .lastMousePos = rl.Vector2.init(0, 0),

            .cachedBeeCount = 0,
            .cachedBeeTypeCounts = .{ 0, 0, 0, 0 },
            .cachedFlowerCount = 0,
            .cachedHoneyFactor = 1.0,

            .clickStartPos = rl.Vector2.init(0, 0),

            .showPauseMenu = false,
            .isPaused = false,
            .shouldExit = false,

            .state = if (env.get("BT_AUTOPLAY") != null) .playing else .title_screen,
            .env = env,
            .savePath = savePath,
            .hasSavedGame = false,
            .autosaveTimer = 0,

            .width = width,
            .height = height,
            .gridWidth = INITIAL_GRID_WIDTH,
            .gridHeight = INITIAL_GRID_HEIGHT,
        };

        spawners.superFlowersUnlocked = false;
        if (game.loadProgress()) {
            game.hasSavedGame = true;
        } else |err| switch (err) {
            error.FileNotFound => {},
            else => std.debug.print("Could not load save '{s}': {}\n", .{ savePath, err }),
        }
        if (useSavedWindowMode) settings.apply(settings.windowMode);
        return game;
    }

    pub fn deinit(self: *@This()) void {
        render_system.deinit();
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
        ui.prompt_icons.deinit();
        input.deinit();

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
        // BT_UNCAPPED=1 lifts the cap so benchmark runs measure real headroom.
        if (shootAt != null and self.env.get("BT_UNCAPPED") == null) rl.setTargetFPS(60);
        if (captureN != null) rl.setTargetFPS(30);
        var frame: u32 = 0;

        while (!rl.windowShouldClose() and !self.shouldExit) {
            self.handleCommonInput();
            switch (self.state) {
                .title_screen => try self.drawTitleScreen(),
                .playing => {
                    try self.handlePlayingInput();
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

    /// True when a menu/modal owns input: d-pad navigates and the right
    /// stick scrolls instead of driving world shortcuts and the camera.
    fn inMenuContext(self: *const @This()) bool {
        return self.state == .title_screen or self.showOptions or self.showPauseMenu or
            self.showTree or self.showPrestigeDialog or self.plantMenu.open;
    }

    /// Handle input common to all game states (fullscreen, window resize)
    fn handleCommonInput(self: *@This()) void {
        input.beginFrame(self.inMenuContext());
        // Keep the ambient audio bed looping in every state, and allow muting.
        self.audio.update(clock.frameTime());
        if (rl.isKeyPressed(rl.KeyboardKey.n)) self.audio.toggleMute();

        // Alt+Enter toggles between windowed and the chosen fullscreen mode.
        if (rl.isKeyPressed(rl.KeyboardKey.enter) and rl.isKeyDown(rl.KeyboardKey.left_alt)) {
            settings.toggleQuick();
        }

        // Cmd/Ctrl +/- adjusts the UI scale; Cmd/Ctrl 0 resets it.
        const mod = rl.isKeyDown(rl.KeyboardKey.left_super) or rl.isKeyDown(rl.KeyboardKey.right_super) or
            rl.isKeyDown(rl.KeyboardKey.left_control) or rl.isKeyDown(rl.KeyboardKey.right_control);
        if (mod) {
            if (rl.isKeyPressed(rl.KeyboardKey.equal) or rl.isKeyPressed(rl.KeyboardKey.kp_add)) ui_scale.adjustUser(0.1);
            if (rl.isKeyPressed(rl.KeyboardKey.minus) or rl.isKeyPressed(rl.KeyboardKey.kp_subtract)) ui_scale.adjustUser(-0.1);
            if (rl.isKeyPressed(rl.KeyboardKey.zero) or rl.isKeyPressed(rl.KeyboardKey.kp_0)) ui_scale.resetUser();
        }
        ui_scale.refresh();

        // React to logical-size changes (window resize or UI-scale change):
        // re-center the grid viewport and carry the bees along with it.
        const currentWidth = ui_scale.width();
        const currentHeight = ui_scale.height();
        if (currentWidth != self.width or currentHeight != self.height) {
            const oldOffset = self.grid.offset;
            self.grid.updateViewport(currentWidth, currentHeight);
            self.translateBees(.{
                .x = self.grid.offset.x - oldOffset.x,
                .y = self.grid.offset.y - oldOffset.y,
            });
            self.width = currentWidth;
            self.height = currentHeight;
        }
    }

    fn drawTitleScreen(self: *@This()) !void {
        rl.beginDrawing();
        defer rl.endDrawing();
        ui_scale.begin();
        defer ui_scale.end();
        defer input.drawCursor();

        rl.clearBackground(theme.CatppuccinMocha.Color.base);

        // Cozy animated sky behind the title, with a subtle darkening wash so
        // the menu text stays readable.
        self.sky.drawBackground(self.width, self.height);
        self.sky.drawCelestial(self.width, self.height);
        rl.drawRectangle(0, 0, @intFromFloat(self.width), @intFromFloat(self.height), rl.Color.init(20, 20, 40, 90));

        if (self.showOptions) {
            if (rl.isKeyPressed(rl.KeyboardKey.escape) or input.cancelPressed()) self.showOptions = false;
            self.drawAndHandleOptions();
            return;
        }
        const action = ui.title_screen.draw(self.width, self.height, self.hasSavedGame);
        switch (action) {
            .play => self.state = .playing,
            .new_game => {
                try self.startNewGame();
                self.state = .playing;
            },
            .quit => self.shouldExit = true,
            .options => self.showOptions = true,
            .none => {},
        }
    }

    /// Options overlay (title screen and pause menu). Applies changes live;
    /// they persist through the normal save.
    fn drawAndHandleOptions(self: *@This()) void {
        const action = ui.options.draw(.{
            .screenWidth = self.width,
            .screenHeight = self.height,
            .windowMode = settings.windowMode,
            .language = locale.current(),
            .musicVolume = self.audio.musicVolume,
            .fxVolume = self.audio.fxVolume,
            .uiScale = ui_scale.user(),
            .cursorSnap = settings.cursorSnap,
        });
        switch (action) {
            .none => {},
            .back => self.showOptions = false,
            .window_mode => |m| settings.apply(m),
            .language => |l| locale.set(l),
            .music_volume => |v| self.audio.setMusicVolume(v),
            .fx_volume => |v| {
                self.audio.setFxVolume(v);
                // Audition the new level so the slider is tunable by ear.
                self.audio.playCollect();
            },
            .ui_scale => |s| ui_scale.setUser(s),
            .cursor_snap => |v| settings.cursorSnap = v,
        }
    }

    /// Handle input specific to playing state
    fn handlePlayingInput(self: *@This()) !void {
        // Handle Escape key (or gamepad B) - close popups first, then
        // show/hide pause menu
        if (rl.isKeyPressed(rl.KeyboardKey.escape) or input.cancelPressed()) {
            if (self.showOptions) {
                self.showOptions = false;
                return;
            } else if (self.showPrestigeDialog) {
                self.showPrestigeDialog = false;
                return;
            } else if (self.showTree) {
                self.showTree = false;
                return;
            } else if (self.plantMenu.open) {
                self.plantMenu.open = false;
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

        // Gamepad Start: pause toggle (only over the plain world, so it never
        // silently closes another menu).
        if (input.startPressed()) {
            if (self.showPauseMenu) {
                self.showPauseMenu = false;
                self.isPaused = false;
                return;
            } else if (!self.inMenuContext()) {
                self.showPauseMenu = true;
                self.isPaused = true;
                self.saveProgress() catch |err| std.debug.print("Could not save progress: {}\n", .{err});
                return;
            }
        }

        // Gamepad Y: upgrade tree toggle.
        if (input.treePressed()) {
            if (self.showTree) {
                self.showTree = false;
                return;
            } else if (!self.inMenuContext()) {
                self.showTree = true;
                ui.tree_view.resetScroll();
                return;
            }
        }

        // Block input when popup, pause menu, tree, or prestige dialog is open
        if (self.showPauseMenu or self.showTree or self.showPrestigeDialog) {
            return;
        }
        // The plant chooser owns the mouse while open (draw() handles it).
        if (self.plantMenu.open) return;

        const mousePos = input.pointerPos();
        const mouseInPanel = input.pointerInUi();

        if (input.confirmPressed() and !mouseInPanel) {
            self.isDragging = true;
            self.lastMousePos = mousePos;
            self.clickStartPos = mousePos;
        }

        if (input.confirmReleased()) {
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
            // Panning must stay visual-only: bee targets are recomputed from
            // the new offset every frame, so bees left at their old screen
            // positions would chase moving targets and stall production.
            self.translateBees(mouseDelta);
            self.lastMousePos = mousePos;
        }

        const wheelMove = rl.getMouseWheelMove();
        if (wheelMove != 0.0) {
            self.grid.zoom(wheelMove * 0.3);
        }

        try self.handleWorldShortcuts();
    }

    /// World-mode shortcuts, gamepad and keyboard: camera pan (right stick /
    /// WASD/arrows), zoom (triggers / +-), X plants on the hovered tile,
    /// LB/RB cycle the buy quantity, and d-pad / 1-4 quick-buy one bee.
    fn handleWorldShortcuts(self: *@This()) !void {
        // Panning moves the camera, so the world shifts the other way (same
        // bookkeeping as a mouse drag).
        const pan = input.cameraPan();
        if (pan.x != 0 or pan.y != 0) {
            const delta = rl.Vector2.init(-pan.x, -pan.y);
            self.cameraOffset.x += delta.x;
            self.cameraOffset.y += delta.y;
            self.grid.offset.x += delta.x;
            self.grid.offset.y += delta.y;
            self.translateBees(delta);
        }

        const zoom = input.zoomAxis();
        if (zoom != 0) {
            self.grid.zoom(zoom * 2.0 * rl.getFrameTime());
        }

        if (input.plantPressed()) {
            self.tryOpenPlanterAtHover();
        }

        const cycle = input.shoulderCycle();
        if (cycle != 0) ui.action_hud.cycleBuyQty(cycle);

        // Quick buys: one bee per press, mapped by direction/number.
        if (input.quickBuyPressed(.up)) try self.quickBuyBee(.buy_worker_bee);
        if (input.quickBuyPressed(.left)) try self.quickBuyBee(.buy_swift_bee);
        if (input.quickBuyPressed(.right)) try self.quickBuyBee(.buy_efficient_bee);
        if (input.quickBuyPressed(.down)) try self.quickBuyBee(.buy_gardener_bee);

        // Tile snap: over the grid, gentle stick flicks step tile-by-tile
        // (input.zig's step zone), a released stick settles on the tile
        // center, and a hard push flies the cursor freely.
        const hovered = self.grid.getHoveredTile();
        const snapActive = settings.cursorSnap and input.gamepadActive() and !input.pointerInUi() and hovered != null;
        input.setStepMode(snapActive);
        if (snapActive) {
            const tile = hovered.?;
            input.magnetPull(self.tileCenter(tile.x, tile.y));
            if (input.takeStep()) |dir| {
                if (self.stepTarget(tile.x, tile.y, dir)) |center| {
                    input.warpCursor(center);
                }
            }
        }
    }

    /// Screen-space center of a tile's diamond top face.
    fn tileCenter(self: *const @This(), x: i32, y: i32) rl.Vector2 {
        const pos = utils.isoToXY(@floatFromInt(x), @floatFromInt(y), self.grid.tileWidth, self.grid.tileHeight, self.grid.offset.x, self.grid.offset.y, self.grid.scale);
        return rl.Vector2.init(pos.x + 16 * self.grid.scale, pos.y + 8 * self.grid.scale);
    }

    /// Neighbor to step to for a stick push, by explicit intent sectors:
    /// pushes within ~20° of screen-horizontal or -vertical mean the screen
    /// cross (the grid diagonals), and any clearly mixed push means that
    /// quadrant's shallow neighbor (the grid cardinals, which sit only ~27°
    /// off horizontal on screen and are nearly impossible to aim at with a
    /// nearest-angle rule). Out-of-bounds targets fall back to the best
    /// aligned in-bounds neighbor so borders stay forgiving.
    fn stepTarget(self: *const @This(), tx: i32, ty: i32, dir: rl.Vector2) ?rl.Vector2 {
        const deg = std.math.atan2(dir.y, dir.x) * 180.0 / std.math.pi;
        const a = @abs(deg);
        var dx: i32 = 0;
        var dy: i32 = 0;
        if (a <= 20) {
            dx = 1;
            dy = -1; // screen right
        } else if (a >= 160) {
            dx = -1;
            dy = 1; // screen left
        } else if (deg > 0) { // lower half (screen y grows downward)
            if (deg < 70) {
                dx = 1; // down-right shallow
            } else if (deg <= 110) {
                dx = 1;
                dy = 1; // screen down
            } else {
                dy = 1; // down-left shallow
            }
        } else { // upper half
            if (deg > -70) {
                dy = -1; // up-right shallow
            } else if (deg >= -110) {
                dx = -1;
                dy = -1; // screen up
            } else {
                dx = -1; // up-left shallow
            }
        }
        const nx = tx + dx;
        const ny = ty + dy;
        if (nx >= 0 and ny >= 0 and nx < @as(i32, @intCast(self.gridWidth)) and ny < @as(i32, @intCast(self.gridHeight))) {
            return self.tileCenter(nx, ny);
        }
        return self.bestAlignedNeighbor(tx, ty, dir);
    }

    /// The in-bounds neighbor of (tx, ty) whose on-screen direction best
    /// matches `dir` (a normalized stick vector) — comparing in screen space
    /// so the isometric projection is handled for free. Null when nothing
    /// aligns even loosely.
    fn bestAlignedNeighbor(self: *const @This(), tx: i32, ty: i32, dir: rl.Vector2) ?rl.Vector2 {
        const cur = self.tileCenter(tx, ty);
        var best: ?rl.Vector2 = null;
        var bestDot: f32 = 0.35;
        var dy: i32 = -1;
        while (dy <= 1) : (dy += 1) {
            var dx: i32 = -1;
            while (dx <= 1) : (dx += 1) {
                if (dx == 0 and dy == 0) continue;
                const nx = tx + dx;
                const ny = ty + dy;
                if (nx < 0 or ny < 0 or nx >= @as(i32, @intCast(self.gridWidth)) or ny >= @as(i32, @intCast(self.gridHeight))) continue;
                const c = self.tileCenter(nx, ny);
                const vx = c.x - cur.x;
                const vy = c.y - cur.y;
                const len = @sqrt(vx * vx + vy * vy);
                if (len == 0) continue;
                const dot = (vx * dir.x + vy * dir.y) / len;
                if (dot > bestDot) {
                    bestDot = dot;
                    best = c;
                }
            }
        }
        return best;
    }

    /// Buy one bee without opening any UI (d-pad shortcut). Locked types
    /// no-op so the mapping stays stable; the "-cost" popup at the cursor is
    /// the success feedback (same as shop purchases).
    fn quickBuyBee(self: *@This(), buyAction: actions.BuyAction) !void {
        const unlocked = switch (buyAction) {
            .buy_worker_bee => true,
            .buy_swift_bee => self.upgradeTree.hasEffect(.bee_unlock_swift),
            .buy_efficient_bee => self.upgradeTree.hasEffect(.bee_unlock_efficient),
            .buy_gardener_bee => self.upgradeTree.hasEffect(.bee_unlock_gardener),
        };
        if (!unlocked) return;

        var handler = self.createActionHandler();
        const honeyBefore = self.resources.honey;
        const result = try handler.handleBuy(buyAction);
        if (result.beeCountDelta > 0) {
            self.cachedBeeCount += @intCast(result.beeCountDelta);
            try self.spawnSpendFeedback(honeyBefore);
            ui.action_hud.flashSlot(switch (buyAction) {
                .buy_worker_bee => 0,
                .buy_swift_bee => 1,
                .buy_efficient_bee => 2,
                .buy_gardener_bee => 3,
            });
        }
    }

    fn handleMouseClick(self: *@This(), mousePos: rl.Vector2) void {
        const dragDistance = @sqrt((mousePos.x - self.clickStartPos.x) * (mousePos.x - self.clickStartPos.x) +
            (mousePos.y - self.clickStartPos.y) * (mousePos.y - self.clickStartPos.y));

        // Generous threshold so a small hand-wobble during a click still counts
        // as a click, not a camera drag.
        if (dragDistance >= 12.0) return;

        // Rotten flower under the cursor: clear it so the cell can regrow.
        if (self.grid.getHoveredTile()) |tile| {
            if (self.world.getFlowerAtGrid(tile.x, tile.y)) |flowerEntity| {
                if (self.world.getFlowerGrowth(flowerEntity)) |growth| {
                    if (growth.isRotten) {
                        lifespan_system.removeFlower(&self.world, flowerEntity) catch {};
                        self.cachedFlowerCount = self.world.entityToFlowerGrowth.count();
                        return;
                    }
                }
                return; // live flower: nothing to do
            }
            self.tryOpenPlanterAtHover();
        }
    }

    /// Open the plant chooser on the hovered tile if it's an empty meadow
    /// cell (not the hive, not already flowered, inside the grid).
    fn tryOpenPlanterAtHover(self: *@This()) void {
        const tile = self.grid.getHoveredTile() orelse return;
        if (self.world.hasFlowerAtGrid(tile.x, tile.y)) return;
        const centerX = @as(i32, @intCast((self.gridWidth - 1) / 2));
        const centerY = @as(i32, @intCast((self.gridHeight - 1) / 2));
        const inBounds = tile.x >= 0 and tile.y >= 0 and tile.x < @as(i32, @intCast(self.gridWidth)) and tile.y < @as(i32, @intCast(self.gridHeight));
        if (inBounds and !(tile.x == centerX and tile.y == centerY)) {
            self.plantMenu.openAt(tile.x, tile.y);
        }
    }

    fn drawAndHandlePlantMenu(self: *@This()) !void {
        const action = ui.plant_menu.draw(&self.plantMenu, .{
            .screenWidth = self.width,
            .screenHeight = self.height,
            .gridOffset = self.grid.offset,
            .gridScale = self.grid.scale,
            .resources = &self.resources,
            .textures = &self.textures,
        });
        switch (action) {
            .none => {},
            .close => self.plantMenu.open = false,
            .plant => |flower| {
                const cost = switch (flower) {
                    .rose => spawners.FLOWER_COSTS.rose,
                    .tulip => spawners.FLOWER_COSTS.tulip,
                    .dandelion => spawners.FLOWER_COSTS.dandelion,
                };
                const x = self.plantMenu.tileX;
                const y = self.plantMenu.tileY;
                if (!self.world.hasFlowerAtGrid(x, y) and self.resources.spendHoney(cost)) {
                    const honeyBefore = self.resources.honey + cost;
                    _ = try spawners.spawnFlower(&self.world, &self.textures, flower, x, y);
                    _ = try spawners.tryMergeSuperFlower(&self.world, x, y);
                    self.cachedFlowerCount = self.world.entityToFlowerGrowth.count();
                    try self.spawnSpendFeedback(honeyBefore);
                }
                self.plantMenu.open = false;
            },
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

        // Instant Grow: once unlocked, it fires on its own — whenever the
        // cooldown completes, a random still-growing flower blooms instantly.
        if (self.upgradeTree.hasEffect(.growth_boost_unlock) and self.resources.canUseGrowthBoost()) {
            if (self.pickRandomGrowableFlower()) |flowerEntity| {
                var handler = self.createActionHandler();
                handler.instantGrowFlower(flowerEntity);
            }
        }

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
        self.recountBeeTypes();

        if (frameHoneyGain > 0) {
            const centerX: f32 = @floatFromInt((self.gridWidth - 1) / 2);
            const centerY: f32 = @floatFromInt((self.gridHeight - 1) / 2);
            try self.floatingTexts.spawn(centerX, centerY, frameHoneyGain);
            self.audio.playCollect();
        }
        self.floatingTexts.update(deltaTime);
        self.ambient.update(deltaTime, self.width, self.height);

        try self.world.processDestroyQueue();
    }

    pub fn draw(self: *@This()) !void {
        rl.beginDrawing();
        defer rl.endDrawing();
        // The whole frame (world + UI) draws in logical pixels; the camera
        // zooms it up to the real resolution.
        ui_scale.begin();
        defer ui_scale.end();
        defer input.drawCursor();

        rl.clearBackground(theme.CatppuccinMocha.Color.base);

        // Cozy animated sky behind everything.
        self.sky.drawBackground(self.width, self.height);

        self.grid.draw(self.sky.worldTint());

        try render_system.draw(&self.world, self.grid.offset, self.grid.scale, self.sky.worldTint(), self.upgradeTree.level(upgrade_tree.AURA_ID), self.labs.auraReach);

        self.floatingTexts.draw(self.grid.offset, self.grid.scale);

        // Ambient day/night light wash + vignette over the whole meadow.
        self.sky.drawAmbientOverlay(self.width, self.height);

        // Sun/moon on top of the wash so they stay bright and crisp.
        self.sky.drawCelestial(self.width, self.height);

        // Floating pollen dust / fireflies over the light wash so they glow.
        self.ambient.draw(self.sky.nightFactor());

        // Draw HUD (reuses this frame's cached factor)
        const honeyFactor = self.cachedHoneyFactor;
        self.hud.draw(&self.resources, honeyFactor);

        // Draw the floating action HUD (bee cross, tree button, passives)
        const sideCtx = ui.ActionHudContext{
            .screenWidth = self.width,
            .screenHeight = self.height,
            .resources = &self.resources,
            .beeTypeCounts = self.cachedBeeTypeCounts,
            .treeState = &self.upgradeTree,
            .prestige = &self.prestige,
            .labs = &self.labs,
            .textures = &self.textures,
        };
        const sideAction = ui.action_hud.draw(sideCtx);
        if (!self.showPauseMenu and !self.showTree and !self.showPrestigeDialog) {
            switch (sideAction) {
                .none => {},
                .open_tree => {
                    self.showTree = true;
                    ui.tree_view.resetScroll();
                },
                .open_prestige => self.showPrestigeDialog = true,
                .buy => |b| {
                    var handler = self.createActionHandler();
                    const honeyBefore = self.resources.honey;
                    var delta: i32 = 0;
                    // Bulk buy: repeat until the quantity is met or honey runs out.
                    var n: u32 = 0;
                    while (n < b.qty) : (n += 1) {
                        const result = try handler.handleBuy(b.action);
                        if (result.beeCountDelta == 0) break;
                        delta += result.beeCountDelta;
                    }
                    try self.spawnSpendFeedback(honeyBefore);
                    if (delta != 0) {
                        self.cachedBeeCount = @intCast(@as(i64, @intCast(self.cachedBeeCount)) + delta);
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

        // Dev FPS/frametime readout, hidden by default. BT_SHOW_DEBUG enables
        // it. (frameTime is still computed below for metrics.)
        if (self.env.get("BT_SHOW_DEBUG") != null) {
            const fpsX = @as(i32, @intFromFloat(self.width - 130));
            rl.drawFPS(fpsX, 10);
            text.draw(rl.textFormat("%.2f ms", .{rl.getFrameTime() * 1000.0}), fpsX, 30, 20, rl.Color.white);
        }

        if (self.plantMenu.open) try self.drawAndHandlePlantMenu();

        // Screen-space popups (purchase "-cost" feedback) above all UI.
        self.floatingTexts.drawScreen();

        // Draw pause menu
        if (self.showPauseMenu) {
            if (self.showOptions) {
                self.drawAndHandleOptions();
            } else {
                const action = ui.pause_menu.draw(self.width, self.height);
                switch (action) {
                    .continue_game => {
                        self.showPauseMenu = false;
                        self.isPaused = false;
                    },
                    .exit_game => {
                        self.shouldExit = true;
                    },
                    .options => self.showOptions = true,
                    .none => {},
                }
            }
        }

        // Log metrics
        const fps: f32 = @floatFromInt(rl.getFPS());
        self.metrics.log(fps, rl.getFrameTime() * 1000.0, self.cachedBeeCount, self.cachedFlowerCount);
    }

    /// Sweep the whole grid for 2x2 same-type blocks and merge them. Used when
    /// the Super Flowers node is purchased, so existing arrangements pay off
    /// immediately instead of waiting for the next spawn next to them.
    fn mergeExistingSuperBlocks(self: *@This()) !void {
        for (0..self.gridWidth) |i| {
            for (0..self.gridHeight) |j| {
                _ = try spawners.tryMergeSuperFlower(&self.world, @intCast(i), @intCast(j));
            }
        }
    }

    /// Bee positions are screen-space; whenever the world shifts under them
    /// (pan, resize, grid growth) they must be carried by the same delta.
    fn translateBees(self: *@This(), delta: rl.Vector2) void {
        var beeIter = self.world.iterateBees();
        while (beeIter.next()) |entity| {
            if (self.world.getPosition(entity)) |pos| {
                pos.x += delta.x;
                pos.y += delta.y;
            }
        }
    }

    /// Refresh the per-type owned-bee counts shown on the shop cards.
    fn recountBeeTypes(self: *@This()) void {
        self.cachedBeeTypeCounts = .{ 0, 0, 0, 0 };
        var it = self.world.iterateBees();
        while (it.next()) |entity| {
            const ai = self.world.getBeeAI(entity) orelse continue;
            const index: usize = @intFromEnum(ai.beeType);
            if (index < self.cachedBeeTypeCounts.len) self.cachedBeeTypeCounts[index] += 1;
        }
    }

    /// If honey was spent since `honeyBefore` (a purchase just succeeded),
    /// float a red "-cost" up from the cursor so the click visibly landed.
    fn spawnSpendFeedback(self: *@This(), honeyBefore: f32) !void {
        const spent = honeyBefore - self.resources.honey;
        if (spent <= 0) return;
        const mouse = input.pointerPos();
        try self.floatingTexts.spawnScreen(mouse.x, mouse.y - 14, -spent);
    }

    fn createActionHandler(self: *@This()) actions.ActionHandler {
        return actions.ActionHandler{
            .world = &self.world,
            .resources = &self.resources,
            .grid = &self.grid,
            .textures = &self.textures,
        };
    }

    fn getBeehiveHoneyFactor(self: *@This()) f32 {
        var handler = self.createActionHandler();
        return handler.getBeehiveHoneyFactor();
    }

    /// Uniformly random flower that hasn't fully bloomed yet, or null.
    fn pickRandomGrowableFlower(self: *@This()) ?u32 {
        var count: usize = 0;
        var it = self.world.iterateFlowers();
        while (it.next()) |entity| {
            if (self.world.getFlowerGrowth(entity)) |growth| {
                if (growth.state < 4) count += 1;
            }
        }
        if (count == 0) return null;

        var pick = rl.getRandomValue(0, @intCast(count - 1));
        it = self.world.iterateFlowers();
        while (it.next()) |entity| {
            if (self.world.getFlowerGrowth(entity)) |growth| {
                if (growth.state < 4) {
                    if (pick == 0) return entity;
                    pick -= 1;
                }
            }
        }
        return null;
    }

    fn drawAndHandlePrestigeDialog(self: *@This()) !void {
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

        if (widgets.button(rl.Rectangle.init(popupX + 24, btnY, btnW, btnH), locale.tr("Cancel", "Cancelar"))) {
            self.showPrestigeDialog = false;
        }
        const confirmRect = rl.Rectangle.init(popupX + popupW - btnW - 24, btnY, btnW, btnH);
        if (widgets.buttonEx(confirmRect, locale.tr("Confirm", "Confirmar"), .{ .enabled = gain > 0 })) {
            try self.doPrestige(gain);
            self.showPrestigeDialog = false;
        }
    }

    fn doPrestige(self: *@This(), gain: u32) !void {
        self.prestige.resetRun(gain);
        try self.resetRun();
    }

    /// Wipe everything, including prestige, and overwrite the save on disk.
    fn startNewGame(self: *@This()) !void {
        self.prestige = .{};
        try self.resetRun();
        self.hasSavedGame = false;
        self.saveProgress() catch |err| std.debug.print("Could not save new game: {}\n", .{err});
    }

    /// Tear down the world and restore a fresh run (keeps prestige state).
    fn resetRun(self: *@This()) !void {
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
        self.grid.fitToViewport();

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
        spawners.superFlowersUnlocked = false;
        bee_ai_system.gardenerPlantChance = bee_ai_system.GARDENER_BASE_CHANCE;
        bee_ai_system.gardenerCompost = false;

        self.cachedBeeCount = self.world.entityToBeeAI.count();
        self.cachedFlowerCount = self.world.entityToFlowerGrowth.count();
        self.recountBeeTypes();
        self.floatingTexts.items.clearRetainingCapacity();
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
        // The grid→flower registry's integer keys are now stale — rebuild it.
        // (Previously skipped, which left every tile lookup after an expansion
        // off by one diagonal.)
        self.world.rebuildFlowerRegistry();

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
        self.translateBees(.{
            .x = self.grid.offset.x - oldOffset.x,
            .y = self.grid.offset.y - oldOffset.y,
        });

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
        const node = upgrade_tree.findNode(nodeId) orelse return;
        if (!self.upgradeTree.canBuy(node)) return;
        if (!self.resources.spendHoney(self.upgradeTree.nextCost(node))) return;

        switch (node.effect) {
            .honey_factor_mul => {
                var it = self.world.entityToBeehive.keyIterator();
                if (it.next()) |e| {
                    if (self.world.getBeehive(e.*)) |bh| bh.honeyConversionFactor *= node.value;
                }
            },
            // Capacity scales with level so storage keeps pace with honey growth.
            .storage_add => self.resources.honeyCapacity += node.value * std.math.pow(f32, upgrade_tree.STORAGE_CAPACITY_GROWTH, @floatFromInt(self.upgradeTree.level(nodeId))),
            .growth_cd_sub => self.resources.growthBoostMaxCooldown = @max(2.0, self.resources.growthBoostMaxCooldown - node.value),
            .bee_unlock_worker, .bee_unlock_swift, .bee_unlock_efficient, .bee_unlock_gardener => {},
            .gardener_chance => bee_ai_system.gardenerPlantChance = bee_ai_system.gardenerChanceForLevel(self.upgradeTree.level(nodeId) + 1),
            .gardener_compost => bee_ai_system.gardenerCompost = true,
            .grid_expand => try self.expandGrid(),
            // +1 because the level is bumped after this switch.
            .lab_aura => {
                self.labs.auraMul = labs.auraMultiplierForLevel(self.upgradeTree.level(nodeId) + 1);
                self.labs.auraReach = labs.auraReachForLevel(self.upgradeTree.level(upgrade_tree.AURA_REACH_ID));
            },
            .aura_reach => self.labs.auraReach = labs.auraReachForLevel(self.upgradeTree.level(nodeId) + 1),
            .prestige_unlock => self.prestige.hasUnlockedPrestige = true,
            .growth_boost_unlock => {}, // gate checked via hasEffect at usage
            .super_flower_unlock => {
                spawners.superFlowersUnlocked = true;
                // Reward blocks the player already laid out: merge them now.
                try self.mergeExistingSuperBlocks();
            },
        }

        try self.upgradeTree.markPurchased(nodeId);
    }

    fn saveProgress(self: *@This()) !void {
        var data = save.Data{
            .language = @intFromEnum(locale.current()),
            .ui_scale = ui_scale.user(),
            .window_mode = @intFromEnum(settings.windowMode),
            .music_volume = self.audio.musicVolume,
            .fx_volume = self.audio.fxVolume,
            .cursor_snap = settings.cursorSnap,
            .honey = self.resources.honey,
            .honey_capacity = self.resources.honeyCapacity,
            .storage_level = self.resources.storageLevel,
            .honey_per_sec = self.resources.honeyPerSec,
            .growth_cooldown = self.resources.growthBoostCooldown,
            .growth_max_cooldown = self.resources.growthBoostMaxCooldown,
            .growth_level = self.resources.growthBoostLevel,
            .beehive_factor = self.getBeehiveHoneyFactor(),
            .beehive_upgrade_cost = 20, // legacy field, popup upgrade removed
            .grid_width = self.gridWidth,
            .grid_height = self.gridHeight,
            .royal_jelly = self.prestige.royalJelly,
            .this_run_honey = self.prestige.thisRunHoney,
            .prestige_unlocked = self.prestige.hasUnlockedPrestige,
            .aura_multiplier = self.labs.auraMul,
        };
        defer data.deinit(self.allocator);

        var upgrade_it = self.upgradeTree.levels.iterator();
        while (upgrade_it.next()) |entry| {
            const id = entry.key_ptr.*;
            if (id < data.purchased.len and entry.value_ptr.* > 0) {
                data.purchased[id] = true;
                data.levels[id] = entry.value_ptr.*;
            }
        }

        // Aggregate bees per grid cell so the save stays bounded by occupied
        // tiles, not colony size. Grid coords are pan/zoom/window invariant.
        const CellKey = struct { bee_type: u8, x: i32, y: i32 };
        var cells = std.AutoHashMap(CellKey, u32).init(self.allocator);
        defer cells.deinit();

        const margin: f32 = @floatFromInt(BEE_CELL_MARGIN);
        const maxCoord: f32 = @as(f32, @floatFromInt(self.gridWidth)) + margin;
        var bee_it = self.world.iterateBees();
        while (bee_it.next()) |entity| {
            const ai = self.world.getBeeAI(entity) orelse continue;
            const pos = self.world.getPosition(entity) orelse continue;
            const index: usize = @intFromEnum(ai.beeType);
            if (index >= data.bee_counts.len or data.bee_counts[index] >= save.MAX_BEES_PER_TYPE) continue;
            data.bee_counts[index] += 1;
            const gridPos = utils.worldToGrid(pos.toVector2(), self.grid.offset, self.grid.scale);
            // Strays that wandered far off the meadow fold back to its rim.
            const key = CellKey{
                .bee_type = @intCast(index),
                .x = @intFromFloat(@floor(finiteInRange(gridPos.x, -margin, maxCoord, 0))),
                .y = @intFromFloat(@floor(finiteInRange(gridPos.y, -margin, maxCoord, 0))),
            };
            const gop = try cells.getOrPut(key);
            if (!gop.found_existing) gop.value_ptr.* = 0;
            gop.value_ptr.* += 1;
        }
        var cell_it = cells.iterator();
        while (cell_it.next()) |entry| {
            try data.bee_cells.append(self.allocator, .{
                .bee_type = entry.key_ptr.bee_type,
                .x = entry.key_ptr.x,
                .y = entry.key_ptr.y,
                .count = entry.value_ptr.*,
            });
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
                .is_super = growth.isSuper,
                .is_rotten = growth.isRotten,
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
        ui_scale.setUser(finiteInRange(data.ui_scale, 0.6, 2.5, 1.0));
        settings.windowMode = settings.WindowMode.fromInt(data.window_mode);
        self.audio.setMusicVolume(finiteInRange(data.music_volume, 0, 1, 0.7));
        self.audio.setFxVolume(finiteInRange(data.fx_volume, 0, 1, 0.7));
        settings.cursorSnap = data.cursor_snap;

        self.world.deinit();
        self.world = World.init(self.allocator);
        bee_ai_system.resetCaches();
        render_system.resetCaches();

        self.gridWidth = data.grid_width;
        self.gridHeight = data.grid_height;
        self.grid.width = data.grid_width;
        self.grid.height = data.grid_height;
        self.grid.fitToViewport();

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
            // A saved SUPER flower is only its anchor entity; restore its
            // double-size form and 2x2 block ownership (if it still fits).
            if (flower.is_super and
                flower.x + 1 < @as(i32, @intCast(self.gridWidth)) and
                flower.y + 1 < @as(i32, @intCast(self.gridHeight)))
            {
                spawners.applySuperForm(&self.world, entity, flower.x, flower.y);
            }
            if (flower.is_rotten) {
                if (self.world.getFlowerGrowth(entity)) |growth| {
                    if (self.world.getLifespan(entity)) |lifespan| {
                        lifespan_system.rotFlower(&self.world, entity, growth, lifespan);
                    }
                }
            }
        }

        if (data.bee_cells.items.len > 0) {
            // Restore the colony's spatial distribution: each cell's bees are
            // scattered within their saved tile instead of respawning the
            // whole colony in a random pile.
            var restored: usize = 0;
            outer: for (data.bee_cells.items) |cell| {
                const bee_type: components.BeeType = switch (cell.bee_type) {
                    0 => .worker,
                    1 => .swift,
                    2 => .efficient,
                    3 => .gardener,
                    else => continue,
                };
                const maxCoord = @as(i32, @intCast(self.gridWidth)) + BEE_CELL_MARGIN;
                const cellX: f32 = @floatFromInt(std.math.clamp(cell.x, -BEE_CELL_MARGIN, maxCoord));
                const cellY: f32 = @floatFromInt(std.math.clamp(cell.y, -BEE_CELL_MARGIN, maxCoord));
                for (0..cell.count) |_| {
                    if (restored >= save.MAX_BEES) break :outer;
                    restored += 1;
                    const entity = try spawners.spawnBeeWithType(&self.world, &self.grid, &self.textures, bee_type);
                    if (self.world.getPosition(entity)) |pos| {
                        const gx = cellX + @as(f32, @floatFromInt(rl.getRandomValue(0, 99))) / 100.0;
                        const gy = cellY + @as(f32, @floatFromInt(rl.getRandomValue(0, 99))) / 100.0;
                        const screenPos = utils.isoToXY(gx, gy, self.grid.tileWidth, self.grid.tileHeight, self.grid.offset.x, self.grid.offset.y, self.grid.scale);
                        pos.x = screenPos.x;
                        pos.y = screenPos.y;
                    }
                    self.staggerBeeSearch(entity);
                }
            }
        } else {
            // Old saves only stored counts; positions are re-rolled.
            for (data.bee_counts, 0..) |count, index| {
                const bee_type: components.BeeType = switch (index) {
                    0 => .worker,
                    1 => .swift,
                    2 => .efficient,
                    3 => .gardener,
                    else => unreachable,
                };
                for (0..count) |_| {
                    const entity = try spawners.spawnBeeWithType(&self.world, &self.grid, &self.textures, bee_type);
                    self.staggerBeeSearch(entity);
                }
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

        self.upgradeTree.deinit();
        self.upgradeTree = upgrade_tree.State.init(self.allocator);
        for (data.purchased, 0..) |purchased, id| {
            if (!purchased) continue;
            const node = upgrade_tree.findNode(@intCast(id)) orelse continue;
            // Legacy ids are folded into their target's level below.
            var is_legacy = false;
            for (upgrade_tree.LEGACY_LEVEL_MAP) |m| {
                if (m.legacy == id) is_legacy = true;
            }
            if (is_legacy) continue;
            // Old saves only have the "upgrade" flag -> level 1; clamp to max.
            var lvl: u16 = @max(1, data.levels[id]);
            if (node.repeat) |r| {
                if (r.max_level != 0) lvl = @min(lvl, r.max_level);
            } else lvl = 1;
            try self.upgradeTree.setLevel(@intCast(id), lvl);
        }
        // Old saves: "Grid +2 ring" etc. become extra levels on the single node.
        for (upgrade_tree.LEGACY_LEVEL_MAP) |m| {
            if (m.legacy < data.purchased.len and data.purchased[m.legacy] and self.upgradeTree.isPurchased(m.target)) {
                try self.upgradeTree.setLevel(m.target, self.upgradeTree.level(m.target) + 1);
            }
        }

        self.prestige.royalJelly = data.royal_jelly;
        self.prestige.thisRunHoney = finiteAtLeast(data.this_run_honey, 0, 0);
        self.prestige.hasUnlockedPrestige = data.prestige_unlocked or self.upgradeTree.hasEffect(.prestige_unlock);
        spawners.superFlowersUnlocked = self.upgradeTree.hasEffect(.super_flower_unlock);
        bee_ai_system.gardenerPlantChance = bee_ai_system.gardenerChanceForLevel(self.upgradeTree.level(upgrade_tree.GREEN_THUMB_ID));
        bee_ai_system.gardenerCompost = self.upgradeTree.hasEffect(.gardener_compost);
        // Derived from the tree levels (the saved multiplier is legacy).
        self.labs.auraMul = labs.auraMultiplierForLevel(self.upgradeTree.level(upgrade_tree.AURA_ID));
        self.labs.auraReach = if (self.upgradeTree.isPurchased(upgrade_tree.AURA_ID))
            labs.auraReachForLevel(self.upgradeTree.level(upgrade_tree.AURA_REACH_ID))
        else
            0;

        self.cachedBeeCount = self.world.entityToBeeAI.count();
        self.cachedFlowerCount = self.world.entityToFlowerGrowth.count();
        self.recountBeeTypes();
        self.cachedHoneyFactor = self.getBeehiveHoneyFactor();
        self.floatingTexts.items.clearRetainingCapacity();
        self.autosaveTimer = 0;
    }

    /// Randomize a restored bee's first flower search. Loaded bees all start
    /// with no target; at large populations, the whole colony scanning the
    /// flower cache on the same frames is a visible post-load hitch.
    fn staggerBeeSearch(self: *@This(), entity: u32) void {
        if (self.world.getBeeAI(entity)) |ai| {
            ai.searchCooldown = @as(f32, @floatFromInt(rl.getRandomValue(0, 100))) / 100.0;
        }
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
