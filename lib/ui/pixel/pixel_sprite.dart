/// Deterministic pixel-art sprites drawn from 16x16 character grids.
///
/// The final art ships as flat PNGs in `assets/pixel/` (`docs/07` §11.3). Until
/// those files land, this painter renders the same keys from palette colours so
/// every screen has its sprite at the right size with `FilterQuality.none`
/// semantics (hard edges, integer cells, no smoothing). When the PNGs arrive a
/// `PixelSprite` can serve them without changing a single screen.
library;

import 'package:flutter/widgets.dart';

import 'pixel_canvas.dart';
import 'pixel_theme.dart';

/// Character -> palette colour. `.` is transparent.
const Map<String, Color> _palette = <String, Color>{
  'k': PixelPalette.ink,
  'o': PixelPalette.inkSoft,
  'a': PixelPalette.adobo,
  'y': PixelPalette.cream,
  'Y': PixelPalette.creamDark,
  'c': PixelPalette.clay,
  'd': PixelPalette.clayDark,
  'n': PixelPalette.banig,
  'g': PixelPalette.calamansi,
  'G': PixelPalette.calamansiDark,
  'm': PixelPalette.amber,
  'M': PixelPalette.amberDark,
  'r': PixelPalette.rust,
  'R': PixelPalette.rustDark,
  's': PixelPalette.slate,
  'w': PixelPalette.white,
};

/// The sprite library. Keys match the manifest names used by content
/// (`dish_*`, `eq_*`, `variant_*`, `step_*`, `tab_*`) plus UI glyphs.
abstract final class PixelSprites {
  static const List<String> _steam = <String>[
    '...k...k...k....',
    '..k...k...k.....',
  ];

