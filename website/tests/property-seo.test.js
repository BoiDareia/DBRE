import fc from 'fast-check';
import { describe, it, expect } from 'vitest';

/**
 * Simulated Hugo seo.html partial renderer.
 *
 * Mirrors the logic in layouts/partials/seo.html:
 *   - $title = page title or site title fallback
 *   - $description = page description or site description fallback
 *   - meta name="description" content="$description"
 *   - link rel="canonical" href="permalink"
 *   - meta property="og:title" content="$title"
 *   - meta property="og:description" content="$description"
 *   - meta property="og:image" content="ogImage absURL"
 *   - meta property="og:url" content="permalink"
 *   - meta property="og:type" content="website"
 *   - meta name="twitter:card" content="summary_large_image"
 *   - meta name="twitter:title" content="$title"
 *   - meta name="twitter:description" content="$description"
 *
 * @param {object} page
 * @param {string} [page.title]       - Page title (optional, falls back to site title)
 * @param {string} [page.description] - Page description (optional, falls back to site description)
 * @param {string} page.permalink     - Canonical URL for the page
 * @param {object} site
 * @param {string} site.title         - Site-level title fallback
 * @param {string} site.description   - Site-level description fallback
 * @param {string} [site.ogImage]     - OG image path (optional)
 * @returns {string} HTML string of meta tags
 */
function renderSeoMeta(page, site) {
  const title = page.title || site.title;
  const description = page.description || site.description;

  let html = '';

  // Meta description
  if (description) {
    html += `<meta name="description" content="${description}">\n`;
  }

  // Canonical URL
  html += `<link rel="canonical" href="${page.permalink}">\n`;

  // OpenGraph meta tags
  html += `<meta property="og:title" content="${title}">\n`;
  if (description) {
    html += `<meta property="og:description" content="${description}">\n`;
  }
  if (site.ogImage) {
    const absUrl = page.permalink.replace(/\/[^/]*$/, '/') + site.ogImage;
    html += `<meta property="og:image" content="${absUrl}">\n`;
  }
  html += `<meta property="og:url" content="${page.permalink}">\n`;
  html += `<meta property="og:type" content="website">\n`;

  // Twitter Card meta tags
  html += `<meta name="twitter:card" content="summary_large_image">\n`;
  html += `<meta name="twitter:title" content="${title}">\n`;
  if (description) {
    html += `<meta name="twitter:description" content="${description}">\n`;
  }

  return html;
}

/**
 * Arbitrary for safe alphanumeric strings (letters, digits, spaces).
 * Avoids HTML special characters that would break assertion matching.
 * Uses fc.stringMatching (fast-check v4 compatible).
 */
const safeString = fc.stringMatching(/^[a-zA-Z0-9 ]{1,80}$/).filter(
  (s) => s.trim().length > 0
);

/**
 * Arbitrary for a safe URL string.
 */
const safeUrl = fc
  .stringMatching(/^[a-zA-Z0-9]{1,30}$/)
  .filter((s) => s.trim().length > 0)
  .map((s) => `https://www.makitall.com/${s}`);

/**
 * Arbitrary for page data with optional title and description.
 */
const pageArb = fc.record({
  title: fc.option(safeString, { nil: undefined }),
  description: fc.option(safeString, { nil: undefined }),
  permalink: safeUrl,
});

/**
 * Arbitrary for site-level data with required title and description.
 */
const siteArb = fc.record({
  title: safeString,
  description: safeString,
  ogImage: fc.option(
    fc.constantFrom('images/Logo.png', 'images/foto-1.png'),
    { nil: undefined }
  ),
});

