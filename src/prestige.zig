const std = @import("std");

const HONEY_PER_JELLY: f32 = 10_000.0;
const MUL_PER_JELLY: f32 = 0.1;

/// Permanent upgrades bought with Royal Jelly in the prestige panel. They
/// survive every run reset. Follows the Cookie Clicker model: the income
/// multiplier comes from lifetime jelly earned, while purchases draw from a
/// separate spendable balance — buying never lowers the multiplier.
pub const ShopItem = enum(u8) {
    /// Multiplies all honey income (x1.1 per level, on top of the jelly multiplier).
    queens_blessing,
    /// More Royal Jelly per prestige (+10% per level).
    jelly_refinery,
    /// Every run starts with an extra meadow ring per level (also expands the
    /// current meadow on purchase).
    royal_meadow,
    /// Every run starts with extra bees per level.
    busy_bees,
    /// Every run starts with Swift, Efficient and Gardener bees unlocked.
    royal_retinue,
    /// One more bulk-buy quantity step per level, on top of the Bulk Order
    /// tree node (x5000 ... x100000 with both maxed). Appended last: shop
    /// levels are saved by enum index.
    wholesale_contract,
};

pub const SHOP_ITEM_COUNT = @typeInfo(ShopItem).@"enum".fields.len;

pub const ShopSpec = struct {
    baseCost: f32,
    costGrowth: f32,
    /// 0 = unlimited.
    maxLevel: u16,

    pub fn costAtLevel(self: ShopSpec, level: u16) f32 {
        return @round(self.baseCost * std.math.pow(f32, self.costGrowth, @floatFromInt(level)));
    }

    pub fn isMaxed(self: ShopSpec, level: u16) bool {
        return self.maxLevel != 0 and level >= self.maxLevel;
    }
};

pub const BLESSING_PER_LEVEL: f32 = 1.1;
pub const REFINERY_PER_LEVEL: f32 = 0.1;
pub const BEES_PER_BUSY_LEVEL: u32 = 8;
/// Wholesale Contract levels: one per quantity step past the tree's x1000.
pub const WHOLESALE_MAX_LEVEL: u16 = 4;

/// Priced against a first prestige of ~500 RJ (the tree's Prestige node
/// sits deep enough that the first run banks a few billion honey): one or
/// two meaningful picks the first time, everything but the Blessing sink
/// within a handful of runs. Blessing's cap keeps its total under u32.
pub fn shopSpec(item: ShopItem) ShopSpec {
    return switch (item) {
        .queens_blessing => .{ .baseCost = 50, .costGrowth = 1.5, .maxLevel = 40 },
        .jelly_refinery => .{ .baseCost = 150, .costGrowth = 2.0, .maxLevel = 10 },
        .royal_meadow => .{ .baseCost = 200, .costGrowth = 2.5, .maxLevel = 12 },
        .busy_bees => .{ .baseCost = 100, .costGrowth = 2.0, .maxLevel = 5 },
        .royal_retinue => .{ .baseCost = 400, .costGrowth = 1.0, .maxLevel = 1 },
        .wholesale_contract => .{ .baseCost = 300, .costGrowth = 2.0, .maxLevel = WHOLESALE_MAX_LEVEL },
    };
}

pub const PrestigeState = struct {
    /// Lifetime Royal Jelly earned; drives the income multiplier.
    royalJelly: u32 = 0,
    /// Jelly spent in the shop; never exceeds royalJelly.
    jellySpent: u32 = 0,
    thisRunHoney: f32 = 0,
    hasUnlockedPrestige: bool = false,
    shopLevels: [SHOP_ITEM_COUNT]u16 = @splat(0),

    pub fn trackHoney(self: *@This(), amount: f32) void {
        self.thisRunHoney += amount;
    }

    pub fn gainFromReset(self: *const @This()) u32 {
        if (self.thisRunHoney < HONEY_PER_JELLY) return 0;
        const base = @sqrt(self.thisRunHoney / HONEY_PER_JELLY);
        const boosted = base * (1.0 + REFINERY_PER_LEVEL * @as(f32, @floatFromInt(self.shopLevel(.jelly_refinery))));
        return @intFromFloat(@min(boosted, @as(f32, @floatFromInt(std.math.maxInt(u32)))));
    }

    /// Multiplier from lifetime jelly alone (what prestige prices scale from).
    pub fn jellyMul(self: *const @This()) f32 {
        return 1.0 + MUL_PER_JELLY * @as(f32, @floatFromInt(self.royalJelly));
    }

    /// Queen's Blessing bonus on top of the jelly multiplier.
    pub fn blessingMul(self: *const @This()) f32 {
        return std.math.pow(f32, BLESSING_PER_LEVEL, @floatFromInt(self.shopLevel(.queens_blessing)));
    }

    pub fn globalMul(self: *const @This()) f32 {
        return self.jellyMul() * self.blessingMul();
    }

    /// Global price multiplier for upgrade-tree nodes and bee purchases.
    /// Square root of the jelly multiplier: each prestige still nets faster
    /// progression overall (net speedup = sqrt(jellyMul)), but prices rise
    /// enough that a run keeps a real pacing curve instead of blowing through
    /// the early tree. Shop bonuses are pure upside and never raise prices.
    pub fn costMul(self: *const @This()) f32 {
        return @sqrt(self.jellyMul());
    }

    pub fn resetRun(self: *@This(), gain: u32) void {
        self.royalJelly +|= gain;
        self.thisRunHoney = 0;
    }

    pub fn availableJelly(self: *const @This()) u32 {
        return self.royalJelly -| self.jellySpent;
    }

    pub fn shopLevel(self: *const @This(), item: ShopItem) u16 {
        return self.shopLevels[@intFromEnum(item)];
    }

    pub fn shopCost(self: *const @This(), item: ShopItem) f32 {
        return shopSpec(item).costAtLevel(self.shopLevel(item));
    }

    pub fn canBuyShop(self: *const @This(), item: ShopItem) bool {
        if (shopSpec(item).isMaxed(self.shopLevel(item))) return false;
        return @as(f32, @floatFromInt(self.availableJelly())) >= self.shopCost(item);
    }

    /// Deduct the cost and raise the level; false when unaffordable/maxed.
    /// Callers apply any immediate world effect themselves.
    pub fn buyShop(self: *@This(), item: ShopItem) bool {
        if (!self.canBuyShop(item)) return false;
        self.jellySpent +|= @intFromFloat(self.shopCost(item));
        self.shopLevels[@intFromEnum(item)] += 1;
        return true;
    }

    /// Clamp loaded state so a hand-edited or truncated save can't yield a
    /// negative balance or over-max levels.
    pub fn sanitize(self: *@This()) void {
        for (&self.shopLevels, 0..) |*lvl, i| {
            const spec = shopSpec(@enumFromInt(i));
            if (spec.maxLevel != 0) lvl.* = @min(lvl.*, spec.maxLevel);
        }
        if (self.jellySpent > self.royalJelly) self.jellySpent = self.royalJelly;
    }
};

