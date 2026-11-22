import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_nga/data/core/app_preferences.dart';

enum CustomLineHeight { NORMAL, MEDIUM, LARGE, XLARGE, XXLARGE }

extension LineHeightExtension on CustomLineHeight {
  double get size {
    switch (this) {
      case CustomLineHeight.NORMAL:
        return 1.2;
      case CustomLineHeight.LARGE:
        return 1.6;
      case CustomLineHeight.XLARGE:
        return 1.8;
      case CustomLineHeight.XXLARGE:
        return 2.0;
      case CustomLineHeight.MEDIUM:
        return 1.4;
    }
  }

  String get name {
    switch (this) {
      case CustomLineHeight.NORMAL:
        return "紧凑";
      case CustomLineHeight.LARGE:
        return "大杯";
      case CustomLineHeight.XLARGE:
        return "加大杯";
      case CustomLineHeight.XXLARGE:
        return "超级加倍";
      case CustomLineHeight.MEDIUM:
        return "Material Design";
    }
  }

  String get nameWithSize => "$name(x $size)";
}

class InterfaceSettingsState {
  final double contentSizeMultiple;
  final double titleSizeMultiple;
  final CustomLineHeight lineHeight;

  /// 帖子内容里表情的显示边长（px）。AC娘等表情按原尺寸渲染太小/太大时在此调。
  final double emoticonSize;

  /// 首页社区页用「左侧分类栏 + 右侧内容」双栏布局（对齐官方客户端样式）。
  /// false = 上游默认的顶部横向 Tab。
  final bool homeCategoryRail;

  /// UID 形式用户名（`UID:xxxxxxxx`）的尾 4 字彩色高亮，上游原生行为。
  final bool usernameUidHighlight;

  static const double defaultEmoticonSize = 24;
  static const double minEmoticonSize = 16;
  static const double maxEmoticonSize = 96;

  const InterfaceSettingsState({
    this.contentSizeMultiple = 1.0,
    this.titleSizeMultiple = 1.0,
    this.lineHeight = CustomLineHeight.MEDIUM,
    this.emoticonSize = defaultEmoticonSize,
    this.homeCategoryRail = false,
    this.usernameUidHighlight = true,
  });

  InterfaceSettingsState copyWith({
    double? contentSizeMultiple,
    double? titleSizeMultiple,
    CustomLineHeight? lineHeight,
    double? emoticonSize,
    bool? homeCategoryRail,
    bool? usernameUidHighlight,
  }) {
    return InterfaceSettingsState(
      contentSizeMultiple: contentSizeMultiple ?? this.contentSizeMultiple,
      titleSizeMultiple: titleSizeMultiple ?? this.titleSizeMultiple,
      lineHeight: lineHeight ?? this.lineHeight,
      emoticonSize: emoticonSize ?? this.emoticonSize,
      homeCategoryRail: homeCategoryRail ?? this.homeCategoryRail,
      usernameUidHighlight: usernameUidHighlight ?? this.usernameUidHighlight,
    );
  }
}

class InterfaceSettingsNotifier extends Notifier<InterfaceSettingsState> {
  SharedPreferencesWithCache? _prefs;

  @override
  InterfaceSettingsState build() => const InterfaceSettingsState();

  Future<SharedPreferencesWithCache> get _settings async {
    _prefs ??= await AppPreferences.instance();
    return _prefs!;
  }

  Future<void> init() async {
    final settings = await _settings;
    final contentSize =
        settings.getDouble(PrefsKeys.uiContentSizeMultiple) ?? 1.0;
    final titleSize = settings.getDouble(PrefsKeys.uiTitleSizeMultiple) ?? 1.0;
    final lineHeightIndex =
        settings.getInt(PrefsKeys.uiLineHeight) ??
        CustomLineHeight.MEDIUM.index;
    final emoticonSize =
        settings.getDouble(PrefsKeys.uiEmoticonSize) ??
        InterfaceSettingsState.defaultEmoticonSize;
    final homeCategoryRail =
        settings.getBool(PrefsKeys.uiHomeCategoryRail) ?? false;
    final usernameUidHighlight =
        settings.getBool(PrefsKeys.uiUsernameUidHighlight) ?? true;

    state = InterfaceSettingsState(
      contentSizeMultiple: contentSize,
      titleSizeMultiple: titleSize,
      lineHeight: _getLineHeightByIndex(lineHeightIndex),
      emoticonSize: emoticonSize.clamp(
        InterfaceSettingsState.minEmoticonSize,
        InterfaceSettingsState.maxEmoticonSize,
      ),
      homeCategoryRail: homeCategoryRail,
      usernameUidHighlight: usernameUidHighlight,
    );
  }

  Future<void> setEmoticonSize(double size) async {
    final clamped = size.clamp(
      InterfaceSettingsState.minEmoticonSize,
      InterfaceSettingsState.maxEmoticonSize,
    );
    state = state.copyWith(emoticonSize: clamped);
    final settings = await _settings;
    await settings.setDouble(PrefsKeys.uiEmoticonSize, clamped);
  }

  Future<void> setUsernameUidHighlight(bool enabled) async {
    state = state.copyWith(usernameUidHighlight: enabled);
    final settings = await _settings;
    await settings.setBool(PrefsKeys.uiUsernameUidHighlight, enabled);
  }

  Future<void> setHomeCategoryRail(bool enabled) async {
    state = state.copyWith(homeCategoryRail: enabled);
    final settings = await _settings;
    await settings.setBool(PrefsKeys.uiHomeCategoryRail, enabled);
  }

  Future<void> setContentSizeMultiple(double multiple) async {
    state = state.copyWith(contentSizeMultiple: multiple);
    final settings = await _settings;
    await settings.setDouble(PrefsKeys.uiContentSizeMultiple, multiple);
  }

  Future<void> setTitleSizeMultiple(double multiple) async {
    state = state.copyWith(titleSizeMultiple: multiple);
    final settings = await _settings;
    await settings.setDouble(PrefsKeys.uiTitleSizeMultiple, multiple);
  }

  Future<void> setLineHeight(int index) async {
    final lineHeight = _getLineHeightByIndex(index);
    state = state.copyWith(lineHeight: lineHeight);
    final settings = await _settings;
    await settings.setInt(PrefsKeys.uiLineHeight, index);
  }

  CustomLineHeight _getLineHeightByIndex(int index) {
    switch (index) {
      case 0:
        return CustomLineHeight.NORMAL;
      case 2:
        return CustomLineHeight.LARGE;
      case 3:
        return CustomLineHeight.XLARGE;
      case 4:
        return CustomLineHeight.XXLARGE;
      case 1:
      default:
        return CustomLineHeight.MEDIUM;
    }
  }
}

final interfaceSettingsProvider =
    NotifierProvider<InterfaceSettingsNotifier, InterfaceSettingsState>(
      InterfaceSettingsNotifier.new,
    );
