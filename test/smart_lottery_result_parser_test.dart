import 'package:flutter_test/flutter_test.dart';
import 'package:opscore_pro/features/operations/utils/lottery_result_parser.dart';

void main() {
  test('Smart filter accepts genuine 2024, 2025, 2026 winning numbers while ignoring date & banner years', () {
    const rawResultText = '''
NAGALAND STATE LOTTERIES
DEAR MORNING 1 PM
DRAW NO: 45 | DATE: 29/10/2026 | 1:00 PM
1st Prize: 82D 41997
Cons. Prize: 41997

2nd Prize Amount Rs. 9000/-
12345 23456 34567 45678 56789 67890 78901 89012 90123 01234

3rd Prize Amount Rs. 500/-
1111 2024 3333 4444 5555 6666 7777 8888 9999 1212

4th Prize Amount Rs. 250/-
2025 2222 3344 4455 5566 6677 7788 8899 9900 1313

DEAR DIWALI BUMPER 2026 LOTTERY
DRAW DATE: 12/11/2026 1ST PRIZE 1 CRORE

5th Prize Amount Rs. 120/-
2026 0001 0002 0003 0004 0005 0006 0007 0008 0009
0010 0011 0012 0013 0014 0015 0016 0017 0018 0019
0020 0021 0022 0023 0024 0025 0026 0027 0028 0029
0030 0031 0032 0033 0034 0035 0036 0037 0038 0039
0040 0041 0042 0043 0044 0045 0046 0047 0048 0049
0050 0051 0052 0053 0054 0055 0056 0057 0058 0059
0060 0061 0062 0063 0064 0065 0066 0067 0068 0069
0070 0071 0072 0073 0074 0075 0076 0077 0078 0079
0080 0081 0082 0083 0084 0085 0086 0087 0088 0089
0090 0091 0092 0093 0094 0095 0096 0097 0098 0099
''';

    final result = LotteryResultParser.parseSambadText(rawResultText);

    // 1. Draw date was correctly detected
    expect(result.drawDateStr, '29/10/2026');

    // 2. 3rd prize contains 2024
    print('3rd Prize numbers: ${result.thirdPrizeNumbers}');
    expect(result.thirdPrizeNumbers.contains('2024'), isTrue);

    // 3. 4th prize contains 2025
    print('4th Prize numbers: ${result.fourthPrizeNumbers}');
    expect(result.fourthPrizeNumbers.contains('2025'), isTrue);

    // 4. 5th prize contains 2026
    print('5th Prize contains 2026: ${result.fifthPrizeNumbers.contains('2026')}');
    expect(result.fifthPrizeNumbers.contains('2026'), isTrue);
  });
}

