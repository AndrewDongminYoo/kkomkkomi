// Tests of the privacy policy under web/privacy/, run by `merry run web` without a browser.
//
// The pages are static HTML with one style sheet, so these tests read the files. Node has no layout engine, so the
// 320 px check here is a check of the sources: what can make a page wider than its screen (a fixed width, a table,
// a line that must not wrap, an image) is absent, and long words wrap. A browser measures the real width.

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, test } from "node:test";

import { privacyPath } from "../../web/report/view.js";

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

    test(`the ${lang} page holds nothing that is wider than a 320 px screen`, () => {
      const html = read(page.file);

      assert.match(
        html,
        /<meta\s+name="viewport"\s+content="width=device-width,initial-scale=1,viewport-fit=cover"\s*\/>/,
      );
      assert.doesNotMatch(html, /<table|<pre|<img|<video|<iframe|\swidth=/i);
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
