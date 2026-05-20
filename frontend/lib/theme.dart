part of 'main.dart';

const _themePreferenceKey = 'healthy_t_theme_mode';
final ValueNotifier<ThemeMode> healthyTThemeMode = ValueNotifier(
  ThemeMode.light,
);

bool healthyTIsLightMode(BuildContext context) =>
    Theme.of(context).brightness == Brightness.light;

Color healthyTPrimaryText(BuildContext context) => healthyTIsLightMode(context)
    ? const Color(0xFF111315)
    : const Color(0xFFFFFFFF);

Color healthyTSecondaryText(BuildContext context) =>
    healthyTIsLightMode(context)
    ? const Color(0xFF636A72)
    : const Color(0xFFD4DAE1);

List<Color> healthyTPageGradient(BuildContext context) =>
    healthyTIsLightMode(context)
    ? const [Color(0xFFE9EDF1), Color(0xFFDDE4EA), Color(0xFFD2DBE3)]
    : const [Color(0xFF07090B), Color(0xFF030405), Color(0xFF000000)];

Color healthyTGlassBase(BuildContext context) => healthyTIsLightMode(context)
    ? const Color(0xFFF5F7F9)
    : const Color(0xFF101317);

Color healthyTGlassBorder(BuildContext context) => healthyTIsLightMode(context)
    ? const Color(0xFFCAD2DA).withOpacity(0.72)
    : Colors.transparent;
