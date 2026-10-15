class AppStrings {
  static String activeLanguage =
      'en'; // default language, can be switched to 'hi'

  static const Map<String, Map<String, String>> _localizedValues = {
    'en': {
      'auth.welcomeBack': 'Welcome back!',
      'auth.signIn': 'Sign In',
      'auth.createAccount': 'Create Account',
      'auth.forgotPassword': 'Forgot Password',
      'auth.verifyEmail': 'Verify Email',
      'scan.aiAnalysing': 'AI is analyzing your images...',
      'scan.itemsDetected': 'Items Detected',
      'scan.retryImage': 'Retry source image',
      'pantry.markConsumed': 'Mark as Consumed',
      'pantry.markWasted': 'Mark as Wasted',
      'groceryList.suggestionReason': 'Suggested based on your history',
      'errors.network':
          'No internet connection. Check your network and try again.',
      'errors.sessionExpired':
          'Your session has expired. Please sign in again.',
      'errors.unauthorized':
          'Incorrect credentials. Please check and try again.',
      'errors.rateLimit':
          'Too many scan attempts. Please wait before trying again.',
      'errors.generic': 'Something went wrong. Please try again.',

      'onboarding.title1': 'Never waste groceries again',
      'onboarding.desc1':
          'Track your groceries and know what to use before it expires.',
      'onboarding.title2': 'Smart storage guidance',
      'onboarding.desc2':
          'Know where every grocery item belongs and help it stay fresh longer.',
      'onboarding.title3': 'Recipes from what you have',
      'onboarding.desc3':
          'Turn groceries already in your kitchen into useful meal ideas.',

      'dashboard.expiringSoon': 'Expiring Soon',
      'dashboard.expired': 'Expired',
      'dashboard.fresh': 'Fresh',
      'dashboard.total': 'Total Items',
      'dashboard.useFirst': 'Use These First',
      'dashboard.greetingMorning': 'Good morning',
      'dashboard.greetingAfternoon': 'Good afternoon',
      'dashboard.greetingEvening': 'Good evening',

      'kitchen.fridge': 'FRIDGE',
      'kitchen.spices': 'SPICES',
      'kitchen.pantry': 'PANTRY',
      'kitchen.cabinet': 'CABINET',
      'kitchen.counter': 'COUNTER',
      'kitchen.basket': 'BASKET',
      'kitchen.freezer': 'FREEZER',
    },
    'hi': {
      'auth.welcomeBack': 'वापसी पर आपका स्वागत है!',
      'auth.signIn': 'साइन इन करें',
      'auth.createAccount': 'खाता बनाएँ',
      'auth.forgotPassword': 'पासवर्ड भूल गए',
      'auth.verifyEmail': 'ईमेल सत्यापित करें',
      'scan.aiAnalysing': 'एआई आपकी छवियों का विश्लेषण कर रहा है...',
      'scan.itemsDetected': 'सामग्री मिली',
      'scan.retryImage': 'पुनः प्रयास करें',
      'pantry.markConsumed': 'उपभोग किया गया',
      'pantry.markWasted': 'बर्बाद चिह्नित करें',
      'groceryList.suggestionReason': 'आपके इतिहास के आधार पर सुझाया गया',
      'errors.network':
          'कोई इंटरनेट कनेक्शन नहीं। कृपया जाँचें और पुनः प्रयास करें।',
      'errors.sessionExpired':
          'आपका सत्र समाप्त हो गया है। कृपया पुनः साइन इन करें।',
      'errors.unauthorized': 'गलत विवरण। कृपया पुनः जाँचें।',
      'errors.rateLimit': 'बहुत सारे प्रयास। कृपया बाद में प्रयास करें।',
      'errors.generic': 'कुछ गलत हो गया। कृपया पुनः प्रयास करें।',

      'onboarding.title1': 'कभी भोजन बर्बाद न करें',
      'onboarding.desc1':
          'अपने राशन को ट्रैक करें और समाप्त होने से पहले उपयोग करना जानें।',
      'onboarding.title2': 'स्मार्ट स्टोरेज गाइड',
      'onboarding.desc2':
          'जानें कि राशन की हर वस्तु कहाँ रखी जानी चाहिए ताकि वह लंबे समय तक ताज़ा रहे।',
      'onboarding.title3': 'रसोई के सामान से रेसिपी',
      'onboarding.desc3':
          'अपनी रसोई में पहले से मौजूद सामान को स्वादिष्ट भोजन विचारों में बदलें।',

      'dashboard.expiringSoon': 'जल्द समाप्त',
      'dashboard.expired': 'समाप्त',
      'dashboard.fresh': 'ताज़ा',
      'dashboard.total': 'कुल वस्तुएं',
      'dashboard.useFirst': 'पहले उपयोग करें',
      'dashboard.greetingMorning': 'सुप्रभात',
      'dashboard.greetingAfternoon': 'नमस्कार',
      'dashboard.greetingEvening': 'शुभ संध्या',

      'kitchen.fridge': 'फ्रिज',
      'kitchen.spices': 'मसाले',
      'kitchen.pantry': 'रसोई भंडार',
      'kitchen.cabinet': 'अलमारी',
      'kitchen.counter': 'काउंटर',
      'kitchen.basket': 'टोकरी',
      'kitchen.freezer': 'फ्रीजर',
    },
  };

  static String get(String key) {
    final lang = activeLanguage;
    return _localizedValues[lang]?[key] ?? _localizedValues['en']?[key] ?? key;
  }
}

extension StringLocExt on String {
  String get tr => AppStrings.get(this);
}
