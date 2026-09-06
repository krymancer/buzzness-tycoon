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

/// One-sentence description of what a tree node does, shown as the hover
/// tooltip in the upgrade tree.
pub fn nodeDesc(id: u16) [:0]const u8 {
    return switch (id) {
        0 => tr("The baseline bee: collects pollen and hauls it to the hive.", "A abelha básica: coleta pólen e leva até a colmeia."),
        1 => tr("Doubles the honey earned per pollen delivery, every level (x32 at Lv 5).", "Dobra o mel ganho por entrega de pólen, a cada nível (x32 no Nv 5)."),
        24 => tr("+25% honey per delivery, every level.", "+25% de mel por entrega, a cada nível."),
        4 => tr("Unlocks the Swift bee: flies twice as fast.", "Libera a abelha Veloz: voa duas vezes mais rápido."),
        5 => tr("Unlocks the Efficient bee: collects double pollen.", "Libera a abelha Eficiente: coleta o dobro de pólen."),
        6 => tr("Unlocks the Gardener bee: plants flowers on empty cells it crosses.", "Libera a abelha Jardineira: planta flores nas células vazias que cruza."),
        26 => tr("+10% gardener planting chance per level.", "+10% de chance de plantio da jardineira por nível."),
        27 => tr("Gardeners clear rotten flowers they fly over, and hunt down the rest.", "Jardineiras limpam flores podres por onde voam e caçam as demais."),
        28 => tr("Idle gardeners seek out empty tiles and plant them.", "Jardineiras ociosas procuram células vazias e as plantam."),
        7 => tr("-1s Instant Grow cooldown per level (floor 2s).", "-1s de recarga do Crescer Instantâneo por nível (mínimo 2s)."),
        10 => tr("Adds a ring of meadow tiles around the grid.", "Adiciona um anel de células ao redor do campo."),
        32 => tr("Unlocks bigger bulk-buy options for bees, up to x1000.", "Desbloqueia opções maiores de compra em massa de abelhas, até x1000."),
        13 => tr("Raises the honey storage cap.", "Aumenta o limite de armazenamento de mel."),
        29 => tr("Flowers mature and regrow pollen 20% faster per level.", "Flores amadurecem e repõem pólen 20% mais rápido por nível."),
        30 => tr("Bees live 20% longer per level; living bees benefit too.", "Abelhas vivem 20% mais por nível; as vivas também ganham."),
        31 => tr("Dying flowers rot 10% less often per level; never at max.", "Flores morrendo apodrecem 10% menos por nível; nunca no máximo."),
        16 => tr("Flowers near the hive yield +25% pollen per level.", "Flores perto da colmeia rendem +25% de pólen por nível."),
        25 => tr("Widens the aura by one tile ring per level.", "Amplia a aura em um anel de células por nível."),
        19 => tr("Unlocks Prestige: reset the run for Royal Jelly and a permanent multiplier.", "Libera o Prestígio: reinicie a partida por Geleia Real e um multiplicador permanente."),
        20 => tr("Unlocks Instant Grow: every few seconds a growing flower blooms on the spot.", "Libera o Crescer Instantâneo: a cada poucos segundos uma flor crescendo desabrocha na hora."),
        21 => tr("2x2 blocks of the same flower merge into an 8x SUPER flower.", "Blocos 2x2 da mesma flor se fundem numa SUPERflor de 8x."),
        33 => tr("Bees make half honey and fly slower at night; each level removes a quarter of the penalty.", "Abelhas produzem metade do mel e voam mais devagar à noite; cada nível remove um quarto da penalidade."),
        34 => tr("All bees fly 15% faster per level.", "Todas as abelhas voam 15% mais rápido por nível."),
        35 => tr("Bees visit one more flower per trip before flying home, per level.", "Abelhas visitam uma flor a mais por viagem antes de voltar, por nível."),
        36 => tr("Worker bees fly and collect 10% better per level.", "Abelhas operárias voam e coletam 10% melhor por nível."),
        37 => tr("Swift bees fly and collect 10% better per level.", "Abelhas velozes voam e coletam 10% melhor por nível."),
        38 => tr("Efficient bees fly and collect 10% better per level.", "Abelhas eficientes voam e coletam 10% melhor por nível."),
        39 => tr("Gardener bees fly and collect 10% better per level.", "Abelhas jardineiras voam e coletam 10% melhor por nível."),
        else => "",
    };
}

pub fn nodeName(id: u16, english: []const u8) []const u8 {
    if (current_language == .english) return english;
    return switch (id) {
        0 => "Abelha Operária",
        1 => "Duplicador de Mel",
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
        24 => "Impulso de Mel",
        25 => "Alcance da Aura",
        26 => "Dedo Verde",
        27 => "Compostagem",
        28 => "Batedoras de Sementes",
        29 => "Solo Fértil",
        30 => "Vitalidade",
        31 => "Flores Resistentes",
        32 => "Compra em Massa",
        33 => "Turno da Noite",
        34 => "Vento de Cauda",
        35 => "Alforjes",
        36 => "Treino: Operária",
        37 => "Treino: Veloz",
        38 => "Treino: Eficiente",
        39 => "Treino: Jardineira",
        else => english,
    };
}
