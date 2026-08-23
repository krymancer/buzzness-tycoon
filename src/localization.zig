const std = @import("std");

pub const Language = enum(u8) {
    english,
    portuguese_br,
};

var current_language: Language = .english;

pub fn current() Language {
    return current_language;
}

pub fn set(language: Language) void {
    current_language = language;
}

pub fn toggle() void {
    current_language = switch (current_language) {
        .english => .portuguese_br,
        .portuguese_br => .english,
    };
}

pub fn detectFromEnvironment(env: *std.process.Environ.Map) void {
    const value = env.get("BT_LANG") orelse
        env.get("LC_ALL") orelse
        env.get("LC_MESSAGES") orelse
        env.get("LANGUAGE") orelse
        env.get("LANG") orelse return;

    if (startsWithIgnoreCase(value, "pt")) current_language = .portuguese_br;
}

fn startsWithIgnoreCase(value: []const u8, prefix: []const u8) bool {
    if (value.len < prefix.len) return false;
    for (value[0..prefix.len], prefix) |a, b| {
        if (std.ascii.toLower(a) != std.ascii.toLower(b)) return false;
    }
    return true;
}

/// Select localized, null-terminated UI copy without allocating.
pub fn tr(english: [:0]const u8, portuguese: [:0]const u8) [:0]const u8 {
    return switch (current_language) {
        .english => english,
        .portuguese_br => portuguese,
    };
}

pub fn languageButton() [:0]const u8 {
    return tr("Language: English", "Idioma: Português (BR)");
}

pub fn nodeName(id: u16, english: []const u8) []const u8 {
    if (current_language == .english) return english;
    return switch (id) {
        0 => "Abelha Operária",
        1 => "Mel x2",
        2 => "Mel x4",
        3 => "Mel x8",
        4 => "Abelha Veloz",
        5 => "Abelha Eficiente",
        6 => "Abelha Jardineira",
        7 => "Velocidade de Crescer",
        10 => "Anel da Grade",
        13 => "Armazém",
        16 => "Lab: Aura",
        19 => "Prestígio",
        20 => "Crescer Instantâneo",
        21 => "Superflores",
        22 => "Mel x16",
        23 => "Mel x32",
        24 => "Impulso de Mel",
        25 => "Alcance da Aura",
        26 => "Dedo Verde",
        27 => "Compostagem",
        else => english,
    };
}
