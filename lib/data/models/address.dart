import 'package:om_events/data/om_doc.dart';

final class AddressBookEntry {
  const AddressBookEntry({
    required this.id,
    required this.uid,
    required this.name,
    required this.phone,
    required this.line1,
    required this.city,
    required this.state,
    required this.pincode,
    this.line2 = '',
    this.gstNumber = '',
    this.isDefaultShipping = false,
    this.isDefaultBilling = false,
    this.isWorkAddress = false,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String uid;
  final String name;
  final String phone;
  final String line1;
  final String line2;
  final String city;
  final String state;
  final String pincode;
  final String gstNumber;
  final bool isDefaultShipping;
  final bool isDefaultBilling;
  final bool isWorkAddress;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get displayLine => '$line1${line2.isEmpty ? '' : ', $line2'}';

  String get fullAddress => <String>[
        name,
        displayLine,
        '$city, $state - $pincode',
        phone,
      ].where((s) => s.trim().isNotEmpty).join('\n');

  factory AddressBookEntry.fromMap(Map<String, dynamic> m, {String? id}) => AddressBookEntry(
        id: id ?? readStringOrEmpty(m, 'id'),
        uid: readStringOrEmpty(m, 'uid'),
        name: readStringOrEmpty(m, 'name'),
        phone: readStringOrEmpty(m, 'phone'),
        line1: readStringOrEmpty(m, 'line1'),
        line2: readStringOrEmpty(m, 'line2'),
        city: readStringOrEmpty(m, 'city'),
        state: readStringOrEmpty(m, 'state'),
        pincode: readStringOrEmpty(m, 'pincode'),
        gstNumber: readStringOrEmpty(m, 'gstNumber'),
        isDefaultShipping: readBool(m, 'isDefaultShipping'),
        isDefaultBilling: readBool(m, 'isDefaultBilling'),
        isWorkAddress: readBool(m, 'isWorkAddress'),
        createdAt: readDate(m, 'createdAt'),
        updatedAt: readDate(m, 'updatedAt'),
      );

  Map<String, Object?> toWriteMap() => compact(<String, Object?>{
        'uid': uid,
        'name': name,
        'phone': phone,
        'line1': line1,
        'line2': line2,
        'city': city,
        'state': state,
        'pincode': pincode,
        'gstNumber': gstNumber,
        'isDefaultShipping': isDefaultShipping,
        'isDefaultBilling': isDefaultBilling,
        'isWorkAddress': isWorkAddress,
      });

  AddressBookEntry copyWith({
    String? name,
    String? phone,
    String? line1,
    String? line2,
    String? city,
    String? state,
    String? pincode,
    String? gstNumber,
    bool? isDefaultShipping,
    bool? isDefaultBilling,
    bool? isWorkAddress,
  }) =>
      AddressBookEntry(
        id: id,
        uid: uid,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        line1: line1 ?? this.line1,
        line2: line2 ?? this.line2,
        city: city ?? this.city,
        state: state ?? this.state,
        pincode: pincode ?? this.pincode,
        gstNumber: gstNumber ?? this.gstNumber,
        isDefaultShipping: isDefaultShipping ?? this.isDefaultShipping,
        isDefaultBilling: isDefaultBilling ?? this.isDefaultBilling,
        isWorkAddress: isWorkAddress ?? this.isWorkAddress,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}
