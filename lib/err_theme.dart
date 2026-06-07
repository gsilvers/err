import 'package:flutter/material.dart';

class ErrTheme {
  const ErrTheme({
    required this.id,
    required this.name,
    required this.isDark,
    this.isBuiltIn = false,
    required this.screenBackground,
    required this.appBarBackground,
    required this.appBarTitle,
    required this.statIcon,
    required this.statLabel,
    required this.statValue,
    required this.startActive,
    required this.startDisabled,
    required this.startForeground,
    required this.stopActive,
    required this.stopDisabled,
    required this.stopForeground,
    required this.toggleSelectedBackground,
    required this.toggleSelectedText,
    required this.toggleUnselectedBackground,
    required this.toggleUnselectedText,
    required this.toggleBorder,
    required this.messageInfo,
    required this.messageError,
  });

  final String id;
  final String name;
  final bool isDark;
  final bool isBuiltIn;

  final Color screenBackground;
  final Color appBarBackground;
  final Color appBarTitle;
  final Color statIcon;
  final Color statLabel;
  final Color statValue;
  final Color startActive;
  final Color startDisabled;
  final Color startForeground;
  final Color stopActive;
  final Color stopDisabled;
  final Color stopForeground;
  final Color toggleSelectedBackground;
  final Color toggleSelectedText;
  final Color toggleUnselectedBackground;
  final Color toggleUnselectedText;
  final Color toggleBorder;
  final Color messageInfo;
  final Color messageError;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'isDark': isDark,
        'screenBackground': screenBackground.toARGB32(),
        'appBarBackground': appBarBackground.toARGB32(),
        'appBarTitle': appBarTitle.toARGB32(),
        'statIcon': statIcon.toARGB32(),
        'statLabel': statLabel.toARGB32(),
        'statValue': statValue.toARGB32(),
        'startActive': startActive.toARGB32(),
        'startDisabled': startDisabled.toARGB32(),
        'startForeground': startForeground.toARGB32(),
        'stopActive': stopActive.toARGB32(),
        'stopDisabled': stopDisabled.toARGB32(),
        'stopForeground': stopForeground.toARGB32(),
        'toggleSelectedBackground': toggleSelectedBackground.toARGB32(),
        'toggleSelectedText': toggleSelectedText.toARGB32(),
        'toggleUnselectedBackground': toggleUnselectedBackground.toARGB32(),
        'toggleUnselectedText': toggleUnselectedText.toARGB32(),
        'toggleBorder': toggleBorder.toARGB32(),
        'messageInfo': messageInfo.toARGB32(),
        'messageError': messageError.toARGB32(),
      };

  factory ErrTheme.fromJson(Map<String, dynamic> j) => ErrTheme(
        id: j['id'] as String,
        name: j['name'] as String,
        isDark: j['isDark'] as bool,
        isBuiltIn: false,
        screenBackground: Color(j['screenBackground'] as int),
        appBarBackground: Color(j['appBarBackground'] as int),
        appBarTitle: Color(j['appBarTitle'] as int),
        statIcon: Color(j['statIcon'] as int),
        statLabel: Color(j['statLabel'] as int),
        statValue: Color(j['statValue'] as int),
        startActive: Color(j['startActive'] as int),
        startDisabled: Color(j['startDisabled'] as int),
        startForeground: Color(j['startForeground'] as int),
        stopActive: Color(j['stopActive'] as int),
        stopDisabled: Color(j['stopDisabled'] as int),
        stopForeground: Color(j['stopForeground'] as int),
        toggleSelectedBackground:
            Color(j['toggleSelectedBackground'] as int),
        toggleSelectedText: Color(j['toggleSelectedText'] as int),
        toggleUnselectedBackground:
            Color(j['toggleUnselectedBackground'] as int),
        toggleUnselectedText: Color(j['toggleUnselectedText'] as int),
        toggleBorder: Color(j['toggleBorder'] as int),
        messageInfo: Color(j['messageInfo'] as int),
        messageError: Color(j['messageError'] as int),
      );

  ErrTheme copyWith({
    String? id,
    String? name,
    bool? isDark,
    Color? screenBackground,
    Color? appBarBackground,
    Color? appBarTitle,
    Color? statIcon,
    Color? statLabel,
    Color? statValue,
    Color? startActive,
    Color? startDisabled,
    Color? startForeground,
    Color? stopActive,
    Color? stopDisabled,
    Color? stopForeground,
    Color? toggleSelectedBackground,
    Color? toggleSelectedText,
    Color? toggleUnselectedBackground,
    Color? toggleUnselectedText,
    Color? toggleBorder,
    Color? messageInfo,
    Color? messageError,
  }) =>
      ErrTheme(
        id: id ?? this.id,
        name: name ?? this.name,
        isDark: isDark ?? this.isDark,
        isBuiltIn: false,
        screenBackground: screenBackground ?? this.screenBackground,
        appBarBackground: appBarBackground ?? this.appBarBackground,
        appBarTitle: appBarTitle ?? this.appBarTitle,
        statIcon: statIcon ?? this.statIcon,
        statLabel: statLabel ?? this.statLabel,
        statValue: statValue ?? this.statValue,
        startActive: startActive ?? this.startActive,
        startDisabled: startDisabled ?? this.startDisabled,
        startForeground: startForeground ?? this.startForeground,
        stopActive: stopActive ?? this.stopActive,
        stopDisabled: stopDisabled ?? this.stopDisabled,
        stopForeground: stopForeground ?? this.stopForeground,
        toggleSelectedBackground:
            toggleSelectedBackground ?? this.toggleSelectedBackground,
        toggleSelectedText: toggleSelectedText ?? this.toggleSelectedText,
        toggleUnselectedBackground:
            toggleUnselectedBackground ?? this.toggleUnselectedBackground,
        toggleUnselectedText: toggleUnselectedText ?? this.toggleUnselectedText,
        toggleBorder: toggleBorder ?? this.toggleBorder,
        messageInfo: messageInfo ?? this.messageInfo,
        messageError: messageError ?? this.messageError,
      );
}

