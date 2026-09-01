//! Central tunable config for idle pivot.
//! Add new constants here as systems migrate off hardcoded values.

/// Bees age and die (#69); Bee Vitality stretches their lifespan. Flip on
/// only for benchmarks where a shrinking colony would skew the numbers.
pub const bees_immortal: bool = false;
pub const honey_cap_enabled: bool = true;
pub const starting_honey: f32 = 100.0;
