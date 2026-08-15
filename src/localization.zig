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
        7 => "Crescer -1,5s",
        8 => "Crescer -3s",
        9 => "Crescer -6s",
        10 => "Grade +1 anel",
        11 => "Grade +2 anéis",
        12 => "Grade +3 anéis",
        13 => "Armazém +500",
        14 => "Armazém +1 mil",
        15 => "Armazém +2 mil",
        16 => "Lab: Aura",
        17 => "Lab: Explosão",
        18 => "Lab: Florescer",
        19 => "Prestígio",
        else => english,
    };
}
