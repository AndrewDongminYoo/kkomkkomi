// Tests of the privacy policy under web/privacy/, run by `merry run web` without a browser.
//
// The pages are static HTML with one style sheet, so these tests read the files. Node has no layout engine, so the
// 320 px check here is a check of the sources: what can make a page wider than its screen (a fixed width, a table,
// a line that must not wrap, an image) is absent, and long words wrap. A browser measures the real width.

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, test } from "node:test";

import { privacyPath, texts } from "../../web/report/view.js";

const repository = new URL("../../", import.meta.url);
const read = (path) => readFileSync(new URL(path, repository), "utf8");

const pages = {
  ko: {
    file: "web/privacy/index.html",
    path: "/privacy/",
    other: "/privacy/en/",
  },
  en: {
    file: "web/privacy/en/index.html",
    path: "/privacy/en/",
    other: "/privacy/",
  },
};

/** The privacy officer and the contact, which the operator gave on 2026-10-02. */
const officer = {
  ko: "유동민, ydm2790@gmail.com",
  en: "Dongmin Yu (유동민), ydm2790@gmail.com",
};

/**
 * The words with which each page names the status of a zone and its reason, which the phone keeps for each zone and
 * which a report carries for a zone that is partly done or not done.
 */
const zoneStatus = {
  ko: { reason: "사유", labels: ["일부 완료", "못 함"] },
  en: { reason: "reason", labels: ["partly done", "not done"] },
};

/** The section that describes the deletion of all data in the app. */
const deletionSection = (html) => {
  const startHeading = '<h2 id="delete">';
  const endHeading = '<h2 id="uninstall">';
  const start = html.indexOf(startHeading);
  const end = html.indexOf(endHeading);
  assert.ok(start >= 0, `the page has no ${startHeading} heading`);
  assert.ok(end >= 0, `the page has no ${endHeading} heading`);
  assert.ok(end > start, `${endHeading} does not follow ${startHeading}`);
  return html.slice(start, end);
};

/** The text of the section with [id], with the line breaks of the formatter folded into spaces. */
const sectionText = (html, id) => {
  const start = html.indexOf(`<h2 id="${id}">`);
  const end = html.indexOf("<h2", start + 1);
  assert.ok(
    start >= 0 && end > start,
    `the page has no <h2 id="${id}"> section`,
  );
  return html.slice(start, end).replace(/\s+/g, " ");
};

/**
 * What each page says about RevenueCat, which the plans screen of the app reaches from pull request 4a of M3, and the
 * add control of the client list at 2 or more active clients from pull request 4b.
 */