test "cost multiplier grows slower than the income multiplier" {
    var p: PrestigeState = .{};
    try std.testing.expectEqual(@as(f32, 1.0), p.costMul());

    p.royalJelly = 10; // income x2.0
    try std.testing.expectApproxEqRel(@sqrt(@as(f32, 2.0)), p.costMul(), 1e-5);
    try std.testing.expect(p.costMul() < p.globalMul());
}

test "shop purchases spend from the balance without touching the multiplier" {
    var p: PrestigeState = .{ .royalJelly = 100 };
    const mulBefore = p.jellyMul();
    const costBefore = p.costMul();

    try std.testing.expect(p.canBuyShop(.queens_blessing));
    try std.testing.expect(p.buyShop(.queens_blessing));
    try std.testing.expectEqual(@as(u32, 50), p.availableJelly());
    try std.testing.expectEqual(@as(u16, 1), p.shopLevel(.queens_blessing));
    try std.testing.expectEqual(mulBefore, p.jellyMul());
    try std.testing.expectEqual(costBefore, p.costMul());
    try std.testing.expectApproxEqRel(mulBefore * BLESSING_PER_LEVEL, p.globalMul(), 1e-5);
    // Next level costs more.
    try std.testing.expectApproxEqRel(@as(f32, 75), p.shopCost(.queens_blessing), 1e-5);
}

test "shop refuses unaffordable and maxed items" {
    var p: PrestigeState = .{ .royalJelly = 400 };
    try std.testing.expect(p.buyShop(.royal_retinue));
    try std.testing.expect(!p.canBuyShop(.royal_retinue)); // maxed (one-shot)
    try std.testing.expect(!p.buyShop(.royal_meadow)); // 0 left
    try std.testing.expectEqual(@as(u32, 0), p.availableJelly());
}

test "a typical first prestige affords a real choice but not the whole shop" {
    var p: PrestigeState = .{ .thisRunHoney = 2.5e9 }; // ~500 RJ
    const gain = p.gainFromReset();
    try std.testing.expect(gain >= 450 and gain <= 550);
    var total: f32 = 0;
    inline for (@typeInfo(ShopItem).@"enum".fields) |f| {
        total += shopSpec(@enumFromInt(f.value)).costAtLevel(0);
    }
    try std.testing.expect(total > @as(f32, @floatFromInt(gain)));
    try std.testing.expect(shopSpec(.royal_retinue).costAtLevel(0) <= @as(f32, @floatFromInt(gain)));
}

test "blessing total cost stays inside a u32 balance" {
    const spec = shopSpec(.queens_blessing);
    var total: f64 = 0;
    for (0..spec.maxLevel) |lvl| total += spec.costAtLevel(@intCast(lvl));
    try std.testing.expect(total < @as(f64, @floatFromInt(std.math.maxInt(u32))));
}

test "jelly refinery boosts the prestige gain" {
    var p: PrestigeState = .{ .thisRunHoney = 1_000_000 }; // sqrt(100) = 10
    try std.testing.expectEqual(@as(u32, 10), p.gainFromReset());
    p.shopLevels[@intFromEnum(ShopItem.jelly_refinery)] = 5;
    try std.testing.expectEqual(@as(u32, 15), p.gainFromReset());
}

test "sanitize clamps over-max levels and overspent balances" {
    var p: PrestigeState = .{ .royalJelly = 5, .jellySpent = 50 };
    p.shopLevels[@intFromEnum(ShopItem.royal_retinue)] = 9;
    p.sanitize();
    try std.testing.expectEqual(@as(u32, 5), p.jellySpent);
    try std.testing.expectEqual(@as(u16, 1), p.shopLevel(.royal_retinue));
}
