import 'package:intl/intl.dart';

/// One date-shape vocabulary for the whole storefront, so an order card and an invoice cannot
/// disagree about when something happened.
abstract final class OmDates {
  static final DateFormat _date = DateFormat('d MMM yyyy');
  static final DateFormat _dateTime = DateFormat('d MMM yyyy, h:mm a');

  static String date(DateTime? value) => value == null ? '—' : _date.format(value);

  static String dateTime(DateTime? value) =>
      value == null ? '—' : _dateTime.format(value);
}
