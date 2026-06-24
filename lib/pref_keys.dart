/// Every key Err persists in `shared_preferences`, in one place — so they
/// can't drift or be mistyped, and so there's a single inventory of what the
/// app stores on the device.
abstract final class PrefKeys {
  static const selectedThemeId = 'selected_theme_id';
  static const customThemes = 'custom_themes';
  static const useImperial = 'use_imperial';
  static const keepScreenOn = 'keep_screen_on';
  static const showSpeed = 'show_speed';
  static const debugMode = 'debug_mode';
  static const appearance = 'appearance';
}
