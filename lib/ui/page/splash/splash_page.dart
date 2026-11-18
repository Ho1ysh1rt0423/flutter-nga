import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:material_ui/material_ui.dart';
import 'package:timeago/timeago.dart' as time_ago;
import 'package:flutter_nga/data/data.dart';
import 'package:flutter_nga/utils/custom_time_messages.dart';
import 'package:flutter_nga/utils/route.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashState();
}

class _SplashState extends State<SplashPage> {
  /// 亮色时的品牌奶黄底；深色主题下改用 [ColorScheme.surface]，避免夜间
  /// 冷启动闪一下高亮底色（原生启动屏也已按 `values-night` 换深色）。
  static const _lightSplashBackground = Color(0xFFFFF9E3);

  /// 亮色 logo 自带奶黄底板；深色版是透明底 + 奶白爪印。
  static const _lightSplashIcon = 'images/launcher/splash_icon_1024.png';
  static const _darkSplashIcon = 'images/launcher/splash_icon_dark_1024.png';

  @override
  void initState() {
    time_ago.setLocaleMessages('en', CustomTimeMessages());
    Data().init().then((_) {
      if (!mounted) return;
      FlutterNativeSplash.remove();
      Routes.navigateTo(context, Routes.HOME, replace: true);
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark
        ? Theme.of(context).colorScheme.surface
        : _lightSplashBackground;
    final overlayStyle =
        (isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
            .copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: Colors.transparent,
              systemNavigationBarContrastEnforced: false,
            );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        backgroundColor: background,
        body: Center(
          child: Image.asset(
            isDark ? _darkSplashIcon : _lightSplashIcon,
            width: 200,
            height: 200,
          ),
        ),
      ),
    );
  }
}
