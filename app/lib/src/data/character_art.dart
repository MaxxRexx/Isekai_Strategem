import 'dart:math';

/// Full-body cutout art available for the battle screen's spotlight panel,
/// keyed by character id. Only characters with a finished cutout appear
/// here; everyone else falls back to the shared portrait placeholder. Once
/// every character has art, add more entries per id here (e.g. alternate
/// poses/outfits) - [randomCutoutAssetFor] already picks among them.
const Map<String, List<String>> characterCutoutAssets = {
  'vela_ashworth': ['assets/characters/vela_ashworth/cutout.png'],
};

/// Picks one of [characterId]'s available cutout assets, or null if none
/// exist yet. Callers should call this once per battle and cache the
/// result, not once per rebuild, so the same character doesn't flicker
/// between variants mid-battle.
String? randomCutoutAssetFor(String characterId, Random random) {
  final assets = characterCutoutAssets[characterId];
  if (assets == null || assets.isEmpty) return null;
  return assets[random.nextInt(assets.length)];
}
