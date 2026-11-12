/// Colours and Material themes of the app: the two palettes of the design
/// (warm orange, taken from Jonathan Ong's jacket), in dark and light.
library;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../data/model.dart';

/// The design tokens that have no [ColorScheme] slot.
@immutable
class OngColors extends ThemeExtension<OngColors> {
  /// Creates the tokens.
  const OngColors({
    required this.on3,
    required this.mark,
    required this.brand,
    required this.onBrand,
    required this.thumbnail,
    required this.live,
  });

  /// Tertiary text: metadata, counts, icons of secondary importance.
  final Color on3;

  /// Background of a search hit.
  final Color mark;

  /// The brand orange: "Watch" buttons, the user's own name, avatar ring.
  final Color brand;

  /// Text and icons on [brand]: above 6:1 in both themes, enough for small
  /// text.
  final Color onBrand;

  /// Placeholder behind a thumbnail.
  final Color thumbnail;

  /// The "live" dot of the About tab: red, above 5:1 on the surfaces of its
  /// theme.
  final Color live;

  static const dark = OngColors(
    on3: Color(0xFF9A897D),
    mark: Color(0xFF7A4A00),
    brand: Color(0xFFFF7A1A),
    onBrand: Color(0xFF2B1200),
    thumbnail: Color(0xFF2E2721),
    live: Color(0xFFFF4D4D),
  );

  static const light = OngColors(
    on3: Color(0xFF84736A),
    mark: Color(0xFFFFD9A8),
    brand: Color(0xFFF4721F),
    onBrand: Color(0xFF2B1200),
    thumbnail: Color(0xFFF0E1D6),
    live: Color(0xFFD11A1A),
  );

  /// The tokens of the current theme.
  static OngColors of(BuildContext context) => Theme.of(context).extension<OngColors>()!;

  @override
  OngColors copyWith({Color? on3, Color? mark, Color? brand, Color? onBrand, Color? thumbnail, Color? live}) =>
      OngColors(
        on3: on3 ?? this.on3,
        mark: mark ?? this.mark,
        brand: brand ?? this.brand,
        onBrand: onBrand ?? this.onBrand,
        thumbnail: thumbnail ?? this.thumbnail,
        live: live ?? this.live,
      );

  @override
  OngColors lerp(OngColors? other, double t) {
    if (other == null) return this;
    return OngColors(
      on3: Color.lerp(on3, other.on3, t)!,
      mark: Color.lerp(mark, other.mark, t)!,
      brand: Color.lerp(brand, other.brand, t)!,
      onBrand: Color.lerp(onBrand, other.onBrand, t)!,
      thumbnail: Color.lerp(thumbnail, other.thumbnail, t)!,
      live: Color.lerp(live, other.live, t)!,
    );
  }
}

/// The dark palette of the design.
const ColorScheme darkScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFFFFB37A),
  onPrimary: Color(0xFF4A2000),
  primaryContainer: Color(0xFF6B3200),
  onPrimaryContainer: Color(0xFFFFDCC4),
  secondary: Color(0xFFE5BFA9),
  onSecondary: Color(0xFF422B1D),
  secondaryContainer: Color(0xFF57402E),
  onSecondaryContainer: Color(0xFFFDDCC5),
  tertiary: Color(0xFFFF7A1A),
  onTertiary: Color(0xFF2B1200),
  error: Color(0xFFFFB4AB),
  onError: Color(0xFF690005),
  surface: Color(0xFF15110E),
  onSurface: Color(0xFFF1E2D7),
  onSurfaceVariant: Color(0xFFCBB9AC),
  surfaceContainerLowest: Color(0xFF100C0A),
  surfaceContainerLow: Color(0xFF1C1713),
  surfaceContainer: Color(0xFF241E19),
  surfaceContainerHigh: Color(0xFF2E2721),
  surfaceContainerHighest: Color(0xFF3A322B),
  outline: Color(0xFF8A796D),
  outlineVariant: Color(0xFF3A3029),
  inverseSurface: Color(0xFFF1E2D7),
  onInverseSurface: Color(0xFF15110E),
  inversePrimary: Color(0xFF9A4600),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
  surfaceTint: Color(0x00000000),
);

/// The light palette of the design.
const ColorScheme lightScheme = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFF9A4600),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFFFFDCC4),
  onPrimaryContainer: Color(0xFF6A3100),
  secondary: Color(0xFF765848),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFFBDCC6),
  onSecondaryContainer: Color(0xFF2C1708),
  tertiary: Color(0xFFF4721F),
  onTertiary: Color(0xFF2B1200),
  error: Color(0xFFBA1A1A),
  onError: Color(0xFFFFFFFF),
  surface: Color(0xFFFFF8F4),
  onSurface: Color(0xFF211A15),
  onSurfaceVariant: Color(0xFF54443A),
  surfaceContainerLowest: Color(0xFFFFFFFF),
  surfaceContainerLow: Color(0xFFFBF0E8),
  surfaceContainer: Color(0xFFF6E9DF),
  surfaceContainerHigh: Color(0xFFF0E1D6),
  surfaceContainerHighest: Color(0xFFE9D8CC),
  outline: Color(0xFF85746A),
  outlineVariant: Color(0xFFE4D3C7),
  inverseSurface: Color(0xFF211A15),
  onInverseSurface: Color(0xFFFFF8F4),
  inversePrimary: Color(0xFFFFB37A),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
  surfaceTint: Color(0x00000000),
);

