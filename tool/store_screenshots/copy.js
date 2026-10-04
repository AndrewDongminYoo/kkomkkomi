// The words of the store images: the headline and the line under it for each screenshot, and the product line of the
// Play feature graphic, in Korean and in English. frame.html and feature.html read it; render.sh reads the screen
// names from the raw files, so each raw screen needs an entry here.
//
// Text between two asterisks shows in the accent color. Describe only features that M1 ships.
window.STORE_COPY = {
  screens: {
    "01_capture": {
      ko: {
        headline: "구역마다 *전후 사진*을 찍어요",
        sub: "지난 방문 사진도 함께 보여요",
      },
      en: {
        headline: "Take *before and after* photos of each zone",
        sub: "Photos from the last visit appear alongside",
      },
    },
    "02_report": {
      ko: {
        headline: "보고서를 *링크나 PDF*로 보내요",
        sub: "거래처는 링크 하나로 지난 보고서까지 볼 수 있어요",
      },
      en: {
        headline: "Send the report as *a link or a PDF*",
        sub: "Clients open every past report from one link",
      },
    },
    "03_client": {
      ko: {
        headline: "한 번 저장한 *구역*을 방문마다 불러와요",
        sub: "다음 방문도 같은 구역으로 시작해요",
      },
      en: {
        headline: "Your *zones* carry over to every visit",
        sub: "The next visit starts with the same zones",
      },
    },
    "04_clients": {
      ko: {
        headline: "*거래처*를 한곳에서 관리해요",
        sub: "거래처마다 구역과 방문 기록을 따로 모아요",
      },
      en: {
        headline: "Keep every *client* in one place",
        sub: "Each client keeps its own zones and visits",
      },
    },
  },
  feature: {
    ko: {
      name: "꼼꼬미",
      line: "청소 *전후 사진*을 거래처 보고서로",
      before: "청소 전",
      after: "청소 후",
    },
    en: {
      name: "Kkomkkomi",
      line: "Cleaning reports with *before and after* photos",
      before: "Before",
      after: "After",
    },
  },
};
