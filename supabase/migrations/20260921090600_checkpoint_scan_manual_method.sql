-- Sebetsa Domain 13 — a guard's phone may not have a working camera/QR
-- reader (a real, common field condition, not an edge case — brief §14/§18
-- "poor GPS/network... older Android phones"). scan_checkpoint() already
-- accepts a raw checkpoint code string regardless of how it was obtained;
-- the only gap was that checkpoint_scan_type had no value for "the guard
-- typed the code in by hand" distinct from an actual QR/NFC read, which
-- would have mislabeled every manual-entry scan as a QR scan in the
-- evidence trail. Purely additive — enum values can only be added, never
-- removed, so this cannot regress an existing 'qr'/'nfc' row.

alter type public.checkpoint_scan_type add value 'manual';
