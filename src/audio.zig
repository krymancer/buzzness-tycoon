const rl = @import("raylib");
const std = @import("std");

/// Procedurally-synthesized cozy audio. No sample assets: a small set of
/// gentle ambient music-box pieces (soft drones + pentatonic bells) that
/// rotate with a short pause between them, a gathering chime that plays when
/// bees deliver honey, and a rising fanfare for prestige. Everything degrades
/// gracefully if there is no audio device (headless / no server) — `ready`
/// gates all playback.
pub const Audio = struct {
    const SAMPLE_RATE: u32 = 44100;

    /// Baseline mix levels the channel sliders scale (0..1 each).
    const MUSIC_BASE: f32 = 0.32;
    const FX_BASE: f32 = 0.28;
    /// Silence between pieces so the rotation breathes.
    const TRACK_GAP: f32 = 2.5;

    ready: bool,
    tracks: [TRACKS.len]rl.Sound,
    current: usize,
    /// Pause remaining before the next piece starts (after one ends).
    gapLeft: f32,
    chime: rl.Sound,
    fanfare: rl.Sound,
    chimeCooldown: f32,
    chimeIndex: usize,
    muted: bool,
    /// Channel volumes the player chose (0..1); mute is applied on top.
    musicVolume: f32,
    fxVolume: f32,

    pub fn init(allocator: std.mem.Allocator) Audio {
        rl.initAudioDevice();
        var self: Audio = .{
            .ready = rl.isAudioDeviceReady(),
            .tracks = undefined,
            .current = 0,
            .gapLeft = 0,
            .chime = undefined,
            .fanfare = undefined,
            .chimeCooldown = 0,
            .chimeIndex = 0,
            .muted = false,
            .musicVolume = 0.7,
            .fxVolume = 0.7,
        };
        if (!self.ready) return self;

        var loaded: usize = 0;
        errdefer_unload: {
            for (TRACKS, 0..) |spec, i| {
                self.tracks[i] = buildTrack(allocator, spec) catch break :errdefer_unload;
                loaded += 1;
            }
            self.chime = buildChime(allocator) catch break :errdefer_unload;
            self.fanfare = buildFanfare(allocator) catch {
                rl.unloadSound(self.chime);
                break :errdefer_unload;
            };
            self.applyVolume();
            // Start on a random piece so launches don't always open the same way.
            self.current = @intCast(rl.getRandomValue(0, @as(i32, @intCast(TRACKS.len)) - 1));
            rl.playSound(self.tracks[self.current]);
            return self;
        }
        for (self.tracks[0..loaded]) |t| rl.unloadSound(t);
        self.ready = false;
        return self;
    }

    pub fn deinit(self: *Audio) void {
        if (self.ready) {
            for (self.tracks) |t| rl.unloadSound(t);
            rl.unloadSound(self.chime);
            rl.unloadSound(self.fanfare);
        }
        if (rl.isAudioDeviceReady()) rl.closeAudioDevice();
    }

    pub fn toggleMute(self: *Audio) void {
        self.muted = !self.muted;
        self.applyVolume();
    }

    pub fn setMusicVolume(self: *Audio, v: f32) void {
        self.musicVolume = std.math.clamp(v, 0.0, 1.0);
        self.applyVolume();
    }

    pub fn setFxVolume(self: *Audio, v: f32) void {
        self.fxVolume = std.math.clamp(v, 0.0, 1.0);
        self.applyVolume();
    }

    /// Mute cuts the master bus so both channels silence together and their
    /// slider values survive unmuting untouched.
    fn applyVolume(self: *Audio) void {
        rl.setMasterVolume(if (self.muted) 0.0 else 1.0);
        if (!self.ready) return;
        for (self.tracks) |t| rl.setSoundVolume(t, MUSIC_BASE * self.musicVolume);
        rl.setSoundVolume(self.chime, FX_BASE * self.fxVolume);
        rl.setSoundVolume(self.fanfare, FX_BASE * 1.3 * self.fxVolume);
    }

    pub fn update(self: *Audio, dt: f32) void {
        if (!self.ready) return;
        if (self.chimeCooldown > 0) self.chimeCooldown -= dt;
        if (rl.isSoundPlaying(self.tracks[self.current])) return;
        // The piece ended: rest, then move on to a different one.
        if (self.gapLeft == 0) {
            self.gapLeft = TRACK_GAP;
            return;
        }
        self.gapLeft = @max(0, self.gapLeft - dt);
        if (self.gapLeft > 0) return;
        if (TRACKS.len > 1) {
            const step: usize = @intCast(rl.getRandomValue(1, @as(i32, @intCast(TRACKS.len)) - 1));
            self.current = (self.current + step) % TRACKS.len;
        }
        rl.playSound(self.tracks[self.current]);
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

    /// Bright high bell for a Royal Shop purchase (bypasses the throttle).
    pub fn playShopBuy(self: *Audio) void {
        if (!self.ready) return;
        rl.setSoundPitch(self.chime, 2.0);
        rl.playSound(self.chime);
        self.chimeCooldown = 0.3;
    }

    /// Rising arpeggio when the player ascends.
    pub fn playPrestige(self: *Audio) void {
        if (!self.ready) return;
        rl.playSound(self.fanfare);
    }

    // ---- pieces -------------------------------------------------------------

    const Note = struct { start: f32, note: usize, amp: f32 };
    const Drone = struct { freq: f32, amp: f32 };

    const TrackSpec = struct {
        duration: f32,
        scale: [8]f32,
        drones: [3]Drone,
        /// Tremolo rate on the drone bed (Hz).
        tremolo: f32,
        /// Bell decay time; longer reads dreamier.
        decay: f32,
        melody: []const Note,
    };

    const A_MIN_PENT = [8]f32{ 220.0, 261.63, 293.66, 329.63, 392.0, 440.0, 523.25, 587.33 };
    const C_MAJ_PENT = [8]f32{ 261.63, 293.66, 329.63, 392.0, 440.0, 523.25, 587.33, 659.25 };
    const D_MIN_PENT = [8]f32{ 293.66, 349.23, 392.0, 440.0, 523.25, 587.33, 698.46, 783.99 };
    const G_MAJ_PENT = [8]f32{ 196.0, 220.0, 246.94, 293.66, 329.63, 392.0, 440.0, 493.88 };

    const TRACKS = [_]TrackSpec{
        // "Meadow": the original loop — warm A-minor bed, sparse bells.
        .{
            .duration = 16.0,
            .scale = A_MIN_PENT,
            .drones = .{ .{ .freq = 110.0, .amp = 0.16 }, .{ .freq = 164.81, .amp = 0.11 }, .{ .freq = 220.02, .amp = 0.06 } },
            .tremolo = 0.08,
            .decay = 2.2,
            .melody = &[_]Note{
                .{ .start = 0.5, .note = 5, .amp = 0.22 },
                .{ .start = 2.5, .note = 4, .amp = 0.18 },
                .{ .start = 4.0, .note = 6, .amp = 0.20 },
                .{ .start = 6.0, .note = 3, .amp = 0.17 },
                .{ .start = 8.0, .note = 5, .amp = 0.22 },
                .{ .start = 10.0, .note = 7, .amp = 0.19 },
                .{ .start = 11.5, .note = 4, .amp = 0.16 },
                .{ .start = 13.0, .note = 2, .amp = 0.18 },
                .{ .start = 14.5, .note = 5, .amp = 0.15 },
            },
        },
        // "Sunny": brighter C-major bed with a busier, skipping melody.
        .{
            .duration = 20.0,
            .scale = C_MAJ_PENT,
            .drones = .{ .{ .freq = 130.81, .amp = 0.14 }, .{ .freq = 196.0, .amp = 0.10 }, .{ .freq = 329.63, .amp = 0.04 } },
            .tremolo = 0.12,
            .decay = 1.6,
            .melody = &[_]Note{
                .{ .start = 0.5, .note = 5, .amp = 0.20 },
                .{ .start = 1.0, .note = 4, .amp = 0.15 },
                .{ .start = 1.5, .note = 5, .amp = 0.17 },
                .{ .start = 2.5, .note = 6, .amp = 0.19 },
                .{ .start = 3.5, .note = 4, .amp = 0.15 },
                .{ .start = 4.0, .note = 3, .amp = 0.16 },
                .{ .start = 5.0, .note = 5, .amp = 0.18 },
                .{ .start = 5.5, .note = 7, .amp = 0.16 },
                .{ .start = 6.0, .note = 6, .amp = 0.17 },
                .{ .start = 7.0, .note = 5, .amp = 0.19 },
                .{ .start = 8.0, .note = 2, .amp = 0.15 },
                .{ .start = 8.5, .note = 3, .amp = 0.14 },
                .{ .start = 9.0, .note = 4, .amp = 0.16 },
                .{ .start = 10.0, .note = 5, .amp = 0.20 },
                .{ .start = 11.0, .note = 6, .amp = 0.17 },
                .{ .start = 11.5, .note = 7, .amp = 0.15 },
                .{ .start = 12.0, .note = 5, .amp = 0.18 },
                .{ .start = 13.0, .note = 4, .amp = 0.16 },
                .{ .start = 14.0, .note = 3, .amp = 0.15 },
                .{ .start = 14.5, .note = 2, .amp = 0.13 },
                .{ .start = 15.0, .note = 4, .amp = 0.16 },
                .{ .start = 16.0, .note = 5, .amp = 0.19 },
                .{ .start = 17.0, .note = 6, .amp = 0.16 },
                .{ .start = 17.5, .note = 4, .amp = 0.14 },
                .{ .start = 18.0, .note = 5, .amp = 0.17 },
            },
        },
        // "Dusk": low D-minor drone, very sparse long bells — the lullaby.
        .{
            .duration = 24.0,
            .scale = D_MIN_PENT,
            .drones = .{ .{ .freq = 73.42, .amp = 0.15 }, .{ .freq = 110.0, .amp = 0.12 }, .{ .freq = 146.83, .amp = 0.07 } },
            .tremolo = 0.05,
            .decay = 3.4,
            .melody = &[_]Note{
                .{ .start = 1.0, .note = 3, .amp = 0.19 },
                .{ .start = 4.0, .note = 5, .amp = 0.17 },
                .{ .start = 6.5, .note = 4, .amp = 0.16 },
                .{ .start = 9.0, .note = 2, .amp = 0.18 },
                .{ .start = 12.0, .note = 3, .amp = 0.17 },
                .{ .start = 15.0, .note = 6, .amp = 0.16 },
                .{ .start = 17.5, .note = 5, .amp = 0.15 },
                .{ .start = 20.0, .note = 4, .amp = 0.16 },
                .{ .start = 22.0, .note = 3, .amp = 0.13 },
            },
        },
        // "Waltz": G-major in three — a low root then two lighter bells per bar.
        .{
            .duration = 18.0,
            .scale = G_MAJ_PENT,
            .drones = .{ .{ .freq = 98.0, .amp = 0.15 }, .{ .freq = 146.83, .amp = 0.10 }, .{ .freq = 196.02, .amp = 0.05 } },
            .tremolo = 0.1,
            .decay = 1.8,
            .melody = &waltzMelody(),
        },
    };

    /// Twelve 1.5s bars: root on the downbeat, two higher bells after.
    fn waltzMelody() [36]Note {
        const bars = [12][3]usize{
            .{ 0, 3, 5 }, .{ 0, 4, 6 }, .{ 1, 4, 6 }, .{ 1, 3, 5 },
            .{ 3, 5, 7 }, .{ 3, 5, 6 }, .{ 1, 4, 7 }, .{ 0, 3, 5 },
            .{ 0, 4, 6 }, .{ 2, 4, 6 }, .{ 1, 3, 5 }, .{ 0, 3, 5 },
        };
        var out: [36]Note = undefined;
        for (bars, 0..) |bar, b| {
            const t0: f32 = @as(f32, @floatFromInt(b)) * 1.5;
            const soft: f32 = if (b == bars.len - 1) 0.7 else 1.0;
            out[b * 3 + 0] = .{ .start = t0, .note = bar[0], .amp = 0.17 * soft };
            out[b * 3 + 1] = .{ .start = t0 + 0.5, .note = bar[1], .amp = 0.13 * soft };
            out[b * 3 + 2] = .{ .start = t0 + 1.0, .note = bar[2], .amp = 0.15 * soft };
        }
        return out;
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

    /// Render one piece: detuned drones under a bell melody. The envelope
    /// fades both ends to zero so the piece starts and ends silent (no click).
    /// Returns a Sound; the temp sample buffer is freed after load because
    /// raylib copies the wave into its own audio buffer.
    fn buildTrack(allocator: std.mem.Allocator, spec: TrackSpec) !rl.Sound {
        const n: usize = @intFromFloat(spec.duration * @as(f32, @floatFromInt(SAMPLE_RATE)));
        const buf = try allocator.alloc(i16, n);
        defer allocator.free(buf);
        const acc = try allocator.alloc(f32, n);
        defer allocator.free(acc);
        @memset(acc, 0);

        const sr: f32 = @floatFromInt(SAMPLE_RATE);

        // Drone bed with a slow tremolo.
        for (0..n) |i| {
            const t = @as(f32, @floatFromInt(i)) / sr;
            const trem = 0.85 + 0.15 * @sin(t * std.math.tau * spec.tremolo);
            var s: f32 = 0;
            for (spec.drones) |d| s += @sin(t * std.math.tau * d.freq) * d.amp;
            acc[i] += s * trem;
        }

        for (spec.melody) |m| {
            addBell(acc, m.start, spec.scale[m.note], m.amp, spec.decay, sr);
        }

        applyLoopFade(acc, sr, 0.6);
        floatToI16(acc, buf);

        const wave = waveFromSamples(buf);
        return rl.loadSoundFromWave(wave);
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

    /// Prestige fanfare: a quick rising A-major arpeggio that lands on a
    /// shimmering high chord.
    fn buildFanfare(allocator: std.mem.Allocator) !rl.Sound {
        const dur_s: f32 = 2.4;
        const n: usize = @intFromFloat(dur_s * @as(f32, @floatFromInt(SAMPLE_RATE)));
        const buf = try allocator.alloc(i16, n);
        defer allocator.free(buf);
        const acc = try allocator.alloc(f32, n);
        defer allocator.free(acc);
        @memset(acc, 0);

        const sr: f32 = @floatFromInt(SAMPLE_RATE);
        const run = [_]struct { t: f32, f: f32 }{
            .{ .t = 0.0, .f = 440.0 }, // A4
            .{ .t = 0.12, .f = 554.37 }, // C#5
            .{ .t = 0.24, .f = 659.25 }, // E5
            .{ .t = 0.36, .f = 880.0 }, // A5
        };
        for (run) |r| addBell(acc, r.t, r.f, 0.32, 1.0, sr);
        // Landing chord, held.
        addBell(acc, 0.55, 880.0, 0.28, 2.2, sr);
        addBell(acc, 0.55, 1108.73, 0.22, 2.2, sr);
        addBell(acc, 0.55, 1318.51, 0.20, 2.2, sr);
        applyLoopFade(acc, sr, 0.05);
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