  static final Map<String, List<String>> _patterns = <String, List<String>>{
    // A clay pot with dark adobo contents and steam.
    'dish_chicken_adobo': <String>[
      ..._steam,
      '................',
      '..kkkkkkkkkkkk..',
      '.kwwwwwwwwwwwwk.',
      '.kwccccccccccwk.',
      '.kwcddddddddcwk.',
      '.kwcddddddddcwk.',
      '.kwccccccccccwk.',
      '.kwccccccccccwk.',
      '.kddddddddddddk.',
      '..kkkkkkkkkkkk..',
      '...kk......kk...',
      '..kkk......kkk..',
      '................',
    ],
    // A clay pot of garlic fried rice: cream grains on amber.
    'dish_sinangag': <String>[
      ..._steam,
      '................',
      '..kkkkkkkkkkkk..',
      '.kwwwwwwwwwwwwk.',
      '.kwccccccccccwk.',
      '.kwcmwmwnmwmmwk.',
      '.kwcmmnwmwmmcwk.',
      '.kwcmmmmmmwmmwk.',
      '.kwcwmwnmmmmcwk.',
      '.kddddddddddddk.',
      '..kkkkkkkkkkkk..',
      '...kk......kk...',
      '..kkk......kkk..',
      '................',
    ],
    // The pork belly pot: golden body, rust crackling stripes.
    'dish_crispy_pork_belly': <String>[
      '................',
      '..kkkkkkkkkkkk..',
      '.kwwwwnnnnnnnnk.',
      '.kwnnnnnnnnnnnk.',
      '.kwnnnrrrrrrnnk.',
      '.kwnrrrrrrrrrnk.',
      '.kwnnnnnnnnnnnk.',
      '.kwnrrrrrrrrnnk.',
      '.kwnrrrrrrrrrnk.',
      '.knnnnnnnnnnnnk.',
      '..kkkkkkkkkkkk..',
      '...kk......kk...',
      '..kkk......kkk..',
      '................',
      '................',
      '................',
    ],
    // Pan-fry method: a pan with a handle.
    'variant_panfry': <String>[
      '................',
      '................',
      '................',
      '................',
      '.kkkkkkkkkk.....',
      'kwwwwwwwwwwk....',
      'kwkkkkkkkkkkkk..',
      'kwkssssssskwkk..',
      'kwkssssssskwkk..',
      'kwwwwwwwwwwk....',
      '.kkkkkkkkkk.....',
      '................',
      '................',
      '................',
      '................',
      '................',
    ],
    // Air-fry method: a basket with slats.
    'variant_airfry': <String>[
      '................',
      '..kkkkkkkkkkkk..',
      '.kwwwwwwwwwwwwk.',
      '.kwkkkkkkkkkkwk.',
      '.kwksssssssskwk.',
      '.kwsksssssskswk.',
      '.kwsskssssksswk.',
      '.kwsssksskssswk.',
      '.kwsssskksssswk.',
      '.kwsssssssssswk.',
      '.kwkkkkkkkkkkwk.',
      '..kkkkkkkkkkkk..',
      '...k........k...',
      '................',
      '................',
      '................',
    ],
    // Appliances
    'eq_stovetop': <String>[
      '................',
      '..kkkkkkkkkkkk..',
      '.kwwwwwwwwwwwwk.',
      '.kwkkkwwwwkkkwwk',
      '.kwkkkwwwwkkkwwk',
      '.kwwwwwwwwwwwwk.',
      '.kwrrrrwwrrrrwk.',
      '.kwwwwwwwwwwwwk.',
      '.kwkkkrrrrkkkwwk',
      '.kwkkkrrrrkkkwwk',
      '.kwwwwwwwwwwwwk.',
      '..kkkkkkkkkkkk..',
      '...kk......kk...',
      '..kkk......kkk..',
      '................',
      '................',
    ],
    'eq_air_fryer': <String>[
      '................',
      '....kkkkkkkk....',
      '...kwwwwwwwwk...',
      '...kwkkkkkkwk...',
      '...kwksssskwk...',
      '...kwkkkkkkwk...',
      '..kkwwwwwwwwkk..',
      '..kwwwwwwwwwwk..',
      '..kwkkkkkkkkwk..',
      '..kwksssssskwk..',
      '..kwkkkkkkkkwk..',
      '..kkkkkkkkkkkk..',
      '...kk......kk...',
      '..kkk......kkk..',
      '................',
      '................',
    ],
    'eq_oven': <String>[
      '................',
      '..kkkkkkkkkkkk..',
      '.kwwwwwwwwwwwwk.',
      '.kwkkkkkkkkkkwk.',
      '.kwkssssssssswk.',
      '.kwkssssssssswk.',
      '.kwkssssssssswk.',
      '.kwkkkkkkkkkkwk.',
      '.kwwwwwwwwwwwwk.',
      '.kwkkwwwwwwrrwk.',
      '.kwkkwwwwwwrrwk.',
      '..kkkkkkkkkkkk..',
      '...k........k...',
      '................',
      '................',
      '................',
    ],
    'eq_grill': <String>[
      '................',
      '..kkkkkkkkkkkk..',
      '.kwwwwwwwwwwwwk.',
      '.kwkkkkkkkkkkwk.',
      '.kwkssskssksswk.',
      '.kwkssskssksswk.',
      '.kwkssskssksswk.',
      '.kwkssskssksswk.',
      '.kwwwwwwwwwwwwk.',
      '..kkkkkkkkkkkk..',
      '...k........k...',
      '..kk........kk..',
      '..kk........kk..',
      '................',
      '................',
      '................',
    ],
    'eq_pressure_cooker': <String>[
      '................',
      '......kkkk......',
      '.....kwwwwk.....',
      '..kkkkkkkkkkkk..',
      '.kwwwwwwwwwwwwk.',
      '.kwkkkkkkkkkkwk.',
      '.kwksssssssskwk.',
      '.kwksssssssskwk.',
      '.kwksssssssskwk.',
      '.kwkkkkkkkkkkwk.',
      '..kkkkkkkkkkkk..',
      '...kk......kk...',
      '..kkk......kkk..',
      '................',
      '................',
      '................',
    ],
    // Ingredient still (shared by every catalog ingredient).
    'ing_default': <String>[
      '................',
      '................',
      '......kk........',
      '.....kggk.......',
      '....kggggk......',
      '...kggggggk.....',
      '...kggkgggk.....',
      '...kggggggk.....',
      '....kggggk......',
      '.....kkkk.......',
      '....kkkkkk......',
      '...knnnnnnk.....',
      '...knnnnnnk.....',
      '....kkkkkk......',
      '................',
      '................',
    ],
    // Step scene glyphs, one per (kind, appliance).
    'step_prep_none': <String>[
      '................',
      '................',
      '..........kk....',
      '.........kwwk...',
      '........kwwk....',
      '.......kwwk.....',
      '......kwwk......',
      '.....kwwk.......',
      '....kwwk........',
      '...kwwk.........',
      '...kwk..........',
      '....kk..........',
      '................',
      '................',
      '................',
      '................',
    ],
    'step_heat_stovetop': <String>[
      '................',
      '................',
      '................',
      '.....r...r......',
      '....rr..rr......',
      '.....m..m.......',
      '....mm.mm.......',
      '.....m.m........',
      '....mmm.mm......',
      '..kkkkkkkkkkkk..',
      '.kwwwwwwwwwwwwk.',
      '.kddddddddddddk.',
      '..kkkkkkkkkkkk..',
      '................',
      '................',
      '................',
    ],
    'step_cook_stovetop': <String>[
      '................',
      '................',
      '................',
      '....r....r......',
      '...rr...rr......',
      '....m...m.......',
      '...mm..mm.......',
      '....m..m........',
      '..kkkkkkkkkkkk..',
      '.kwwwwwwwwwwwwk.',
      '.kwccccccccccwk.',
      '.kwcddddddddcwk.',
      '.kwccccccccccwk.',
      '.kddddddddddddk.',
      '..kkkkkkkkkkkk..',
      '................',
    ],
    'step_cook_air_fryer': <String>[
      '................',
      '...kkkkkkkkkk...',
      '..kwwwwwwwwwwk..',
      '..kwkkkkkkkkwk..',
      '..kwksssssskwk..',
      '..kwksssssskwk..',
      '..kwkkkkkkkkwk..',
      '..kwwwwwwwwwwk..',
      '...kkkkkkkkkk...',
      '.....nnnnnn.....',
      '....nnnnnnnn....',
      '.....kkkkkk.....',
      '................',
      '................',
      '................',
      '................',
    ],
    'step_wait_stovetop': <String>[
      '................',
      '......kkkk......',
      '.....kwwwwk.....',
      '....kwkkkkwk....',
      '....kwk..kwk....',
      '....kwk..kwk....',
      '....kwk..kwk....',
      '....kwkkkkwk....',
      '.....kwwwwk.....',
      '......kkkk......',
      '...kkkkkkkkkk...',
      '...knnnnnnnnk...',
      '...kkkkkkkkkk...',
      '................',
      '................',
      '................',
    ],
    'step_finish_none': <String>[
      '................',
      '................',
      '......kkkk......',
      '.....kwwwwk.....',
      '....kwwwwwwk....',
      '...kkkkkkkkkk...',
      '....kwwwwwwk....',
      '...kwwwwwwwwk...',
      '..kwwnnnnnnwwk..',
      '..kwnnnnnnnnwk..',
      '...kwnnnnnnwk...',
      '....kkkkkkkk....',
      '................',
      '................',
      '................',
      '................',
    ],
    // Tab bar glyphs.
    'tab_cook': <String>[
      '................',
      '................',
      '....kkkkkkkk....',
      '...kwwwwwwwwk...',
      '...kwccccccwk...',
      '...kwcddddcwk...',
      '...kwccccccwk...',
      '...kwwwwwwwwk...',
      '....kkkkkkkk....',
      '.....k....k.....',
      '................',
      '................',
      '................',
      '................',
      '................',
      '................',
    ],
    'tab_recipes': <String>[
      '................',
      '..kkkkkkkkkkkk..',
      '..kwwwwwwwwwwk..',
      '..kwkkkwkkkkwk..',
      '..kwwwwwwwwwwk..',
      '..kwkkkwkkkkwk..',
      '..kwwwwwwwwwwk..',
      '..kwkkkwkkkkwk..',
      '..kwwwwwwwwwwk..',
      '..kkkkkkkkkkkk..',
      '................',
      '................',
      '................',
      '................',
      '................',
      '................',
    ],
    'tab_stock': <String>[
      '................',
      '..kkkkkkkkkkkk..',
      '..kwwwwwwwwwwk..',
      '..kwknnnnnnkwk..',
      '..kwwwwwwwwwwk..',
      '..kwknnnnnnkwk..',
      '..kwwwwwwwwwwk..',
      '..kwkkkkkkkkwk..',
      '..kwwwwwwwwwwk..',
      '..kkkkkkkkkkkk..',
      '................',
      '................',
      '................',
      '................',
      '................',
      '................',
    ],
    'tab_history': <String>[
      '................',
      '.....kkkkkk.....',
      '....kwwwwwwk....',
      '...kwkkkkkkwk...',
      '...kwk....kwk...',
      '...kwk.kk.kwk...',
      '...kwk.k..kwk...',
      '...kwk.kkkkwk...',
      '...kwkkkkkkwk...',
      '....kwwwwwwk....',
      '.....kkkkkk.....',
      '................',
      '................',
      '................',
      '................',
      '................',
    ],
    // App-bar glyphs.
    'ui_gear': <String>[
      '................',
      '....kk..kk......',
      '...kwwkkwwk.....',
      '..kkwwwwwwkk....',
      '.kwwkwwwwkwwk...',
      '.kwwwkkkkwwwk...',
      '..kkwwwwwwkk....',
      '..kwwwwwwwwk....',
      '..kkwwwwwwkk....',
      '.kwwwkkkkwwwk...',
      '.kwwkwwwwkwwk...',
      '..kkwwwwwwkk....',
      '...kwwkkwwk.....',
      '....kk..kk......',
      '................',
      '................',
    ],
    'ui_back': <String>[
      '................',
      '................',
      '......kk........',
      '.....kwwk.......',
      '....kwwk........',
      '...kwwk.........',
      '..kwwkkkkkkk....',
      '..kwwkkkkkkk....',
      '...kwwk.........',
      '....kwwk........',
      '.....kwwk.......',
      '......kk........',
      '................',
      '................',
      '................',
      '................',
    ],
  };

