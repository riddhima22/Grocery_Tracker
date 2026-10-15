class UserModel {
  final String id;
  final String email;
  final String displayName;
  final String? avatarUrl;
  final bool emailVerified;

  final String dietType;
  final String cuisinePref;
  final List<String> allergies;
  final int householdSize;

  final bool notify3Days;
  final bool notify1Day;
  final bool notifyDailyRecipe;

  final int totalTracked;
  final int savedFromWaste;
  final int recipesCooked;

  const UserModel({
    required this.id,
    required this.email,
    required this.displayName,
    this.avatarUrl,
    this.emailVerified = false,
    this.dietType = 'any',
    this.cuisinePref = '',
    this.allergies = const [],
    this.householdSize = 1,
    this.notify3Days = true,
    this.notify1Day = true,
    this.notifyDailyRecipe = true,
    this.totalTracked = 0,
    this.savedFromWaste = 0,
    this.recipesCooked = 0,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] ?? '',
      email: json['email'] ?? '',
      displayName: json['display_name'] ?? '',
      avatarUrl: json['avatar_url'],
      emailVerified: json['email_verified'] ?? false,
      dietType: json['diet_type'] ?? 'any',
      cuisinePref: json['cuisine_pref'] ?? '',
      allergies: List<String>.from(json['allergies'] ?? []),
      householdSize: json['household_size'] ?? 1,
      notify3Days: json['notify_3_days'] ?? true,
      notify1Day: json['notify_1_day'] ?? true,
      notifyDailyRecipe: json['notify_daily_recipe'] ?? true,
      totalTracked: json['total_tracked'] ?? 0,
      savedFromWaste: json['saved_from_waste'] ?? 0,
      recipesCooked: json['recipes_cooked'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'display_name': displayName,
    'avatar_url': avatarUrl,
    'diet_type': dietType,
    'cuisine_pref': cuisinePref,
    'allergies': allergies,
    'household_size': householdSize,
    'notify_3_days': notify3Days,
    'notify_1_day': notify1Day,
    'notify_daily_recipe': notifyDailyRecipe,
  };

  Map<String, dynamic> toFullJson() => {
    'id': id,
    'email': email,
    'display_name': displayName,
    'avatar_url': avatarUrl,
    'email_verified': emailVerified,
    'diet_type': dietType,
    'cuisine_pref': cuisinePref,
    'allergies': allergies,
    'household_size': householdSize,
    'notify_3_days': notify3Days,
    'notify_1_day': notify1Day,
    'notify_daily_recipe': notifyDailyRecipe,
    'total_tracked': totalTracked,
    'saved_from_waste': savedFromWaste,
    'recipes_cooked': recipesCooked,
  };

  UserModel copyWith({
    String? displayName,
    String? avatarUrl,
    String? dietType,
    String? cuisinePref,
    List<String>? allergies,
    int? householdSize,
    bool? notify3Days,
    bool? notify1Day,
    bool? notifyDailyRecipe,
  }) {
    return UserModel(
      id: id,
      email: email,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      emailVerified: emailVerified,
      dietType: dietType ?? this.dietType,
      cuisinePref: cuisinePref ?? this.cuisinePref,
      allergies: allergies ?? this.allergies,
      householdSize: householdSize ?? this.householdSize,
      notify3Days: notify3Days ?? this.notify3Days,
      notify1Day: notify1Day ?? this.notify1Day,
      notifyDailyRecipe: notifyDailyRecipe ?? this.notifyDailyRecipe,
      totalTracked: totalTracked,
      savedFromWaste: savedFromWaste,
      recipesCooked: recipesCooked,
    );
  }
}
