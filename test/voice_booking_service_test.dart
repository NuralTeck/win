import 'package:flutter_test/flutter_test.dart';
import 'package:opscore_pro/features/bookings/services/voice_booking_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VoiceBookingService Parsing Tests', () {
    final service = VoiceBookingService.instance;

    test('1. Test Spoken Range (English: 56581 to 56585)', () async {
      final result = await service.parseSpokenTicketText(
        spokenText: 'Series 12 ticket 56581 to 56585',
        defaultSeries: '12',
        defaultSeller: 'Walk-in Customer',
        defaultPrice: 45.0,
      );

      expect(result.tickets.length, equals(5));
      expect(result.tickets.first.ticketNo, equals('56581'));
      expect(result.tickets.last.ticketNo, equals('56585'));
      expect(result.tickets.every((t) => t.series == '12'), isTrue);
    });

    test('2. Test Spoken Hindi Range (se: 28311 se 28314)', () async {
      final result = await service.parseSpokenTicketText(
        spokenText: '100 series 28311 se 28314',
        defaultSeries: '12',
        defaultSeller: 'Ramesh',
        defaultPrice: 375.0,
      );

      expect(result.tickets.length, equals(4));
      expect(result.tickets[0].ticketNo, equals('28311'));
      expect(result.tickets[1].ticketNo, equals('28312'));
      expect(result.tickets[2].ticketNo, equals('28313'));
      expect(result.tickets[3].ticketNo, equals('28314'));
      expect(result.tickets.every((t) => t.series == '100'), isTrue);
    });

    test('3. Test Shift and Customer Detection in Spoken Voice', () async {
      final result = await service.parseSpokenTicketText(
        spokenText: 'Customer Sonu Dear 6 PM Series 24 ticket 46185, 56185',
        defaultSeries: '12',
        defaultSeller: 'Walk-in Customer',
        defaultPrice: 90.0,
      );

      expect(result.detectedShift, equals('Dear 6 PM'));
      expect(result.detectedSeller?.toLowerCase(), contains('sonu'));
      expect(result.tickets.length, equals(2));
      expect(result.tickets[0].ticketNo, equals('46185'));
      expect(result.tickets[1].ticketNo, equals('56185'));
      expect(result.tickets.every((t) => t.series == '24'), isTrue);
    });

    test('4. Test Two-digit Shorthand Range (56576-81)', () async {
      final result = await service.parseSpokenTicketText(
        spokenText: 'Series 12 56576-81',
        defaultSeries: '12',
        defaultSeller: 'Walk-in Customer',
        defaultPrice: 45.0,
      );

      expect(result.tickets.length, equals(6));
      expect(result.tickets.first.ticketNo, equals('56576'));
      expect(result.tickets.last.ticketNo, equals('56581'));
    });

    test('5. Test Explicit 100% Offline Mode Parsing', () async {
      final result = await service.parseSpokenTicketText(
        spokenText: 'Series 36 number 12341 to 12345',
        defaultSeries: '12',
        defaultSeller: 'Walk-in Customer',
        defaultPrice: 135.0,
        overrideMode: 'offline',
      );

      expect(result.tickets.length, equals(5));
      expect(result.isOnlineAiUsed, isFalse);
      expect(result.tickets.first.ticketNo, equals('12341'));
      expect(result.tickets.last.ticketNo, equals('12345'));
      expect(result.tickets.every((t) => t.series == '36'), isTrue);
    });
  });
}
