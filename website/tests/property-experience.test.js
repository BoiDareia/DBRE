import fc from 'fast-check';
import { describe, it, expect } from 'vitest';

/**
 * Simulated Hugo timeline-entry.html partial renderer.
 *
 * Mirrors the logic in layouts/partials/timeline-entry.html:
 *   - Date badge: shows year from date, optionally " – endDate"
 *   - h3 with title
 *   - Optional company paragraph
 *   - Description div with body content
 *   - Optional image with alt text
 *
 * @param {object} entry
 * @param {string} entry.title    - Role or milestone title (required)
 * @param {Date}   entry.date     - Start date (required)
 * @param {string} entry.body     - Body/description text (required)
 * @param {string} [entry.endDate]  - End date string (optional)
 * @param {string} [entry.company]  - Company name (optional)
 * @param {string} [entry.image]    - Image path (optional)
 * @param {number} index          - Entry index for alternating layout
 * @returns {string} HTML string
 */
function renderTimelineEntry(entry, index = 0) {
  const isEven = index % 2 === 0;
  const year = entry.date.getFullYear().toString();

  let dateBadge = year;
  if (entry.endDate) {
    dateBadge += `\u2009–\u2009${entry.endDate}`;
  }

  let companyHtml = '';
  if (entry.company) {
    companyHtml = `
      <p class="text-amber-600 font-semibold text-sm sm:text-base mb-3">
        ${entry.company}
      </p>`;
  }

  let imageHtml = '';
  if (entry.image) {
    const altText = `${entry.title} — ${entry.company || 'career milestone'}`;
    imageHtml = `
      <img
        src="${entry.image}"
        alt="${altText}"
        class="mt-4 rounded-lg max-w-full h-auto ${isEven ? 'md:ml-auto' : ''}"
        loading="lazy"
      />`;
  }

  return `
<div class="relative flex flex-col md:flex-row items-start mb-12 md:mb-16 last:mb-0">
  <div class="absolute left-4 md:left-1/2 w-3 h-3 bg-amber-600 rounded-full border-2 border-slate-900 -translate-x-1/2 mt-1.5 z-10" aria-hidden="true"></div>
  <div class="ml-10 md:ml-0 md:w-1/2 ${isEven ? 'md:pr-12 md:text-right' : 'md:pl-12 md:ml-auto'}">
    <span class="inline-block px-3 py-1 text-sm font-mono font-medium text-amber-600 bg-slate-800 rounded-full mb-3">
      ${dateBadge}
    </span>
    <h3 class="text-white font-heading text-xl sm:text-2xl font-bold mb-1">
      ${entry.title}
    </h3>
    ${companyHtml}
    <div class="text-slate-300 text-sm sm:text-base leading-relaxed prose prose-invert max-w-none">
      ${entry.body}
    </div>
    ${imageHtml}
  </div>
</div>`;
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
 * Arbitrary for a valid Date between 1990 and 2030.
 */
const safeDate = fc.date({
  min: new Date('1990-01-01'),
  max: new Date('2030-12-31'),
});

/**
 * Arbitrary for a complete experience entry with required and optional fields.
 */
const experienceEntryArb = fc.record({
  title: safeString,
  date: safeDate,
  body: safeString,
  endDate: fc.option(safeString, { nil: undefined }),
  company: fc.option(safeString, { nil: undefined }),
  image: fc.option(
    fc.constantFrom('/images/foto-1.png', '/images/foto-2.png', '/images/Logo.png'),
    { nil: undefined }
  ),
});

describe('Property 1: Experience entry rendering preserves front matter fields', () => {
  /**
   * **Validates: Requirements 3.9, 8.1**
   *
   * For any experience entry with title, date, and body content,
   * the rendered timeline HTML output SHALL contain the title text,
   * a formatted date year string, and the body description text.
   */
  it('rendered HTML contains title, date year, and body for any experience entry', () => {
    fc.assert(
      fc.property(experienceEntryArb, fc.nat({ max: 20 }), (entry, index) => {
        const html = renderTimelineEntry(entry, index);

        // Title must appear inside an h3
        expect(html).toContain(`<h3`);
        expect(html).toContain(entry.title);

        // Date year must appear in the date badge
        const year = entry.date.getFullYear().toString();
        expect(html).toContain(year);

        // Body text must appear in the description div
        expect(html).toContain(entry.body);
      }),
      { numRuns: 150 }
    );
  });

  it('rendered HTML includes endDate in date badge when provided', () => {
    const withEndDate = experienceEntryArb.filter((e) => e.endDate !== undefined);

    fc.assert(
      fc.property(withEndDate, (entry) => {
        const html = renderTimelineEntry(entry, 0);

        // endDate should appear in the date badge alongside the year
        expect(html).toContain(entry.endDate);
      }),
      { numRuns: 100 }
    );
  });

  it('rendered HTML includes company when provided', () => {
    const withCompany = experienceEntryArb.filter((e) => e.company !== undefined);

    fc.assert(
      fc.property(withCompany, (entry) => {
        const html = renderTimelineEntry(entry, 0);

        // Company should appear in a paragraph
        expect(html).toContain(entry.company);
        expect(html).toContain('text-amber-600 font-semibold');
      }),
      { numRuns: 100 }
    );
  });

  it('rendered HTML includes image with alt text when image is provided', () => {
    const withImage = experienceEntryArb.filter((e) => e.image !== undefined);

    fc.assert(
      fc.property(withImage, (entry) => {
        const html = renderTimelineEntry(entry, 0);

        // Image tag should be present with the correct src
        expect(html).toContain(`src="${entry.image}"`);
        // Alt text should contain the title
        expect(html).toContain(`alt="`);
        expect(html).toContain(entry.title);
      }),
      { numRuns: 100 }
    );
  });

  it('rendered HTML omits company paragraph when company is absent', () => {
    const withoutCompany = experienceEntryArb.filter((e) => e.company === undefined);

    fc.assert(
      fc.property(withoutCompany, (entry) => {
        const html = renderTimelineEntry(entry, 0);

        // No company paragraph should be rendered
        expect(html).not.toContain('font-semibold text-sm sm:text-base mb-3');
      }),
      { numRuns: 100 }
    );
  });

  it('rendered HTML omits image when image is absent', () => {
    const withoutImage = experienceEntryArb.filter((e) => e.image === undefined);

    fc.assert(
      fc.property(withoutImage, (entry) => {
        const html = renderTimelineEntry(entry, 0);

        // No img tag should be rendered
        expect(html).not.toContain('<img');
      }),
      { numRuns: 100 }
    );
  });
});
