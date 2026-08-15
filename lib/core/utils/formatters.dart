import 'package:intl/intl.dart';

class Formatters {
  Formatters._();

  static final NumberFormat currencyFormatter = NumberFormat.currency(
    symbol: '\$',
    decimalDigits: 2,
  );

  static final NumberFormat _inrFormatter = NumberFormat.currency(
    symbol: '₹',
    decimalDigits: 2,
    locale: 'en_IN',
  );

  static final NumberFormat compactCurrencyFormatter = NumberFormat.compactCurrency(
    symbol: '\$',
    decimalDigits: 1,
  );

  static final NumberFormat numberFormatter = NumberFormat.decimalPattern();

  static final DateFormat dateFormatter = DateFormat('MMM dd, yyyy');
  static final DateFormat dateTimeFormatter = DateFormat('MMM dd, yyyy • HH:mm');
  static final DateFormat timeFormatter = DateFormat('HH:mm:ss');

  static String formatCurrency(double amount) => currencyFormatter.format(amount);
  static String formatCompactCurrency(double amount) => compactCurrencyFormatter.format(amount);
  static String formatNumber(num value) => numberFormatter.format(value);
  static String formatDate(DateTime date) => dateFormatter.format(date);
  static String formatDateTime(DateTime date) => dateTimeFormatter.format(date);
  static String formatTime(DateTime date) => timeFormatter.format(date);

  /// Format as Indian Rupees — e.g. ₹4,82,900.00
  static String formatIndianCurrency(double amount) {
    if (amount >= 10000000) {
      return '₹${(amount / 10000000).toStringAsFixed(2)} Cr';
    } else if (amount >= 100000) {
      return '₹${(amount / 100000).toStringAsFixed(2)} L';
    }
    return _inrFormatter.format(amount);
  }

  /// Short Indian currency label — e.g. ₹18.4L
  static String formatCompactIndianCurrency(double amount) {
    if (amount >= 10000000) return '₹${(amount / 10000000).toStringAsFixed(1)} Cr';
    if (amount >= 100000) return '₹${(amount / 100000).toStringAsFixed(1)}L';
    if (amount >= 1000) return '₹${(amount / 1000).toStringAsFixed(1)}K';
    return '₹${amount.toStringAsFixed(0)}';
  }

  static String formatPercentage(double value, {bool includeSign = true}) {
    final formatted = value.abs().toStringAsFixed(1);
    if (!includeSign) return '$formatted%';
    final prefix = value >= 0 ? '+' : '-';
    return '$prefix$formatted%';
  }
}

