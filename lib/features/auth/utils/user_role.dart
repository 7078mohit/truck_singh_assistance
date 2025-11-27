import 'package:flutter/material.dart';

enum UserRole { driver, truckOwner, shipper, agent, Admin }

extension UserRoleExtension on UserRole {
  static const _data = {
    UserRole.agent: {
      'name': 'Agent',
      'db': 'agent',
      'icon': Icons.support_agent,
      'prefix': 'AGNT',
    },
    UserRole.driver: {
      'name': 'Driver',
      'db': 'driver',
      'icon': Icons.groups,
      'prefix': 'DRV',
    },
    UserRole.truckOwner: {
      'name': 'Truck Owner',
      'db': 'truckowner',
      'icon': Icons.local_shipping,
      'prefix': 'TRUK',
    },
    UserRole.shipper: {
      'name': 'Shipper',
      'db': 'shipper',
      'icon': Icons.shopping_cart,
      'prefix': 'SHIP',
    },
    UserRole.Admin: {
      'name': 'Admin',
      'db': 'Admin',
      'icon': Icons.add_moderator_outlined,
      'prefix': 'ADM',
    },
  };

  String get displayName => _data[this]!['name'] as String;
  String get dbValue => _data[this]!['db'] as String;
  IconData get icon => _data[this]!['icon'] as IconData;
  String get prefix => _data[this]!['prefix'] as String;

  static UserRole? fromDbValue(String? value) {
    if (value == null) return null;
    return _data.entries
        .firstWhere(
          (e) => e.value['db'] == value,
      orElse: () => const MapEntry(UserRole.agent, {}),
    )
        .key;
  }
}