  /// The 16x16 grid for [key], padded to 16 columns.
  ///
  /// Unknown keys fall back to the ingredient still so a future content key
  /// never renders an empty hole. Rows are padded (never truncated) so a
  /// short line cannot shift the art.
  static List<String> grid(String key) {
    final raw = _patterns[key] ?? _patterns['ing_default']!;
    return <String>[for (final row in raw) row.padRight(16, '.')];
  }

  /// Raw authored rows, for the art test. Not padded.
  static List<String> rawRows(String key) =>
      List<String>.unmodifiable(_patterns[key] ?? const <String>[]);

  static bool hasSprite(String key) => _patterns.containsKey(key);

  /// Every authored key; used by the sprite test to stay 16x16.
  static Iterable<String> get keys => _patterns.keys;
}

/// One 16x16 sprite rendered at [artUnits] art units (integer-scaled edges).
class PixelSprite extends StatelessWidget {
  const PixelSprite({
    super.key,
    required this.spriteKey,
    this.artUnits = 16,
    this.semanticLabel,
  });

  final String spriteKey;
  final double artUnits;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scale = PixelScaleProvider.of(context);
    final size = scale.au(artUnits);
    final sprite = SizedBox.square(
      dimension: size,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _SpritePainter(grid: PixelSprites.grid(spriteKey)),
        ),
      ),
    );
    if (semanticLabel == null) {
      return ExcludeSemantics(child: sprite);
    }
    return Semantics(image: true, label: semanticLabel, child: sprite);
  }
}

class _SpritePainter extends CustomPainter {
  const _SpritePainter({required this.grid});

  final List<String> grid;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 16;
    final paint = Paint()..isAntiAlias = false;
    for (var row = 0; row < grid.length; row++) {
      final line = grid[row];
      for (var column = 0; column < line.length; column++) {
        final color = _palette[line[column]];
        if (color == null) {
          continue;
        }
        paint.color = color;
        canvas.drawRect(
          Rect.fromLTWH(column * cell, row * cell, cell, cell),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_SpritePainter oldDelegate) => false;
}