describe('Property 5: SEO meta tags generated from page data', () => {
  /**
   * **Validates: Requirements 13.1**
   *
   * For any page with a title and description (or site-level fallback),
   * the rendered HTML <head> SHALL contain og:title, og:description,
   * twitter:card, and twitter:title meta tags whose content values
   * correspond to the page's title and description.
   */
  it('rendered SEO HTML contains og:title, og:description, twitter:card, and twitter:title with correct values for any page data', () => {
    fc.assert(
      fc.property(pageArb, siteArb, (page, site) => {
        const html = renderSeoMeta(page, site);

        const expectedTitle = page.title || site.title;
        const expectedDescription = page.description || site.description;

        // og:title must contain the resolved title
        expect(html).toContain(`<meta property="og:title" content="${expectedTitle}">`);

        // og:description must contain the resolved description
        expect(html).toContain(`<meta property="og:description" content="${expectedDescription}">`);

        // twitter:card must be summary_large_image
        expect(html).toContain('<meta name="twitter:card" content="summary_large_image">');

        // twitter:title must contain the resolved title
        expect(html).toContain(`<meta name="twitter:title" content="${expectedTitle}">`);
      }),
      { numRuns: 150 }
    );
  });

  it('rendered SEO HTML contains meta description with correct value', () => {
    fc.assert(
      fc.property(pageArb, siteArb, (page, site) => {
        const html = renderSeoMeta(page, site);

        const expectedDescription = page.description || site.description;

        // meta description must be present with the resolved description
        expect(html).toContain(`<meta name="description" content="${expectedDescription}">`);
      }),
      { numRuns: 100 }
    );
  });

  it('rendered SEO HTML contains canonical URL matching the permalink', () => {
    fc.assert(
      fc.property(pageArb, siteArb, (page, site) => {
        const html = renderSeoMeta(page, site);

        // Canonical link must reference the page permalink
        expect(html).toContain(`<link rel="canonical" href="${page.permalink}">`);

        // og:url must also match the permalink
        expect(html).toContain(`<meta property="og:url" content="${page.permalink}">`);
      }),
      { numRuns: 100 }
    );
  });

  it('rendered SEO HTML uses page title when provided, site title as fallback', () => {
    fc.assert(
      fc.property(pageArb, siteArb, (page, site) => {
        const html = renderSeoMeta(page, site);

        if (page.title) {
          // When page title is provided, it should appear in og:title and twitter:title
          expect(html).toContain(`<meta property="og:title" content="${page.title}">`);
          expect(html).toContain(`<meta name="twitter:title" content="${page.title}">`);
        } else {
          // When page title is absent, site title should be used as fallback
          expect(html).toContain(`<meta property="og:title" content="${site.title}">`);
          expect(html).toContain(`<meta name="twitter:title" content="${site.title}">`);
        }
      }),
      { numRuns: 100 }
    );
  });

  it('rendered SEO HTML uses page description when provided, site description as fallback', () => {
    fc.assert(
      fc.property(pageArb, siteArb, (page, site) => {
        const html = renderSeoMeta(page, site);

        if (page.description) {
          // When page description is provided, it should appear in og:description and twitter:description
          expect(html).toContain(`<meta property="og:description" content="${page.description}">`);
          expect(html).toContain(`<meta name="twitter:description" content="${page.description}">`);
        } else {
          // When page description is absent, site description should be used as fallback
          expect(html).toContain(`<meta property="og:description" content="${site.description}">`);
          expect(html).toContain(`<meta name="twitter:description" content="${site.description}">`);
        }
      }),
      { numRuns: 100 }
    );
  });

  it('rendered SEO HTML contains og:type set to website', () => {
    fc.assert(
      fc.property(pageArb, siteArb, (page, site) => {
        const html = renderSeoMeta(page, site);

        expect(html).toContain('<meta property="og:type" content="website">');
      }),
      { numRuns: 100 }
    );
  });

  it('rendered SEO HTML includes twitter:description with correct value', () => {
    fc.assert(
      fc.property(pageArb, siteArb, (page, site) => {
        const html = renderSeoMeta(page, site);

        const expectedDescription = page.description || site.description;

        expect(html).toContain(`<meta name="twitter:description" content="${expectedDescription}">`);
      }),
      { numRuns: 100 }
    );
  });

  it('rendered SEO HTML includes og:image when site ogImage is configured', () => {
    const siteWithOgImage = siteArb.filter((s) => s.ogImage !== undefined);

    fc.assert(
      fc.property(pageArb, siteWithOgImage, (page, site) => {
        const html = renderSeoMeta(page, site);

        // og:image meta tag must be present
        expect(html).toContain('<meta property="og:image"');
        expect(html).toContain(site.ogImage);
      }),
      { numRuns: 100 }
    );
  });

  it('rendered SEO HTML omits og:image when site ogImage is not configured', () => {
    const siteWithoutOgImage = siteArb.filter((s) => s.ogImage === undefined);

    fc.assert(
      fc.property(pageArb, siteWithoutOgImage, (page, site) => {
        const html = renderSeoMeta(page, site);

        // og:image meta tag must NOT be present
        expect(html).not.toContain('og:image');
      }),
      { numRuns: 100 }
    );
  });
});
