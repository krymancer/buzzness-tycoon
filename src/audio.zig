const rl = @import("raylib");
const std = @import("std");

/// Procedurally-synthesized cozy audio. No sample assets: a gentle ambient
/// music-box loop (soft drone + pentatonic bells) and a gathering chime that
/// plays when bees deliver honey. Everything degrades gracefully if there is
/// no audio device (headless / no server) — `ready` gates all playback.
pub const Audio = struct {
    const SAMPLE_RATE: u32 = 44100;
    const A_MIN_PENTATONIC = [_]f32{ 220.0, 261.63, 293.66, 329.63, 392.0, 440.0, 523.25, 587.33 };

    ready: bool,
    music: rl.Sound,
    chime: rl.Sound,
    chimeCooldown: f32,
    chimeIndex: usize,
    muted: bool,
    /// Master volume the player chose (0..1); mute is applied on top.
    volume: f32,

    pub fn init(allocator: std.mem.Allocator) Audio {
        rl.initAudioDevice();
        var self: Audio = .{
            .ready = rl.isAudioDeviceReady(),
            .music = undefined,
            .chime = undefined,
            .chimeCooldown = 0,
            .chimeIndex = 0,
            .muted = false,
            .volume = 0.7,
        };
        if (!self.ready) return self;

        rl.setMasterVolume(0.7);
        self.music = buildMusic(allocator) catch {
            self.ready = false;
            return self;
        };
        self.chime = buildChime(allocator) catch {
            rl.unloadSound(self.music);
            self.ready = false;
            return self;
        };
        rl.setSoundVolume(self.music, 0.32);
        rl.setSoundVolume(self.chime, 0.28);
        rl.playSound(self.music);
        return self;
    }

    pub fn deinit(self: *Audio) void {
        if (self.ready) {
            rl.unloadSound(self.music);
            rl.unloadSound(self.chime);
        }
        if (rl.isAudioDeviceReady()) rl.closeAudioDevice();
    }

    pub fn toggleMute(self: *Audio) void {
        self.muted = !self.muted;
        self.applyVolume();
    }

    pub fn setVolume(self: *Audio, v: f32) void {
        self.volume = std.math.clamp(v, 0.0, 1.0);
        self.applyVolume();
    }

    fn applyVolume(self: *Audio) void {
        rl.setMasterVolume(if (self.muted) 0.0 else self.volume);
    }

    pub fn update(self: *Audio, dt: f32) void {
        if (!self.ready) return;
        // Loop the ambient bed by relaunching it once it finishes.
        if (!rl.isSoundPlaying(self.music)) rl.playSound(self.music);
        if (self.chimeCooldown > 0) self.chimeCooldown -= dt;
    }

    /// Soft bell when honey is delivered. Throttled and pitch-cycled through a
    /// pentatonic scale so a busy hive sounds like wind chimes, not a machine gun.
    pub fn playCollect(self: *Audio) void {
        if (!self.ready or self.chimeCooldown > 0) return;
        const ratios = [_]f32{ 1.0, 1.2, 1.5, 1.8, 2.0 };
        rl.setSoundPitch(self.chime, ratios[self.chimeIndex % ratios.len]);
        rl.playSound(self.chime);
        self.chimeIndex +%= 1;
        self.chimeCooldown = 0.16;
    }

    // ---- synthesis ----------------------------------------------------------

    fn waveFromSamples(samples: []i16) rl.Wave {
        return .{
            .frameCount = @intCast(samples.len),
            .sampleRate = SAMPLE_RATE,
            .sampleSize = 16,
            .channels = 1,
            .data = @ptrCast(samples.ptr),
        };
    }

    /// A ~16s ambient loop: two low detuned drones under a sparse pentatonic
    /// bell melody. Envelope fades both ends to zero so the loop point is silent
    /// (no click). Returns a Sound; the temp sample buffer is freed after load
    /// because raylib copies the wave into its own audio buffer.
    fn buildMusic(allocator: std.mem.Allocator) !rl.Sound {
        const dur_s: f32 = 16.0;
        const n: usize = @intFromFloat(dur_s * @as(f32, @floatFromInt(SAMPLE_RATE)));
        const buf = try allocator.alloc(i16, n);
        defer allocator.free(buf);
        const acc = try allocator.alloc(f32, n);
        defer allocator.free(acc);
        @memset(acc, 0);

        const sr: f32 = @floatFromInt(SAMPLE_RATE);

        // Low drone: A2 + E3, slow tremolo — the warm "bed".
        for (0..n) |i| {
            const t = @as(f32, @floatFromInt(i)) / sr;
            const trem = 0.85 + 0.15 * @sin(t * std.math.tau * 0.08);
            var s: f32 = 0;
            s += @sin(t * std.math.tau * 110.0) * 0.16;
            s += @sin(t * std.math.tau * 164.81) * 0.11;
            s += @sin(t * std.math.tau * 220.02) * 0.06; // gentle detune shimmer
            acc[i] += s * trem;
        }

        // Sparse bell melody over the loop. Each note is a decaying sine pair
        // (fundamental + octave) for a soft music-box timbre.
        const melody = [_]struct { start: f32, note: usize, amp: f32 }{
            .{ .start = 0.5, .note = 5, .amp = 0.22 },
            .{ .start = 2.5, .note = 4, .amp = 0.18 },
            .{ .start = 4.0, .note = 6, .amp = 0.20 },
            .{ .start = 6.0, .note = 3, .amp = 0.17 },
            .{ .start = 8.0, .note = 5, .amp = 0.22 },
            .{ .start = 10.0, .note = 7, .amp = 0.19 },
            .{ .start = 11.5, .note = 4, .amp = 0.16 },
            .{ .start = 13.0, .note = 2, .amp = 0.18 },
            .{ .start = 14.5, .note = 5, .amp = 0.15 },
        };
        for (melody) |m| {
            addBell(acc, m.start, A_MIN_PENTATONIC[m.note], m.amp, 2.2, sr);
        }

        // Global fade in/out so the loop seam is silent.
        applyLoopFade(acc, sr, 0.6);
        floatToI16(acc, buf);

        const wave = waveFromSamples(buf);
        const sound = rl.loadSoundFromWave(wave);
        return sound;
    }

    /// A single short pentatonic bell — used for honey pickups, retuned per play.
    fn buildChime(allocator: std.mem.Allocator) !rl.Sound {
        const dur_s: f32 = 0.6;
        const n: usize = @intFromFloat(dur_s * @as(f32, @floatFromInt(SAMPLE_RATE)));
        const buf = try allocator.alloc(i16, n);
        defer allocator.free(buf);
        const acc = try allocator.alloc(f32, n);
        defer allocator.free(acc);
        @memset(acc, 0);

        const sr: f32 = @floatFromInt(SAMPLE_RATE);
        addBell(acc, 0.0, 523.25, 0.5, 0.5, sr); // C5 base; pitch-shifted at play
        floatToI16(acc, buf);

        const wave = waveFromSamples(buf);
        return rl.loadSoundFromWave(wave);
    }

    /// Add a decaying sine bell (fundamental + soft octave) into `acc` at `start`.
    fn addBell(acc: []f32, start: f32, freq: f32, amp: f32, decay_s: f32, sr: f32) void {
        const startIdx: usize = @intFromFloat(start * sr);
        if (startIdx >= acc.len) return;
        var i: usize = startIdx;
        while (i < acc.len) : (i += 1) {
            const t = @as(f32, @floatFromInt(i - startIdx)) / sr;
            const env = std.math.exp(-t / (decay_s * 0.35));
            if (env < 0.001) break;
            const s = (@sin(t * std.math.tau * freq) * 0.7 + @sin(t * std.math.tau * freq * 2.0) * 0.3);
            acc[i] += s * env * amp;
        }
    }

    fn applyLoopFade(acc: []f32, sr: f32, fade_s: f32) void {
        const fn_: usize = @intFromFloat(fade_s * sr);
        const n = acc.len;
        for (0..@min(fn_, n)) |i| {
            const g = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(fn_));
            acc[i] *= g;
            acc[n - 1 - i] *= g;
        }
    }

    fn floatToI16(acc: []const f32, buf: []i16) void {
        for (acc, 0..) |v, i| {
            const clamped = std.math.clamp(v, -1.0, 1.0);
            buf[i] = @intFromFloat(clamped * 32000.0);
        }
    }
};
