import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/domain/domain.dart';

void main() {
  group('CompanyProfile', () {
    test('trims the name', () {
      expect(CompanyProfile(name: ' 반짝 클린 ').name, '반짝 클린');
    });

    test('refuses a name that is empty after trimming', () {
      expect(() => CompanyProfile(name: '  '), throwsA(isA<EmptyNameException>()));
    });

    test('is equal to a profile with the same name', () {
      expect(CompanyProfile(name: '반짝 클린'), CompanyProfile(name: '반짝 클린'));
      expect(CompanyProfile(name: '반짝 클린').hashCode, CompanyProfile(name: '반짝 클린').hashCode);
      expect(CompanyProfile(name: '반짝 클린'), isNot(CompanyProfile(name: '다른 회사')));
    });
  });
}
