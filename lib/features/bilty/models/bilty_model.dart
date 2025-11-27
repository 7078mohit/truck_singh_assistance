extension JsonSafe on Map<String, dynamic> {
  T getOr<T>(String key, T fallback) => (this[key] ?? fallback) as T;
  double getDouble(String key) => (this[key] ?? 0).toDouble();
  DateTime? getDate(String key) => this[key] != null ? DateTime.parse(this[key]) : null;
}

/// ---------- BASE MODEL FOR SHARED JSON LOGIC ----------
mixin JsonModel {
  Map<String, dynamic> toJson();
}

/// ------------------ BILTY MODEL -----------------------
class BiltyModel with JsonModel {
  final String? id, userId;
  final String biltyNo, consignorName, consigneeName, origin, destination;
  final double totalFare;
  final DateTime? createdAt, updatedAt;
  final Map<String, dynamic> metadata;

  BiltyModel({
    this.id,
    required this.biltyNo,
    required this.consignorName,
    required this.consigneeName,
    required this.origin,
    required this.destination,
    required this.totalFare,
    this.userId,
    this.createdAt,
    this.updatedAt,
    required this.metadata,
  });

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'bilty_no': biltyNo,
    'consignor_name': consignorName,
    'consignee_name': consigneeName,
    'origin': origin,
    'destination': destination,
    'total_fare': totalFare,
    'user_id': userId,
    'created_at': createdAt?.toIso8601String(),
    'updated_at': updatedAt?.toIso8601String(),
    'metadata': metadata,
  };

  factory BiltyModel.fromJson(Map<String, dynamic> json) => BiltyModel(
    id: json['id'],
    biltyNo: json.getOr('bilty_no', ''),
    consignorName: json.getOr('consignor_name', ''),
    consigneeName: json.getOr('consignee_name', ''),
    origin: json.getOr('origin', ''),
    destination: json.getOr('destination', ''),
    totalFare: json.getDouble('total_fare'),
    userId: json['user_id'],
    createdAt: json.getDate('created_at'),
    updatedAt: json.getDate('updated_at'),
    metadata: json['metadata'] ?? {},
  );
}

/// ---------------- PARTY DETAILS ----------------
class PartyDetails with JsonModel {
  final String name, address;
  final String? gstin, phone, email;

  PartyDetails({
    required this.name,
    required this.address,
    this.gstin,
    this.phone,
    this.email,
  });

  @override
  Map<String, dynamic> toJson() => {
    'name': name,
    'address': address,
    'gstin': gstin,
    'phone': phone,
    'email': email,
  };

  factory PartyDetails.fromJson(Map<String, dynamic> json) => PartyDetails(
    name: json.getOr('name', ''),
    address: json.getOr('address', ''),
    gstin: json['gstin'],
    phone: json['phone'],
    email: json['email'],
  );
}

/// ---------------- GOODS ITEM ----------------
class GoodsItem with JsonModel {
  final String description;
  final int quantity;
  final double weight, rate, amount;

  GoodsItem({
    required this.description,
    required this.quantity,
    required this.weight,
    required this.rate,
    required this.amount,
  });

  GoodsItem copyWith({
    String? description,
    int? quantity,
    double? weight,
    double? rate,
    double? amount,
  }) =>
      GoodsItem(
        description: description ?? this.description,
        quantity: quantity ?? this.quantity,
        weight: weight ?? this.weight,
        rate: rate ?? this.rate,
        amount: amount ?? this.amount,
      );

  @override
  Map<String, dynamic> toJson() => {
    'description': description,
    'quantity': quantity,
    'weight': weight,
    'rate': rate,
    'amount': amount,
  };

  factory GoodsItem.fromJson(Map<String, dynamic> json) => GoodsItem(
    description: json.getOr('description', ''),
    quantity: json.getOr('quantity', 0),
    weight: json.getDouble('weight'),
    rate: json.getDouble('rate'),
    amount: json.getDouble('amount'),
  );
}

/// ---------------- VEHICLE DETAILS ----------------
class VehicleDetails with JsonModel {
  final String vehicleNumber, driverName;
  final String? driverPhone, driverLicense;

  VehicleDetails({
    required this.vehicleNumber,
    required this.driverName,
    this.driverPhone,
    this.driverLicense,
  });

  @override
  Map<String, dynamic> toJson() => {
    'vehicle_number': vehicleNumber,
    'driver_name': driverName,
    'driver_phone': driverPhone,
    'driver_license': driverLicense,
  };

  factory VehicleDetails.fromJson(Map<String, dynamic> json) => VehicleDetails(
    vehicleNumber: json.getOr('vehicle_number', ''),
    driverName: json.getOr('driver_name', ''),
    driverPhone: json['driver_phone'],
    driverLicense: json['driver_license'],
  );
}

/// ---------------- CHARGES DETAILS ----------------
class ChargesDetails with JsonModel {
  final double basicFare, otherCharges, gst, totalAmount;
  final String paymentStatus;

  ChargesDetails({
    required this.basicFare,
    required this.otherCharges,
    required this.gst,
    required this.totalAmount,
    required this.paymentStatus,
  });

  @override
  Map<String, dynamic> toJson() => {
    'basic_fare': basicFare,
    'other_charges': otherCharges,
    'gst': gst,
    'total_amount': totalAmount,
    'payment_status': paymentStatus,
  };

  factory ChargesDetails.fromJson(Map<String, dynamic> json) => ChargesDetails(
    basicFare: json.getDouble('basic_fare'),
    otherCharges: json.getDouble('other_charges'),
    gst: json.getDouble('gst'),
    totalAmount: json.getDouble('total_amount'),
    paymentStatus: json.getOr('payment_status', 'To Pay'),
  );
}