const revenueCat = {
  ko: {
    contact: "RevenueCat, Inc. 연락처: compliance@revenuecat.com",
    linked: "구입 내역은 그 사용자 ID와 연결됩니다",
    remains: "RevenueCat의 고객 기록",
    newAccount:
      '정식 버전 앱에서 요금제 화면을 열거나 보관하지 않은 거래처가 2곳 이상인 상태에서 "거래처 추가하기"를 누를 때 새 익명 계정으로 로그인합니다',
    googleWhen: "앱이 로그인할 때(2항, 6항)",
    googleToken:
      "앱이 방문 보고서 화면을 열어 유료 요금제인지 알려 주는 새 로그인 토큰을 요청할 때",
    googlePublishToken:
      "앱이 보고서를 링크로 공유하려고 올리면서(3항) 같은 이유로 새 로그인 토큰을 요청할 때",
    googleTokenData: "새 로그인 토큰을 요청할 때의 IP 주소",
    processor:
      "운영자는 구독 확인, 판매, 복원에 필요한 처리를 RevenueCat에 맡깁니다.",
    when: '정식 버전 앱에서 요금제 화면을 열 때, 보관하지 않은 거래처가 2곳 이상인 상태에서 "거래처 추가하기"를 누를 때, 구독을 사거나 복원할 때 인터넷으로 전송.',
    sync: "이 중 하나로 RevenueCat에 한 번 연결한 뒤에는 앱이 완전히 종료될 때까지 RevenueCat SDK가 주기적으로, 그리고 앱이 다시 화면에 나타날 때마다 구독 상태를 동기화하며 전송",
    onlyWhen: /할 때만/,
    refuse:
      '요금제 화면을 열지 않고, 보관하지 않은 거래처가 2곳 이상인 상태에서 "거래처 추가하기"를 누르지 않고, 구독을 사지 않으면 이전되지 않습니다.',
    deletion: "모든 데이터 지우기(6항)는 RevenueCat에 연결하지 않습니다.",
    noRefusal: /거부하는 방법은 지금 없습니다/,
  },
  en: {
    contact: "RevenueCat, Inc. Contact: compliance@revenuecat.com",
    linked: "the purchase history is linked to that user ID",
    remains: "The customer record at RevenueCat",
    newAccount:
      'or, in the release version, opens the plans screen or gets a tap on "Add Client" while 2 or more clients are not archived (section 2)',
    googleWhen: "when the app signs in (sections 2 and 6)",
    googleToken:
      "when the app opens the screen of a visit report and asks for a new sign-in token, which tells whether the company has a paid plan",
    googlePublishToken:
      "when the app uploads a report to share it as a link (section 3) and asks for a new sign-in token for the same reason",
    googleTokenData: "the IP address of each request for a new sign-in token",
    processor: "The operator entrusts RevenueCat with the processing",
    when: 'when the release version of the app opens the plans screen, when "Add Client" is tapped while 2 or more clients are not archived, and when a subscription is bought or restored.',
    sync: "After the first of these, the RevenueCat SDK also syncs the subscription state periodically and each time the app comes back to the foreground, until the app is closed completely.",
    onlyWhen: /only when/,
    refuse:
      'Not opening the plans screen, not tapping "Add Client" while 2 or more clients are not archived, and not buying a subscription avoids this transfer.',
    deletion: "Delete All Data (section 6) does not contact RevenueCat.",
    noRefusal: /no way to refuse/,
  },
};

/** The IDs of the sections of a page, in order. */
const sectionIds = (html) =>
  [...html.matchAll(/<h2 id="([^"]+)"/g)].map((match) => match[1]);

