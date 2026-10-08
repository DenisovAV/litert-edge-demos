import 'package:flutter_test/flutter_test.dart';
import 'package:litert_hackathon/utils/spoken_numbers.dart';

void main() {
  test('numbers as words', () {
    expect(numberToWords(0), 'zero');
    expect(numberToWords(7), 'seven');
    expect(numberToWords(17), 'seventeen');
    expect(numberToWords(20), 'twenty');
    expect(numberToWords(25), 'twenty-five');
    expect(numberToWords(90), 'ninety');
    expect(numberToWords(105), 'one hundred five');
    expect(numberToWords(850), 'eight hundred fifty');
    expect(numberToWords(2300), 'two thousand three hundred');
    expect(numberToWords(86400), 'eighty-six thousand four hundred');
    expect(numberToWords(-3), 'minus three');
  });

  test('joinWords', () {
    expect(joinWords(const []), '');
    expect(joinWords(const ['a']), 'a');
    expect(joinWords(const ['a', 'b']), 'a and b');
    expect(joinWords(const ['a', 'b', 'c']), 'a, b and c');
  });
}
