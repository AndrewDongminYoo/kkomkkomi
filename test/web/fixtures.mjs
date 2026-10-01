// Documents as the Firestore REST API gives them, in the shape that `FirebasePublisher` writes: a client page and two
// reports under it. The configuration is the shape of /__/firebase/init.json, with values that name no real project.

export const pageId = "0123456789abcdef0123456789abcdef";
export const visitId = "fedcba9876543210fedcba9876543210";
export const olderVisitId = "00112233445566778899aabbccddeeff";

export const config = {
  projectId: "demo-kkomkkomi",
  storageBucket: "demo-kkomkkomi.appspot.com",
  apiKey: "fixture-key",
};

const documents = "projects/demo-kkomkkomi/databases/(default)/documents";

const string = (value) => ({ stringValue: value });
const timestamp = (value) => ({ timestampValue: value });

export const pageDocument = {
  name: `${documents}/clientPages/${pageId}`,
  fields: {
    ownerUid: string("owner-uid"),
    companyName: string("깔끔클린"),
    clientName: string("행복빌딩"),
    createdAt: timestamp("2026-09-01T00:00:00Z"),
  },
};

function zone(name, note, beforePhoto, afterPhoto) {
  return {
    mapValue: {
      fields: {
        name: string(name),
        note: string(note),
        beforePhoto:
          beforePhoto === null ? { nullValue: null } : string(beforePhoto),
        afterPhoto:
          afterPhoto === null ? { nullValue: null } : string(afterPhoto),
      },
    },
  };
}

export const lobbyBefore = `clientPages/${pageId}/${visitId}/zone-1-before-a.jpg`;
export const lobbyAfter = `clientPages/${pageId}/${visitId}/zone-1-after-b.jpg`;
export const hallBefore = `clientPages/${pageId}/${visitId}/zone-2-before-c.jpg`;

export const reportDocument = {
  name: `${documents}/clientPages/${pageId}/reports/${visitId}`,
  fields: {
    visitDate: string("2026-10-01"),
    publishedAt: timestamp("2026-10-01T09:00:00Z"),
    zones: {
      arrayValue: {
        values: [
          zone("로비", "바닥 왁스\n유리문 닦음", lobbyBefore, lobbyAfter),
          zone("복도", "", hallBefore, null),
          zone("탕비실", "공사 중이라 사진을 못 찍었어요", null, null),
        ],
      },
    },
  },
};

export const olderReportDocument = {
  name: `${documents}/clientPages/${pageId}/reports/${olderVisitId}`,
  fields: {
    visitDate: string("2026-09-24"),
    publishedAt: timestamp("2026-09-24T09:00:00Z"),
    zones: { arrayValue: { values: [zone("로비", "", null, null)] } },
  },
};