describe("the privacy policy pages", () => {
  for (const [lang, page] of Object.entries(pages)) {
    test(`the ${lang} page names its language and links to the other one`, () => {
      const html = read(page.file);

      assert.match(html, new RegExp(`<html lang="${lang}">`));
      assert.match(html, new RegExp(`<a href="${page.other}"`));
      // Each page lists every language version, itself included, by its full URL.
      const alternates = [
        ...html.matchAll(
          /<link\s+rel="alternate"\s+hreflang="([a-z-]+)"\s+href="([^"]+)"\s*\/>/g,
        ),
      ].map(([, hreflang, href]) => [hreflang, href]);
      assert.deepEqual(alternates, [
        ["ko", `https://kkomkkomi.web.app${pages.ko.path}`],
        ["en", `https://kkomkkomi.web.app${pages.en.path}`],
        ["x-default", `https://kkomkkomi.web.app${pages.ko.path}`],
      ]);
    });

    test(`the ${lang} page runs no script, and loads only its own style sheet`, () => {
      const html = read(page.file);

      assert.doesNotMatch(
        html,
        /<script|<iframe|<style|\sstyle="|\son[a-z]+=/i,
      );
      assert.match(
        html,
        /<link rel="stylesheet" href="\/privacy\/privacy\.css" \/>/,
      );
      assert.match(html, /default-src 'none'; style-src 'self';/);
      assert.doesNotMatch(
        html,
        /script-src|unsafe-inline|unsafe-eval|https?:\/\/(?!kkomkkomi\.web\.app)/,
      );
    });

    test(`the ${lang} page names the privacy officer and the contact, at the top and in the last section`, () => {
      const html = read(page.file);
      const header = html.slice(0, html.indexOf("</header>"));
      const rights = html.slice(html.indexOf('<h2 id="rights">'));

      assert.ok(header.includes(officer[lang]));
      assert.ok(rights.includes(officer[lang]));
    });

    test(`the ${lang} page lists the four steps of the deletion in the app, in their order`, () => {
      const steps = [
        ...deletionSection(read(page.file)).matchAll(/<li>([\s\S]*?)<\/li>/g),
      ]
        .slice(0, 4)
        // The line breaks of the formatter folded into spaces.
        .map((match) => match[1].replace(/\s+/g, " "));

      assert.equal(steps.length, 4);
      assert.match(steps[0], /Cloud Storage/);
      assert.match(steps[1], /Cloud Firestore/);
      assert.match(steps[2], /Firebase Authentication/);
      assert.doesNotMatch(steps[3], /Firebase|Cloud/);
    });

    test(`the ${lang} page lists the mark of a report without the footer text among what a link share sends`, () => {
      const html = read(page.file);
      const start = html.indexOf('<h2 id="publish">');
      const end = html.indexOf("<h2", start + 1);
      assert.ok(
        start >= 0 && end > start,
        'the page has no <h2 id="publish"> section',
      );
      // The line breaks of the formatter folded into spaces.
      const section = html.slice(start, end).replace(/\s+/g, " ");

      // `FirebasePublisher` writes `unbranded: true` into such a report, and the report page then leaves out this text.
      assert.ok(
        section.includes(`"${texts.footer}"`),
        `section 3 does not name "${texts.footer}"`,
      );
    });

    test(`the ${lang} page names the status and the reason of a zone wherever it lists the notes`, () => {
      const html = read(page.file);
      const words = zoneStatus[lang];

      // The phone database, a link share, the documents that stay after a revoke, and the deletion.
      for (const id of ["device", "publish", "revoke", "delete"]) {
        assert.ok(
          sectionText(html, id).includes(words.reason),
          `section ${id} does not name the reason`,
        );
      }
      // `FirebasePublisher` writes the status and the reason only for these two statuses.
      for (const id of ["device", "publish", "revoke"]) {
        for (const label of words.labels) {
          assert.ok(
            sectionText(html, id).includes(label),
            `section ${id} does not name "${label}"`,
          );
        }
      }
    });

    test(`the ${lang} page holds nothing that is wider than a 320 px screen`, () => {
      const html = read(page.file);

      assert.match(
        html,
        /<meta\s+name="viewport"\s+content="width=device-width,initial-scale=1,viewport-fit=cover"\s*\/>/,
      );
      assert.doesNotMatch(html, /<table|<pre|<img|<video|<iframe|\swidth=/i);
    });

    test(`the ${lang} page names RevenueCat as a recipient, the purchase history as linked, and what deletion leaves`, () => {
      const html = read(page.file);
      const words = revenueCat[lang];

      assert.ok(sectionText(html, "location").includes(words.contact));
      assert.ok(sectionText(html, "not-collected").includes(words.linked));
      assert.ok(sectionText(html, "delete").includes(words.remains));
      assert.ok(sectionText(html, "retention").includes(words.remains));
      // The plans screen and the add control at 2 or more active clients read the plan, which signs in with a new
      // anonymous account after Delete All Data.
      assert.ok(sectionText(html, "delete").includes(words.newAccount));
      assert.ok(sectionText(html, "location").includes(words.googleWhen));
      // The visit report screen asks Firebase for a newly issued ID token, which carries the claim of a paid plan, each
      // time it opens (lib/firebase/firebase_identity.dart), so the Google part names that request too.
      const google = sectionText(html, "location");
      const googlePart = google.slice(0, google.indexOf(words.processor));
      assert.ok(googlePart.includes(words.googleToken));
      // The publish queue asks for the same token before it writes each report (lib/application/publish_queue.dart).
      assert.ok(googlePart.includes(words.googlePublishToken));
      assert.ok(googlePart.includes(words.googleTokenData));
      // The company profile screen reads no plan, and the client list reads it only at 2 or more active clients, so a
      // person who never opens the plans screen and never asks for a client beyond the Free limit can refuse the
      // transfer to RevenueCat. The Google part before it keeps its sentence that the sign-in cannot be refused.
      const location = sectionText(html, "location");
      const start = location.indexOf(words.processor);
      assert.ok(start >= 0, "the section names no RevenueCat processing");
      const revenueCatPart = location.slice(start);
      assert.ok(revenueCatPart.includes(words.when));
      // The SDK stays configured after its first use, and RevenueCat updates CustomerInfo periodically and
      // when the app becomes active (https://www.revenuecat.com/docs/customers/customer-info, read on 2026-10-05).
      assert.ok(revenueCatPart.includes(words.sync));
      assert.doesNotMatch(revenueCatPart, words.onlyWhen);
      assert.ok(revenueCatPart.includes(words.refuse));
      assert.ok(revenueCatPart.includes(words.deletion));
      assert.doesNotMatch(revenueCatPart, words.noRefusal);
      assert.doesNotMatch(
        html.replace(/\s+/g, " "),
        /회사 정보 화면이나 요금제 화면|company profile screen or the plans screen/,
      );
      // The build of the plans screen sells subscriptions, so the sentence of pull request 2 is gone.
      assert.doesNotMatch(html, /구독을 판매하지 않으며|sells no subscription/);
    });
  }

  test("both pages have the same sections in the same order", () => {
    const ko = sectionIds(read(pages.ko.file));

    assert.ok(ko.length > 0);
    assert.deepEqual(sectionIds(read(pages.en.file)), ko);
  });

  test("neither page keeps a point for the operator to fill", () => {
    for (const page of Object.values(pages)) {
      const html = read(page.file);
      assert.doesNotMatch(
        html,
        /class="todo"|운영자 확인 필요|Operator to confirm/,
      );
    }
  });

  test("neither page says that an anonymous account is deleted after 30 days, which the operator turned off", () => {
    for (const page of Object.values(pages)) {
      assert.doesNotMatch(read(page.file), /30\s*일|30\s+days/);
    }
  });

  test("the style sheet sets no width that a 320 px screen cannot hold, and wraps long words", () => {
    const css = read("web/privacy/privacy.css");
    // Every length outside the `max-width` of the column and the media query of wide screens.
    const rules = css
      .replace(/\/\*[\s\S]*?\*\//g, "")
      .replace(/@media \(min-width: [^)]+\)/g, "");
    const declarations = rules
      .split(";")
      .filter((declaration) => !/max-width/.test(declaration));
    const lengths = declarations.flatMap((declaration) =>
      [
        ...declaration.matchAll(/(\d+(?:\.\d+)?)(px|rem|em|ch|ex|pt|vw|vh)\b/g),
      ].map(([, value, unit]) => ({
        declaration: declaration.trim(),
        // Pixels on a 320 x 640 screen with a 16 px font, counting `ch` and `ex` as a whole em.
        pixels:
          Number(value) *
          {
            px: 1,
            rem: 16,
            em: 16,
            ch: 16,
            ex: 16,
            pt: 4 / 3,
            vw: 3.2,
            vh: 6.4,
          }[unit],
      })),
    );

    for (const { declaration, pixels } of lengths)
      assert.ok(pixels < 160, declaration);
    assert.doesNotMatch(rules, /nowrap|min-width:\s*\d|(?<!max-)width:\s*\d/);
    assert.match(css, /body \{[^}]*overflow-wrap: anywhere;/);
  });

  test("Hosting serves the pages from web/ without a rewrite, and the report footer links to them", () => {
    const hosting = JSON.parse(read("firebase.json")).hosting;

    assert.equal(hosting.public, "web");
    assert.ok(
      hosting.rewrites.every(
        (rewrite) => !"/privacy/".startsWith(rewrite.source.replace("**", "")),
      ),
    );
    assert.equal(privacyPath, pages.ko.path);
    assert.ok(read(`web${pages.en.path}index.html`).length > 0);
  });
});
