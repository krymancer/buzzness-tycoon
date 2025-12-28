const rl = @import("raylib");
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
    ui: UI,

    cameraOffset: rl.Vector2,
    isDragging: bool,
    lastMousePos: rl.Vector2,

    beehiveUpgradeCost: f32,
    cachedBeeCount: usize,
    cachedFlowerCount: usize,

    metrics: Metrics,

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
                    try world.addFlowerGrowth(flowerEntity, components.FlowerGrowth.init());
                    try world.addLifespan(flowerEntity, components.Lifespan.init(@floatFromInt(rl.getRandomValue(60, 120))));
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
        if (rl.isKeyPressed(rl.KeyboardKey.enter) and rl.isKeyDown(rl.KeyboardKey.left_alt)) {
            rl.toggleFullscreen();
        }

        const mousePos = rl.getMousePosition();

        if (rl.isMouseButtonPressed(rl.MouseButton.left)) {
            self.isDragging = true;
            self.lastMousePos = mousePos;
        }

        if (rl.isMouseButtonReleased(rl.MouseButton.left)) {
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

        // Log metrics
        const fps: f32 = @floatFromInt(rl.getFPS());
        self.metrics.log(fps, frameTime, self.cachedBeeCount, self.cachedFlowerCount);
    }
};