/// Genre colours, the same in both themes ([Genre.other] is neutral).
const Map<Genre, Color> genreColors = {
  Genre.other: Color(0xFF9A897D),
  Genre.popular: Color(0xFFF2A65A),
  Genre.gameOst: Color(0xFF5BC08A),
  Genre.filmTv: Color(0xFF6CA8F0),
  Genre.anime: Color(0xFFF07AA8),
  Genre.disney: Color(0xFFB48CF2),
  Genre.classical: Color(0xFFD9B44A),
  Genre.musicals: Color(0xFFE8705F),
  Genre.jazz: Color(0xFF4FC3C8),
  Genre.ongriginal: Color(0xFFFF6B2C),
  Genre.christmas: Color(0xFF7BC96F),
  Genre.hymns: Color(0xFF9FB3C8),
  Genre.meme: Color(0xFFC7D36F),
  Genre.traditional: Color(0xFFB8A58F),
};

const _noSpacing = TextStyle(letterSpacing: 0);

/// The app theme for [brightness].
ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = dark ? darkScheme : lightScheme;
  final ong = dark ? OngColors.dark : OngColors.light;
  // The design gives its sizes once for every platform (40 px buttons, 32 px
  // chips): without the standard density, Windows and desktop browsers would
  // shrink every control by 4 to 8 px (a "Watch" button lower than the round
  // buttons beside it).
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, visualDensity: VisualDensity.standard);
  final text = base.textTheme;
  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    canvasColor: scheme.surface,
    extensions: [ong],
    dividerColor: scheme.outlineVariant,
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      backgroundColor: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      indicatorColor: scheme.secondaryContainer,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: states.contains(WidgetState.selected) ? scheme.onSurface : scheme.onSurfaceVariant,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 24,
          color: states.contains(WidgetState.selected) ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
        ),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainer,
      modalBackgroundColor: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: scheme.outline.withValues(alpha: 0.6),
      dragHandleSize: const Size(32, 4),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      modalBarrierColor: Colors.black.withValues(alpha: dark ? 0.66 : 0.44),
      constraints: const BoxConstraints(maxWidth: 640),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.transparent,
      selectedColor: scheme.secondaryContainer,
      // a selected chip keeps an invisible border: without it the chip would be
      // 2 px narrower and its neighbours would shift when it is toggled
      side: WidgetStateBorderSide.resolveWith(
        (states) =>
            BorderSide(color: states.contains(WidgetState.selected) ? Colors.transparent : scheme.outlineVariant),
      ),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
      iconTheme: IconThemeData(size: 16, color: scheme.onSurfaceVariant),
      // with the 8 px around the label: the 12 px of the design inside its 1 px border
      padding: const EdgeInsets.symmetric(horizontal: 4),
      labelPadding: const EdgeInsets.symmetric(horizontal: 8),
      showCheckmark: false,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        side: WidgetStatePropertyAll(BorderSide(color: scheme.outline)),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? scheme.secondaryContainer : Colors.transparent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? scheme.onSecondaryContainer : scheme.onSurface,
        ),
        textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: scheme.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: scheme.outline),
      ),
      hintStyle: TextStyle(color: ong.on3),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: TextStyle(color: scheme.onInverseSurface, fontSize: 14),
      behavior: SnackBarBehavior.floating,
    ),
    dialogTheme: DialogThemeData(backgroundColor: scheme.surfaceContainerHigh, surfaceTintColor: Colors.transparent),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(scheme.onSurfaceVariant.withValues(alpha: 0.5)),
      radius: const Radius.circular(4),
    ),
    // the design uses the font's own spacing, not Material's tracking
    textTheme: text
        .merge(
          const TextTheme(
            displayLarge: _noSpacing,
            displayMedium: _noSpacing,
            displaySmall: _noSpacing,
            headlineLarge: _noSpacing,
            headlineMedium: _noSpacing,
            headlineSmall: _noSpacing,
            titleLarge: _noSpacing,
            titleMedium: _noSpacing,
            titleSmall: _noSpacing,
            bodyLarge: _noSpacing,
            bodyMedium: _noSpacing,
            bodySmall: _noSpacing,
            labelLarge: _noSpacing,
            labelMedium: _noSpacing,
            labelSmall: _noSpacing,
          ),
        )
        .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface),
  );
}

/// Status and navigation bar style for a theme: transparent bars (edge to
/// edge) with icons readable on [ThemeData.colorScheme].
SystemUiOverlayStyle systemBarsStyle(ThemeData theme) {
  final dark = theme.brightness == Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
    statusBarBrightness: dark ? Brightness.dark : Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
    systemNavigationBarContrastEnforced: false,
  );
}
