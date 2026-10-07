import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/domain/domain.dart';

void main() {
  group('CompanyProfile', () {
    test('trims an optional phone, preserves its punctuation, and includes it in equality', () {
      final profile = CompanyProfile(name: '반짝 클린', phone: ' +82 (2) 1234-5678 ');
      expect(profile.phone, '+82 (2) 1234-5678');
      expect(profile, CompanyProfile(name: '반짝 클린', phone: '+82 (2) 1234-5678'));
      expect(profile.hashCode, CompanyProfile(name: '반짝 클린', phone: '+82 (2) 1234-5678').hashCode);
      expect(profile, isNot(CompanyProfile(name: '반짝 클린')));
      expect(CompanyProfile(name: '반짝 클린', phone: '  ').phone, isEmpty);
    });
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
