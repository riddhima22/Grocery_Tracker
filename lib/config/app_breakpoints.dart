class AppBreakpoints {
  AppBreakpoints._();

  // Device width thresholds (exclusive upper bounds for each category)
  static const double compactPhoneMax = 359.0;
  static const double phoneMax = 599.0;
  static const double largePhoneMax = 719.0;
  static const double tabletMax = 1023.0;

  // Named breakpoint aliases for responsive layout switching
  static const double mobile = 600;
  static const double tablet = 768;
  static const double desktop = 1024;
}
