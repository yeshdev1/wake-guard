/// Namespace marker for the `TravelDomain` module — Pure time-zone and travel-policy calculations.
///
/// Feature folder per ADR-003 (single target; boundaries enforced by protocols
/// and tests, not yet by separate compilation units). Real types arrive in
/// later tasks; this keeps the module folder present and gives future code a
/// stable namespace.
enum TravelDomain {}
