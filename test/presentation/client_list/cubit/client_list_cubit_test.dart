// 🎯 Dart imports:
import 'dart:async';

// 📦 Package imports:
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// 🌎 Project imports:
import 'package:kkomkkomi/domain/domain.dart';
import 'package:kkomkkomi/presentation/presentation.dart';

import '../../../helpers/helpers.dart';

void main() {
  final now = DateTime.utc(2026, 10, 1, 9);
  final office = Client(id: 'client-a', name: '한빛 사무실', createdAt: DateTime.utc(2026, 9));
  final shop = Client(id: 'client-b', name: '새봄 매장', createdAt: DateTime.utc(2026, 9, 2));
  final failure = Exception('storage failed');

  late MockClientRepository clients;
  late FakeEntitlements entitlements;

  ClientListCubit build({Duration planTimeout = ClientListCubit.defaultPlanTimeout}) => ClientListCubit(
    clients: clients,
    entitlements: entitlements,
    idGenerator: SequenceIdGenerator(),
    clock: FixedClock(now),
    planTimeout: planTimeout,
  );

  ClientListState ready({
    List<Client> clients = const [],
    NameEntry entry = NameEntry.editing,
    ClientAddition addition = ClientAddition.idle,
    Plan? limitPlan,
  }) => ClientListState(
    status: ClientListStatus.ready,
    clients: clients,
    entry: entry,
    addition: addition,
    limitPlan: limitPlan,
  );

  /// [count] active clients, oldest first.
  List<Client> clientsOf(int count) => [
    for (var index = 0; index < count; index++)
      Client(id: 'client-$index', name: '거래처 $index', createdAt: DateTime.utc(2026, 9, 1 + index)),
  ];

  setUpAll(() => registerFallbackValue(office));

  setUp(() {
    clients = MockClientRepository();
    entitlements = FakeEntitlements();
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
      expect(ready(), isNot(ready(addition: ClientAddition.checking)));
      expect(ready(), isNot(ready(limitPlan: Plan.free)));
    });

    test('copyWith keeps the plan of the limit unless it is given, and forgets it for null', () {
      expect(
        ready(limitPlan: Plan.basic).copyWith(addition: ClientAddition.allowed),
        ready(limitPlan: Plan.basic, addition: ClientAddition.allowed),
      );
      expect(ready(limitPlan: Plan.basic).copyWith(limitPlan: () => null), ready());
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

      blocTest<ClientListCubit, ClientListState>(
        'forgets the plan whose limit stopped the last addition',
        setUp: () => when(clients.activeClients).thenAnswer((_) async => [office, shop]),
        build: build,
        seed: () => ready(clients: [office, shop], limitPlan: Plan.free),
        act: (cubit) => cubit.load(),
        expect: () => [
          ready(clients: [office, shop]),
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

    group('requestNewClient', () {
      for (final count in [0, 1]) {
        blocTest<ClientListCubit, ClientListState>(
          'allows a client with $count active clients without asking for the plan',
          build: build,
          seed: () => ready(clients: clientsOf(count)),
          act: (cubit) => cubit.requestNewClient(),
          expect: () => [
            ready(clients: clientsOf(count), addition: ClientAddition.checking),
            ready(clients: clientsOf(count), addition: ClientAddition.allowed),
          ],
          verify: (_) => expect(entitlements.touched, isEmpty),
        );
      }

      blocTest<ClientListCubit, ClientListState>(
        'stops a Free company with 2 active clients, and names the Free plan',
        build: build,
        seed: () => ready(clients: clientsOf(2)),
        act: (cubit) => cubit.requestNewClient(),
        expect: () => [
          ready(clients: clientsOf(2), addition: ClientAddition.checking),
          ready(clients: clientsOf(2), limitPlan: Plan.free),
        ],
        verify: (_) {
          expect(entitlements.touched, ['currentPlan']);
          verifyNever(() => clients.save(any()));
        },
      );

      blocTest<ClientListCubit, ClientListState>(
        'keeps every client of a company above the Free limit after a downgrade, and stops the next one',
        build: build,
        seed: () => ready(clients: clientsOf(3)),
        act: (cubit) => cubit.requestNewClient(),
        expect: () => [
          ready(clients: clientsOf(3), addition: ClientAddition.checking),
          ready(clients: clientsOf(3), limitPlan: Plan.free),
        ],
        verify: (_) => verifyNever(() => clients.save(any())),
      );

      test('lets a Basic company with 4 active clients add the fifth, and stops it at the sixth', () async {
        entitlements.plan = Plan.basic;
        final cubit = build()..emit(ready(clients: clientsOf(4)));

        await cubit.requestNewClient();
        expect(cubit.state.addition, ClientAddition.allowed);
        cubit.startNameEntry();
        await cubit.addClient('다섯째');
        await cubit.requestNewClient();

        final fifth = Client(id: 'id-1', name: '다섯째', createdAt: now);
        expect(cubit.state, ready(clients: [...clientsOf(4), fifth], entry: NameEntry.saved, limitPlan: Plan.basic));
        verify(() => clients.save(fifth)).called(1);
        expect(entitlements.calls, 3);
        await cubit.close();
      });

      test('lets a Pro company with 12 active clients add the thirteenth', () async {
        entitlements.plan = Plan.pro;
        final cubit = build()..emit(ready(clients: clientsOf(12)));

        await cubit.requestNewClient();
        expect(cubit.state.addition, ClientAddition.allowed);
        cubit.startNameEntry();
        await cubit.addClient('열셋째');

        expect(
          cubit.state,
          ready(
            clients: [
              ...clientsOf(12),
              Client(id: 'id-1', name: '열셋째', createdAt: now),
            ],
            entry: NameEntry.saved,
          ),
        );
        await cubit.close();
      });

      blocTest<ClientListCubit, ClientListState>(
        'forgets the plan of an earlier stop when the plan allows a client',
        setUp: () => entitlements.plan = Plan.basic,
        build: build,
        seed: () => ready(clients: clientsOf(2), limitPlan: Plan.free),
        act: (cubit) => cubit.requestNewClient(),
        expect: () => [
          ready(clients: clientsOf(2), addition: ClientAddition.checking, limitPlan: Plan.free),
          ready(clients: clientsOf(2), addition: ClientAddition.allowed),
        ],
      );

      test('waits for a late plan, past the timeout of a save, and allows the client that it allows', () async {
        entitlements
          ..plan = Plan.basic
          ..planGate = Completer<void>();
        final cubit = build(planTimeout: const Duration(milliseconds: 10))..emit(ready(clients: clientsOf(2)));

        final check = cubit.requestNewClient();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(cubit.state, ready(clients: clientsOf(2), addition: ClientAddition.checking));
        entitlements.planGate!.complete();
        await check;

        expect(cubit.state, ready(clients: clientsOf(2), addition: ClientAddition.allowed));
        await cubit.close();
      });

      test('does nothing for a second call while the plan is on its way', () async {
        entitlements.planGate = Completer<void>();
        final cubit = build()..emit(ready(clients: clientsOf(2)));

        final first = cubit.requestNewClient();
        await cubit.requestNewClient();
        entitlements.planGate!.complete();
        await first;

        expect(entitlements.calls, 1);
        expect(cubit.state, ready(clients: clientsOf(2), limitPlan: Plan.free));
        await cubit.close();
      });

      test('emits nothing more when the cubit closes before the plan answers', () async {
        entitlements.planGate = Completer<void>();
        final cubit = build()..emit(ready(clients: clientsOf(2)));

        final check = cubit.requestNewClient();
        await cubit.close();
        entitlements.planGate!.complete();
        await check;

        expect(cubit.state, ready(clients: clientsOf(2), addition: ClientAddition.checking));
      });
    });

    group('startNameEntry', () {
      blocTest<ClientListCubit, ClientListState>(
        'forgets the problem of the last submitted name and the allowed press that opened the dialog',
        build: build,
        seed: () => ready(entry: NameEntry.empty, addition: ClientAddition.allowed),
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
        'saves a client of a Free company with 1 active client without asking for the plan',
        build: build,
        seed: () => ready(clients: [office]),
        act: (cubit) => cubit.addClient('다온 카페'),
        expect: () => [
          ready(clients: [office], entry: NameEntry.saving),
          ready(clients: [office, added], entry: NameEntry.saved),
        ],
        verify: (_) => expect(entitlements.touched, isEmpty),
      );

      blocTest<ClientListCubit, ClientListState>(
        'refuses the client when the plan ended while the dialog was open, and saves nothing',
        setUp: () => entitlements.plan = Plan.basic,
        build: build,
        seed: () => ready(clients: clientsOf(4)),
        act: (cubit) async {
          await cubit.requestNewClient();
          cubit.startNameEntry();
          entitlements.plan = Plan.free;
          await cubit.addClient('다온 카페');
        },
        skip: 3,
        expect: () => [
          ready(clients: clientsOf(4), entry: NameEntry.saving),
          ready(clients: clientsOf(4), entry: NameEntry.limitReached, limitPlan: Plan.free),
        ],
        verify: (_) {
          expect(entitlements.calls, 2);
          verifyNever(() => clients.save(any()));
        },
      );

      test('fails the save without naming a plan, and saves nothing, when the plan does not answer in time', () async {
        entitlements.plan = Plan.basic;
        final cubit = build(planTimeout: const Duration(milliseconds: 10))..emit(ready(clients: clientsOf(4)));
        entitlements.planGate = Completer<void>();

        await cubit.addClient('다온 카페');

        expect(cubit.state, ready(clients: clientsOf(4), entry: NameEntry.failed));
        verifyNever(() => clients.save(any()));
        entitlements.planGate!.complete();
        await cubit.close();
      });

      test('emits nothing more when the cubit closes before the timeout of the plan', () async {
        entitlements.planGate = Completer<void>();
        final cubit = build(planTimeout: const Duration(milliseconds: 10))..emit(ready(clients: clientsOf(2)));

        final add = cubit.addClient('다온 카페');
        await cubit.close();
        await add;

        expect(cubit.state.entry, NameEntry.saving);
        verifyNever(() => clients.save(any()));
        entitlements.planGate!.complete();
      });

      test('emits nothing more and saves nothing when the cubit closes before the plan answers', () async {
        entitlements.planGate = Completer<void>();
        final cubit = build()..emit(ready(clients: clientsOf(2)));

        final add = cubit.addClient('다온 카페');
        await cubit.close();
        entitlements.planGate!.complete();
        await add;

        expect(cubit.state.entry, NameEntry.saving);
        verifyNever(() => clients.save(any()));
      });

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
        // The check of the limit comes first, so the save starts a turn later.
        await Future<void>.delayed(Duration.zero);
        verify(() => clients.save(any())).called(1);
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
        // The check of the limit comes first, so the save starts a turn later.
        await Future<void>.delayed(Duration.zero);
        verify(() => clients.save(any())).called(1);
        await cubit.close();
        answer.completeError(failure);
        await add;

        expect(cubit.state.entry, NameEntry.saving);
      });
    });
  });
}
