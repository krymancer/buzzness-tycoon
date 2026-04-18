const std = @import("std");

pub const BURST_DURATION: f32 = 10.0;
pub const BURST_COOLDOWN: f32 = 60.0;
pub const BURST_MUL: f32 = 4.0;
pub const BLOOM_COOLDOWN: f32 = 60.0;
pub const AURA_MUL: f32 = 1.25;

pub const LabState = struct {
    auraMul: f32 = 1.0,
    burstRemaining: f32 = 0,
    burstCooldown: f32 = 0,
    bloomCooldown: f32 = 0,

    pub fn update(self: *@This(), deltaTime: f32) void {
        self.burstRemaining = @max(0, self.burstRemaining - deltaTime);
        self.burstCooldown = @max(0, self.burstCooldown - deltaTime);
        self.bloomCooldown = @max(0, self.bloomCooldown - deltaTime);
    }

    pub fn honeyMultiplier(self: *const @This()) f32 {
        const burstMul: f32 = if (self.burstRemaining > 0) BURST_MUL else 1.0;
        return self.auraMul * burstMul;
    }

    pub fn tryActivateBurst(self: *@This(), unlocked: bool) bool {
        if (!unlocked or self.burstCooldown > 0) return false;
        self.burstRemaining = BURST_DURATION;
        self.burstCooldown = BURST_COOLDOWN;
        return true;
    }

    pub fn tryActivateBloom(self: *@This(), unlocked: bool) bool {
        if (!unlocked or self.bloomCooldown > 0) return false;
        self.bloomCooldown = BLOOM_COOLDOWN;
        return true;
    }
};
