import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/presentation/presentation.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/helpers.dart';

void main() {
  final now = DateTime.utc(2026, 10, 1, 9);
  final office = Client(id: 'client-a', name: '한빛 사무실', createdAt: DateTime.utc(2026, 9));
  final shop = Client(id: 'client-b', name: '새봄 매장', createdAt: DateTime.utc(2026, 9, 2));
  final failure = Exception('storage failed');

  late MockClientRepository clients;

  ClientListCubit build() =>
      ClientListCubit(clients: clients, idGenerator: SequenceIdGenerator(), clock: FixedClock(now));

  ClientListState ready({List<Client> clients = const [], NameEntry entry = NameEntry.editing}) =>
      ClientListState(status: ClientListStatus.ready, clients: clients, entry: entry);

  setUpAll(() => registerFallbackValue(office));

  setUp(() {
    clients = MockClientRepository();
    when(() => clients.save(any())).thenAnswer((_) async {});
  });

  group('ClientListState', () {
    test('is equal to a state with the same status, clients, and entry', () {
      expect(ready(clients: [office]), ready(clients: [office]));
      expect(ready(clients: [office]).hashCode, ready(clients: [office]).hashCode);
    });

    test('differs from a state with another status, client list, or entry', () {
      expect(ready(clients: [office]), isNot(ready(clients: [shop])));
      expect(ready(), isNot(ready(entry: NameEntry.saved)));
      expect(ready(), isNot(const ClientListState()));
    });
  });

  group('ClientListCubit', () {
    test('starts with no client while the first load runs', () {
      expect(build().state, const ClientListState());
      expect(build().state.status, ClientListStatus.loading);
    });

    group('load', () {
      blocTest<ClientListCubit, ClientListState>(
        'shows the active clients that storage holds',
        setUp: () => when(clients.activeClients).thenAnswer((_) async => [office, shop]),
        build: build,
        act: (cubit) => cubit.load(),
        expect: () => [
          ready(clients: [office, shop]),
        ],
      );

      blocTest<ClientListCubit, ClientListState>(
        'reports a failure of storage',
        setUp: () => when(clients.activeClients).thenThrow(failure),
        build: build,
        act: (cubit) => cubit.load(),
        expect: () => [const ClientListState(status: ClientListStatus.loadFailed)],
        errors: () => [failure],
      );

      blocTest<ClientListCubit, ClientListState>(
        'shows the loading state and then the clients when it runs again after a failure',
        setUp: () => when(clients.activeClients).thenAnswer((_) async => [office]),
        build: build,
        seed: () => const ClientListState(status: ClientListStatus.loadFailed),
        act: (cubit) => cubit.load(),
        expect: () => [
          const ClientListState(),
          ready(clients: [office]),
        ],
      );

      blocTest<ClientListCubit, ClientListState>(
        'keeps the list in place while it reads the clients again',
        setUp: () => when(clients.activeClients).thenAnswer((_) async => [shop]),
        build: build,
        seed: () => ready(clients: [office, shop]),
        act: (cubit) => cubit.load(),
        expect: () => [
          ready(clients: [shop]),
        ],
      );

      test('emits nothing when the cubit closes before storage answers', () async {
        final answer = Completer<List<Client>>();
        when(clients.activeClients).thenAnswer((_) => answer.future);
        final cubit = build();
        final states = <ClientListState>[];
        final subscription = cubit.stream.listen(states.add);

        final load = cubit.load();
        await cubit.close();
        answer.complete([office]);
        await load;
        await subscription.cancel();

        expect(states, isEmpty);
      });

      test('emits nothing when the cubit closes before storage fails', () async {
        final answer = Completer<List<Client>>();
        when(clients.activeClients).thenAnswer((_) => answer.future);
        final cubit = build();
        final states = <ClientListState>[];
        final subscription = cubit.stream.listen(states.add);

        final load = cubit.load();
        await cubit.close();
        answer.completeError(failure);
        await load;
        await subscription.cancel();

        expect(states, isEmpty);
      });
    });

    group('startNameEntry', () {
      blocTest<ClientListCubit, ClientListState>(
        'forgets the problem of the last submitted name',
        build: build,
        seed: () => ready(entry: NameEntry.empty),
        act: (cubit) => cubit.startNameEntry(),
        expect: () => [ready()],
      );
    });

    group('addClient', () {
      final added = Client(id: 'id-1', name: '다온 카페', createdAt: now);

      blocTest<ClientListCubit, ClientListState>(
        'saves a client with a new identifier, the trimmed name, and the time of the clock, and lists it last',
        build: build,
        seed: () => ready(clients: [office]),
        act: (cubit) => cubit.addClient('  다온 카페 '),
        expect: () => [
          ready(clients: [office], entry: NameEntry.saving),
          ready(clients: [office, added], entry: NameEntry.saved),
        ],
        verify: (_) => verify(() => clients.save(added)).called(1),
      );

      blocTest<ClientListCubit, ClientListState>(
        'refuses an empty name and saves nothing',
        build: build,
        seed: () => ready(clients: [office]),
        act: (cubit) => cubit.addClient('   '),
        expect: () => [
          ready(clients: [office], entry: NameEntry.empty),
        ],
        verify: (_) => verifyNever(() => clients.save(any())),
      );

      blocTest<ClientListCubit, ClientListState>(
        'reports a failure of storage and keeps the list as it was',
        setUp: () => when(() => clients.save(any())).thenThrow(failure),
        build: build,
        seed: () => ready(clients: [office]),
        act: (cubit) => cubit.addClient('다온 카페'),
        expect: () => [
          ready(clients: [office], entry: NameEntry.saving),
          ready(clients: [office], entry: NameEntry.failed),
        ],
        errors: () => [failure],
      );

      blocTest<ClientListCubit, ClientListState>(
        'takes no second name while the first is on its way to storage',
        build: build,
        seed: ready,
        act: (cubit) async {
          final first = cubit.addClient('다온 카페');
          await cubit.addClient('두 번째');
          await first;
        },
        expect: () => [
          ready(entry: NameEntry.saving),
          ready(clients: [added], entry: NameEntry.saved),
        ],
        verify: (_) => verify(() => clients.save(any())).called(1),
      );

      test('emits nothing more when the cubit closes before storage answers', () async {
        final answer = Completer<void>();
        when(() => clients.save(any())).thenAnswer((_) => answer.future);
        final cubit = build();

        final add = cubit.addClient('다온 카페');
        await cubit.close();
        answer.complete();
        await add;

        expect(cubit.state.entry, NameEntry.saving);
      });

      test('emits nothing more when the cubit closes before storage fails', () async {
        final answer = Completer<void>();
        when(() => clients.save(any())).thenAnswer((_) => answer.future);
        final cubit = build();

        final add = cubit.addClient('다온 카페');
        await cubit.close();
        answer.completeError(failure);
        await add;

        expect(cubit.state.entry, NameEntry.saving);
      });
    });
  });
}
