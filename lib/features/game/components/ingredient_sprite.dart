import 'dart:ui' as ui;
import 'package:flame/flame.dart';
import 'package:flutter/painting.dart';
import '../../../core/widgets/glass_visual.dart';
import '../../../data/models/ingredient.dart';

/// Flame stores cached images keyed by filename relative to its
/// "assets/images/" prefix, while every assetPath in this project is the
/// full path — this strips the matching prefix back off.
String _stripAssetPrefix(String path) {
  const prefix = 'assets/images/';
  return path.startsWith(prefix) ? path.substring(prefix.length) : path;
}

/// The key [ingredient]'s art is cached under in Flame's image cache
/// ([Flame.images], loaded by [preloadIngredientArt]) — see
/// [_stripAssetPrefix].
String? _imageCacheKey(Ingredient ingredient) {
  final path = ingredient.assetPath;
  if (path == null) return null;
  return _stripAssetPrefix(path);
}

/// Loads every image at [assetPaths] into Flame's image cache up front —
/// the general form of [preloadIngredientArt], for art that isn't tied
/// to an [Ingredient] (cocktail glamour shots, say). Loads each
/// independently so one bad asset can't take the rest down with it; see
/// [preloadIngredientArt] for why.
Future<void> preloadImageAssets(List<String> assetPaths) async {
  final keys = assetPaths.map(_stripAssetPrefix).toSet();
  await Future.wait(
    keys.map((key) async {
      try {
        await Flame.images.load(key);
      } catch (_) {
        // Soft failure — paintImageAsset() reports back that it has
        // nothing to draw for any key not found in the cache.
      }
    }),
  );
}

/// Paints the image at [assetPath] into [size] (BoxFit.contain,
/// centered) if it's been preloaded, and reports whether it did —
/// callers fall back to their own placeholder when it returns false,
/// same spirit as [paintIngredient]'s GlassPainter fallback but without
/// assuming there's an [Ingredient] to draw a glass shape for.
bool paintImageAsset(ui.Canvas canvas, String assetPath, Size size) {
  final key = _stripAssetPrefix(assetPath);
  final image = Flame.images.containsKey(key) ? Flame.images.fromCache(key) : null;
  if (image == null) return false;
  final srcSize = Size(image.width.toDouble(), image.height.toDouble());
  final fitted = applyBoxFit(BoxFit.contain, srcSize, size);
  final destRect = Alignment.center.inscribe(fitted.destination, Offset.zero & size);
  canvas.drawImageRect(image, Offset.zero & srcSize, destRect, Paint());
  return true;
}

/// Loads every ingredient's real art into Flame's (global) image cache
/// up front, so [paintIngredient] never has to fall back to the
/// code-drawn glass for a throw or a settled glass — only for an
/// ingredient that genuinely has no [Ingredient.assetPath] yet.
///
/// Loads each image independently (not one [Images.loadAll] call): that
/// method's underlying `Future.wait` fails the whole batch the moment any
/// single image errors (a transient network hiccup, a decode issue on
/// web), which would otherwise take down MixolocoGame's entire onLoad —
/// one bad asset should just fall back to the code-drawn glass for that
/// ingredient, not break the game.
Future<void> preloadIngredientArt(List<Ingredient> ingredients) async {
  final keys = {for (final i in ingredients) ?_imageCacheKey(i)};
  await Future.wait(
    keys.map((key) async {
      try {
        await Flame.images.load(key);
      } catch (_) {
        // Soft failure — paintIngredient() falls back to GlassPainter for
        // any key not found in the cache.
      }
    }),
  );
}

/// How much bigger than its own physics circle an ingredient is drawn.
/// The source art (a photo of a glass, a leaf, a bottle) almost never
/// fills its whole bounding square edge-to-edge, so drawing at exactly
/// `radius * 2` leaves a visible gap between two items whose physics
/// circles are genuinely touching. Padding the render size (not the
/// physics radius itself) closes that gap visually without changing how
/// items actually collide or merge.
const kIngredientVisualPad = 1.28;

/// The square [paintIngredient] should be drawn into for a body of
/// physics [radius], centered on the body — see [kIngredientVisualPad].
Size physicsVisualSize(double radius) => Size.square(radius * 2 * kIngredientVisualPad);

/// Paints [ingredient] into [size] on [canvas] — the real PNG art (same
/// asset the "up next" tray shows via GlassVisual) when it's been
/// preloaded, else the code-drawn [GlassPainter] fallback. Shared by
/// every Flame glass component so the table matches the tray instead of
/// only ever showing the placeholder art.
void paintIngredient(ui.Canvas canvas, Ingredient ingredient, Size size) {
  final key = _imageCacheKey(ingredient);
  final image = key != null && Flame.images.containsKey(key) ? Flame.images.fromCache(key) : null;
  if (image != null) {
    final srcSize = Size(image.width.toDouble(), image.height.toDouble());
    // Some photos are naturally tall/narrow and read as smaller than
    // rounder ones once fit into the same square box — displayScale
    // compensates, growing the fitted rect around the same center rather
    // than changing the caller's own row/lane layout size.
    final fitted = applyBoxFit(BoxFit.contain, srcSize, size * ingredient.displayScale);
    // displayScaleX stretches width only, on top of the uniform fit above
    // — see its doc comment on Ingredient for why a tall narrow glass
    // needs this in addition to (not instead of) displayScale.
    final destSize = ingredient.displayScaleX == 1.0
        ? fitted.destination
        : Size(fitted.destination.width * ingredient.displayScaleX, fitted.destination.height);
    final destRect = Alignment.center.inscribe(destSize, Offset.zero & size);
    canvas.drawImageRect(image, Offset.zero & srcSize, destRect, Paint());
    return;
  }
  GlassPainter(shape: ingredient.shape, liquidColor: ingredient.color).paint(canvas, size);
}
