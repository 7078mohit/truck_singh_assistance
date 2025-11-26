import 'package:easy_localization/easy_localization.dart';

mixin AddressMixin {
  String get flatNo;
  String get streetName;
  String get cityName;
  String get district;
  String get zipCode;

  Map<String, dynamic> toLocalizedJson() => {
    'flatNo'.tr(): flatNo,
    'streetName'.tr(): streetName,
    'cityName'.tr(): cityName,
    'district'.tr(): district,
    'zipCode'.tr(): zipCode,
  };

  Map<String, dynamic> toJson() => {
    'flatNo': flatNo,
    'streetName': streetName,
    'cityName': cityName,
    'district': district,
    'zipCode': zipCode,
  };
}

class BillingAddress with AddressMixin {
  @override
  String flatNo, streetName, cityName, district, zipCode;

  BillingAddress({
    required this.flatNo,
    required this.streetName,
    required this.cityName,
    required this.district,
    required this.zipCode,
  });

  factory BillingAddress.fromJson(Map<String, dynamic> json) => BillingAddress(
    flatNo: json['flatNo'] ?? '',
    streetName: json['streetName'] ?? '',
    cityName: json['cityName'] ?? '',
    district: json['district'] ?? '',
    zipCode: json['zipCode'] ?? '',
  );
}

class CompanyAddress with AddressMixin {
  @override
  String flatNo, streetName, cityName, district, zipCode;

  CompanyAddress({
    required this.flatNo,
    required this.streetName,
    required this.cityName,
    required this.district,
    required this.zipCode,
  });

  factory CompanyAddress.fromJson(Map<String, dynamic> json) => CompanyAddress(
    flatNo: json['flatNo'] ?? '',
    streetName: json['streetName'] ?? '',
    cityName: json['cityName'] ?? '',
    district: json['district'] ?? '',
    zipCode: json['zipCode'] ?? '',
  );
}