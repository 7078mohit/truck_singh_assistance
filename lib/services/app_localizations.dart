import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;
import 'app_localizations_en.dart';
import 'app_localizations_hi.dart';

abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
  _AppLocalizationsDelegate();

  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
  <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('hi'),
  ];

  String get settings;
  String get editProfile;
  String get language;
  String get darkMode;
  String get lightMode;
  String get rateApp;
  String get feedback;
  String get appVersion;
  String get termsConditions;
  String get takePhoto;
  String get chooseFromGallery;
  String get profileUpdated;
  String get uploadFailed;
  String get theme;
  String get systemDefault;
  String get chooseTheme;
  String get logout;
  String get confirmLogout;
  String get cancel;
  String get confirm;
  String get accountInfo;
  String get languagePreferences;

  String get verify_otp;
  String get edit_mobile;
  String get reportBug;
  String get changepassword;
  String get delete;
  String get blockAccount;
  String get update;
  String get save;
  String get no;
  String get yes;
  String get apply;
  String get verify;

  String? get mobile_number;

  String get account_disabled;
  String get error_sending_otp;
  String? get enter_otp;
  String get mobile_verified;
  String get otp_failed;
  String get error_verifying_otp;
  String get logout_message;
  String get profilePictureUpdated;
  String? get uploadError;
  String get failedToUpload;
  String? get bugHint;
  String get bugEmpty;

  String? get oldPassword;
  String? get newPassword;
  String get passwordHint;
  String get atLeast8Chars;
  String get uppercaseLetter;
  String get lowercaseLetter;
  String get aNumber;
  String get specialCharacter;
  String get passwordStrong;

  Object get weak;
  Object get medium;

  String? get confirmNewPassword;
  String get allFieldsRequired;
  String get passwordMismatch;
  String get noUser;
  String get wrongOldPassword;
  String get passwordUpdated;
  String get passwordUpdateFailed;

  String get editName;
  String? get fullName;
  String get confirmNameChange;
  String get nameChangeMessage;
  String get nameUpdated;
  String get nameUpdateError;

  String get accountDisabledLogout;
  String get accountDisabledSupport;

  String get chooseFile;

  String get nameEmptyError;
  String get mobileInvalidError;

  String get close;

  String get imageUploadFailed;

  String get accountManagement;
  String get deleteAccount;

  String get address;
  String get addressBook;

  String get notificationSettings;
  String get supportFeedback;
  String get legalInfo;
  String get privacyPolicy;
  String get requestSupport;

  // agent db
  String get performanceOverview;
  String get activeLoads;
  String get completed;
  String get findShipments;
  String get availableLoads;
  String get createShipment;
  String get postNewLoad;
  String get myChats;
  String get viewConversations;
  String get loadBoard;
  String get browsePostLoads;
  String get activeTrips;
  String get monitorLiveLocations;
  String get myTrucks;
  String get addTrackVehicles;
  String get myDrivers;
  String get addTrackDrivers;
  String get ratings;
  String get viewRatings;
  String get complaints;
  String get fileOrView;
  String get myTrips;
  String get historyDetails;
  String get bilty;
  String get createConsignmentNote;
  String get truckDocuments;
  String get manageTruckRecords;
  String get driverDocuments;
  String get manageDriverRecords;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'hi'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'hi':
      return AppLocalizationsHi();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale".',
  );
}