/// Named color slots used in the custom theme editor.
const List<(String key, String label)> errThemeSlots = [
  ('screenBackground', 'Screen Background'),
  ('appBarBackground', 'App Bar Background'),
  ('appBarTitle', 'App Bar Title'),
  ('statIcon', 'Stat Icon'),
  ('statLabel', 'Stat Label'),
  ('statValue', 'Stat Value'),
  ('startActive', 'Start Button'),
  ('startDisabled', 'Start Button (Disabled)'),
  ('startForeground', 'Start Button Text'),
  ('stopActive', 'Stop Button'),
  ('stopDisabled', 'Stop Button (Disabled)'),
  ('stopForeground', 'Stop Button Text'),
  ('toggleSelectedBackground', 'Toggle: Selected BG'),
  ('toggleSelectedText', 'Toggle: Selected Text'),
  ('toggleUnselectedBackground', 'Toggle: Unselected BG'),
  ('toggleUnselectedText', 'Toggle: Unselected Text'),
  ('toggleBorder', 'Toggle Border'),
  ('messageInfo', 'Info Message'),
  ('messageError', 'Error Message'),
];

/// Read a named slot off an [ErrTheme].
Color errThemeGetSlot(ErrTheme t, String key) {
  switch (key) {
    case 'screenBackground':
      return t.screenBackground;
    case 'appBarBackground':
      return t.appBarBackground;
    case 'appBarTitle':
      return t.appBarTitle;
    case 'statIcon':
      return t.statIcon;
    case 'statLabel':
      return t.statLabel;
    case 'statValue':
      return t.statValue;
    case 'startActive':
      return t.startActive;
    case 'startDisabled':
      return t.startDisabled;
    case 'startForeground':
      return t.startForeground;
    case 'stopActive':
      return t.stopActive;
    case 'stopDisabled':
      return t.stopDisabled;
    case 'stopForeground':
      return t.stopForeground;
    case 'toggleSelectedBackground':
      return t.toggleSelectedBackground;
    case 'toggleSelectedText':
      return t.toggleSelectedText;
    case 'toggleUnselectedBackground':
      return t.toggleUnselectedBackground;
    case 'toggleUnselectedText':
      return t.toggleUnselectedText;
    case 'toggleBorder':
      return t.toggleBorder;
    case 'messageInfo':
      return t.messageInfo;
    case 'messageError':
      return t.messageError;
    default:
      return Colors.transparent;
  }
}

/// Return a copy of [t] with the named slot replaced by [color].
ErrTheme errThemeSetSlot(ErrTheme t, String key, Color color) {
  switch (key) {
    case 'screenBackground':
      return t.copyWith(screenBackground: color);
    case 'appBarBackground':
      return t.copyWith(appBarBackground: color);
    case 'appBarTitle':
      return t.copyWith(appBarTitle: color);
    case 'statIcon':
      return t.copyWith(statIcon: color);
    case 'statLabel':
      return t.copyWith(statLabel: color);
    case 'statValue':
      return t.copyWith(statValue: color);
    case 'startActive':
      return t.copyWith(startActive: color);
    case 'startDisabled':
      return t.copyWith(startDisabled: color);
    case 'startForeground':
      return t.copyWith(startForeground: color);
    case 'stopActive':
      return t.copyWith(stopActive: color);
    case 'stopDisabled':
      return t.copyWith(stopDisabled: color);
    case 'stopForeground':
      return t.copyWith(stopForeground: color);
    case 'toggleSelectedBackground':
      return t.copyWith(toggleSelectedBackground: color);
    case 'toggleSelectedText':
      return t.copyWith(toggleSelectedText: color);
    case 'toggleUnselectedBackground':
      return t.copyWith(toggleUnselectedBackground: color);
    case 'toggleUnselectedText':
      return t.copyWith(toggleUnselectedText: color);
    case 'toggleBorder':
      return t.copyWith(toggleBorder: color);
    case 'messageInfo':
      return t.copyWith(messageInfo: color);
    case 'messageError':
      return t.copyWith(messageError: color);
    default:
      return t;
  }
}
