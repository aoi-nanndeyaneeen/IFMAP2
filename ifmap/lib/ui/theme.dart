// lib/ui/theme.dart
//
// 画面全体の色と文字の決まりごと。
//
// 地図アプリは「地図が主役、UIは脇役」なので、UIは白地に濃いグレーの
// 文字でまとめ、色は意味のあるところ（経路の青・目的地の赤・現在地の青・
// 注意の黄）にだけ使う。
import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  /// 操作と経路の青。
  static const primary = Color(0xFF1A73E8);
  static const primaryDark = Color(0xFF1557B0);
  static const primarySoft = Color(0xFFE8F0FE);

  /// 目的地・ピンの赤。
  static const destination = Color(0xFFEA4335);
  static const destinationDark = Color(0xFFA50E0E);

  /// ナビ中の案内バナー（Google マップの緑に寄せた濃い緑）。
  static const guidance = Color(0xFF0F6B4F);
  static const guidanceDark = Color(0xFF0A5540);

  static const success = Color(0xFF188038);
  static const warning = Color(0xFFF9AB00);
  static const warningSoft = Color(0xFFFEF7E0);
  static const danger = Color(0xFFD93025);

  static const text = Color(0xFF202124);
  static const textSecondary = Color(0xFF5F6368);
  static const textTertiary = Color(0xFF80868B);
  static const divider = Color(0xFFE8EAED);
  static const outline = Color(0xFFDADCE0);
  static const surface = Colors.white;
  static const surfaceDim = Color(0xFFF1F3F4);

  /// 地図の地の色。
  static const mapBackground = Color(0xFFE9ECEF);
  static const mapGround = Color(0xFFE4EEDC);
  static const mapFloor = Color(0xFFF7F8F9);
  static const mapCorridor = Colors.white;
  static const mapOutdoor = Color(0xFFDCEDD3);
  static const mapBuildingEdge = Color(0xFF9AA0A6);
  static const mapWall = Color(0xFF80868B);
  static const mapLabel = Color(0xFF3C4043);

  /// 経路の線。歩き終えた部分は色を落とす。
  static const route = Color(0xFF1A73E8);
  static const routeCasing = Color(0xFF1557B0);
  static const routePassed = Color(0xFFA8B8D0);

  static const userDot = Color(0xFF1A73E8);
}

/// 数字の幅をそろえる（残り距離が 9 → 10 m になっても揺れない）。
const tabularFigures = [FontFeature.tabularFigures()];

/// [fontFamily] を渡すとアプリ全体の書体をそれにする（省略時は端末の標準）。
ThemeData buildAppTheme({String? fontFamily}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    primary: AppColors.primary,
    surface: AppColors.surface,
  );
  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.mapBackground,
    splashFactory: InkSparkle.splashFactory,
  );
  final text = base.textTheme.apply(
    bodyColor: AppColors.text,
    displayColor: AppColors.text,
    fontFamily: fontFamily,
  );
  // ボタンの文字は textTheme を引き継がないので、書体をここで渡す。
  final button = (text.labelLarge ?? const TextStyle())
      .copyWith(fontSize: 15, fontWeight: FontWeight.w600);
  return base.copyWith(
    textTheme: text,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: const StadiumBorder(),
        textStyle: button,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: const StadiumBorder(),
        side: const BorderSide(color: AppColors.outline),
        textStyle: button,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        textStyle: button,
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: Colors.white,
      side: const BorderSide(color: AppColors.outline),
      shape: const StadiumBorder(),
      labelStyle: (text.labelLarge ?? const TextStyle()).copyWith(
          fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.text),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.divider, space: 1),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
