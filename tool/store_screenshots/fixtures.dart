import 'package:kkomkkomi/domain/domain.dart';

/// The fictional company, clients, zones, and visits that the store screenshots show in one language.
///
/// The repository is public, so every name and note is invented and plain.
final class StoreFixtures {
  const new({
    required this.companyName,
    required this.clientNames,
    required this.zoneNames,
    required this.notes,
  });

  /// The fixtures of the Korean screenshots.
  static const korean = StoreFixtures(
    companyName: '늘봄클린',
    clientNames: ['해오름빌딩 3층', '모아카페 성수점', '푸른숲치과', '한결디자인 스튜디오', '새봄학원', '정원빌딩 1층 상가', '미소약국', '다올부동산'],
    zoneNames: ['출입문', '탕비실', '화장실'],
    notes: ['유리문 손자국과 발매트 먼지를 닦았어요', '싱크대 물때를 지웠어요', '거울 물자국을 닦고 휴지를 채웠어요'],
  );

  /// The fixtures of the English screenshots.
  static const english = StoreFixtures(
    companyName: 'Brightside Cleaning',
    clientNames: [
      'Sunrise Tower, 3F',
      'Maple Cafe',
      'Greenwood Dental',
      'Northline Design Studio',
      'Riverside Academy',
      'Garden Plaza, 1F',
      'Smile Pharmacy',
      'Harbor Realty',
    ],
    zoneNames: ['Entrance', 'Kitchenette', 'Restroom'],
    notes: [
      'Wiped the glass doors and washed the mat',
      'Removed water stains from the sink',
      'Cleaned the mirror and refilled paper towels',
    ],
  );

  final String companyName;

  /// The names of the clients, in the order of the list. The first client is the one the other screens show.
  final List<String> clientNames;

  /// The zones of the first client, each with the scene of the fixture photos at the same index.
  final List<String> zoneNames;

  /// The note of each zone in the latest visit.
  final List<String> notes;

  /// The scenes of `photos.html`, one for each zone.
  static const scenes = ['entrance', 'pantry', 'restroom'];

  static const clientId = 'client-1';

  /// The visit that the capture and report screens show.
  static const latestVisitId = 'visit-3';

  List<Client> get clients => [
    for (final (index, name) in clientNames.indexed)
      Client(id: 'client-${index + 1}', name: name, createdAt: DateTime.utc(2026, 9, 1, index)),
  ];

  ClientZones get zones => ClientZones(
    clientId: clientId,
    zones: [
      for (final (index, name) in zoneNames.indexed)
        Zone(id: 'zone-${index + 1}', clientId: clientId, name: name, position: index),
    ],
  );

  /// Three weekly visits of the first client, the newest with a note in each zone.
  ///
  /// Every visit holds both photos of every zone, so that the capture screen shows the photos of the previous visit
  /// and the report screen lacks nothing.
  List<Visit> get visits => [
    for (final (index, date) in [VisitDate(2026, 9, 18), VisitDate(2026, 9, 25), VisitDate(2026, 10, 2)].indexed)
      Visit(
        id: 'visit-${index + 1}',
        clientId: clientId,
        visitDate: date,
        createdAt: DateTime.utc(date.year, date.month, date.day, 1),
        zoneRecords: [
          for (final (zone, name) in zoneNames.indexed)
            ZoneRecord(
              zoneId: 'zone-${zone + 1}',
              zoneName: name,
              beforePhoto: PhotoRef('${scenes[zone]}-before.jpg'),
              afterPhoto: PhotoRef('${scenes[zone]}-after.jpg'),
              note: index == 2 ? notes[zone] : '',
            ),
        ],
      ),
  ];
}
