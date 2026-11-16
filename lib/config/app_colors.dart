import 'package:flutter/material.dart';

class AppColors {
  static const primary = Color(0xFF1DB868);
  static const primaryDark = Color(0xFF0FA050);
  static const primaryDeep = Color(0xFF0A6E38);

  static const bgDark = Color(0xFF0A0F0D);
  static const surface = Color(0xFF111A14);
  static const card = Color(0xFF162019);
  static const cardBorder = Color(0xFF1E3024);

  static const textPrimary = Color(0xFFF0F7F2);
  static const textSecondary = Color(0xFF6B8F74);
  static const textHint = Color(0xFF3A5030);

  static const success = Color(0xFF1DB868);
  static const warning = Color(0xFFF5A623);
  static const danger = Color(0xFFE84545);
  static const info = Color(0xFF4A9EFF);

  static const divider = Color(0xFF1E3024);
  static const overlay = Color(0x99000000);
  static const white = Color(0xFFFFFFFF);
  static const black = Color(0xFF000000);

  static const Color wallTop = Color(0xFFF0DFC0);
  static const Color wallBottom = Color(0xFFB8943D);
  static const Color floorTop = Color(0xFFB8943D);
  static const Color floorBottom = Color(0xFFA07828);
  static const Color countertopTop = Color(0xFFE8E0D0);
  static const Color countertopBottom = Color(0xFFD8CFC0);

  static const Color fridgeTop = Color(0xFFE8F0F8);
  static const Color fridgeBottom = Color(0xFFC0CCD8);
  static const Color fridgeBorder = Color(0xFFA8B8C8);
  static const Color fridgeDivider = Color(0xFFA0B0C0);
  static const Color fridgeHandle = Color(0xFF8090A0);
  static const Color fridgeLabel = Color(0xFF506878);
  static const Color fridgeCount = Color(0xFF4A9EFF);

  static const Color woodTop = Color(0xFFD4A855);
  static const Color woodBottom = Color(0xFFB88830);
  static const Color woodBorder = Color(0xFF906820);
  static const Color woodDoor = Color(0xFFDDB858);
  static const Color woodHandle = Color(0xFF786028);

  static const Color zonePillBg = Color(0xBF0D1208);
  static const Color zonePillBorder = Color(0x662DB85A);
  static const Color zonePillText = Color(0xFF5DD880);
  static const Color zoneCountBg = Color(0x332DB85A);
  static const Color zoneCountText = Color(0xFF3DBA60);

  static const primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1DB868), Color(0xFF0FA050)],
  );

  static const bgGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF0A0F0D), Color(0xFF0A0F0D)],
  );

  static const splashGradient = RadialGradient(
    center: Alignment(0, -0.3),
    radius: 1.2,
    colors: [Color(0xFF0D2B1A), Color(0xFF050C07), Color(0xFF030805)],
  );
}
