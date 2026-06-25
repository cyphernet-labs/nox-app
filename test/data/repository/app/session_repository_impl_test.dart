import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/repository/app/session_repository_impl.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SessionRepositoryImpl repository;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    repository = SessionRepositoryImpl(const FlutterSecureStorage(), prefs);
  });

  test('reads a null session when no identifier is stored', () async {
    final result = await repository.readSession();
    expect(result.hasData, isTrue);
    expect(result.data, isNull);
  });

  test('saves the identifier and reads it back with label and onboarding flag', () async {
    await repository.saveIdentifier(identifier: 'abc', onboardingComplete: true, label: 'Alice');
    final session = (await repository.readSession()).data;
    expect(session, isNotNull);
    expect(session!.identifier, 'abc');
    expect(session.label, 'Alice');
    expect(session.onboardingComplete, isTrue);
  });

  test('persists onboardingComplete as false when signed in as a new identifier', () async {
    await repository.saveIdentifier(identifier: 'abc', onboardingComplete: false);
    expect((await repository.readSession()).data!.onboardingComplete, isFalse);
  });

  test('setOnboardingComplete flips the flag and caches the label', () async {
    await repository.saveIdentifier(identifier: 'abc', onboardingComplete: false);
    await repository.setOnboardingComplete(label: 'Bob');
    final session = (await repository.readSession()).data!;
    expect(session.onboardingComplete, isTrue);
    expect(session.label, 'Bob');
  });

  test('clear wipes the identifier so the session resolves to null', () async {
    await repository.saveIdentifier(identifier: 'abc', onboardingComplete: true, label: 'Alice');
    await repository.clear();
    expect((await repository.readSession()).data, isNull);
  });
}
