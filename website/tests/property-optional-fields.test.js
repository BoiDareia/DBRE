import fc from 'fast-check';
import { describe, it, expect } from 'vitest';

/**
 * Simulated Hugo timeline-entry.html partial renderer.
 *
 * Mirrors the logic in layouts/partials/timeline-entry.html using `with` blocks
 * for optional fields (endDate, company, image). When an optional field is absent,
 * the corresponding HTML block is omitted entirely.
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
 * Simulated Hugo project-card.html partial renderer.
 *
 * Mirrors the logic in layouts/partials/project-card.html using `with` blocks
 * for optional fields (summary, tags, link). When an optional field is absent,
 * the corresponding HTML block is omitted entirely.
 *
 * @param {object} project
 * @param {string} project.title     - Project name (required)
 * @param {string} [project.summary] - Brief description (optional)
 * @param {string[]} [project.tags]  - Technology names (optional)
 * @param {string} [project.link]    - External URL (optional)
 * @param {number} [project.weight]  - Display order (optional, not rendered)
 * @returns {string} HTML string
 */
function renderProjectCard(project) {
  let summaryHtml = '';
  if (project.summary) {
    summaryHtml = `
  <p class="text-slate-300 text-sm sm:text-base leading-relaxed mb-4">
    ${project.summary}
  </p>`;
  }

  let tagsHtml = '';
  if (project.tags && project.tags.length > 0) {
    const tagSpans = project.tags
      .map(
        (tag) =>
          `      <span class="inline-block px-3 py-1 text-xs sm:text-sm font-mono font-medium text-amber-600 bg-slate-900 rounded-full">
        ${tag}
      </span>`
      )
      .join('\n');
    tagsHtml = `
  <div class="flex flex-wrap gap-2 mb-4" aria-label="Technologies used">
${tagSpans}
  </div>`;
  }

  let linkHtml = '';
  if (project.link) {
    linkHtml = `
  <a
    href="${project.link}"
    target="_blank"
    rel="noopener noreferrer"
    class="inline-flex items-center gap-1 min-h-11 min-w-11 text-amber-600 hover:text-amber-500 font-semibold text-sm transition-colors focus:outline-none focus:ring-2 focus:ring-amber-400 focus:ring-offset-2 focus:ring-offset-slate-800"
  >
    View Project
    <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2" aria-hidden="true">
      <path stroke-linecap="round" stroke-linejoin="round" d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" />
    </svg>
  </a>`;
  }

  return `
<article class="break-inside-avoid mb-6 bg-slate-800 rounded-lg border-2 border-transparent hover:border-amber-600 transition-colors p-6">

  <h3 class="text-white font-heading text-xl sm:text-2xl font-bold mb-3">
    ${project.title}
  </h3>
${summaryHtml}
${tagsHtml}
${linkHtml}

</article>`;
}

// ── Arbitraries ──────────────────────────────────────────────────────────────

/**
 * Arbitrary for safe alphanumeric strings (letters, digits, spaces).
 * Avoids HTML special characters that would break assertion matching.
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
 * Arbitrary for a safe URL string.
 */
const safeUrl = fc
  .stringMatching(/^[a-zA-Z0-9]{1,30}$/)
  .filter((s) => s.trim().length > 0)
  .map((s) => `https://example.com/${s}`);

/**
 * Arbitrary for a non-empty array of safe tag strings (1–6 tags).
 */
const safeTagsArray = fc.array(safeString, { minLength: 1, maxLength: 6 });

/**
 * Arbitrary for an experience entry with random subsets of optional fields omitted.
 * Required fields: title, date, body
 * Optional fields: endDate, company, image
 */
const experienceWithOptionalFieldsArb = fc.record({
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

/**
 * Arbitrary for a project entry with random subsets of optional fields omitted.
 * Required fields: title
 * Optional fields: summary, tags, link, weight
 */
const projectWithOptionalFieldsArb = fc.record({
  title: safeString,
  summary: fc.option(safeString, { nil: undefined }),
  tags: fc.option(safeTagsArray, { nil: undefined }),
  link: fc.option(safeUrl, { nil: undefined }),
  weight: fc.option(fc.nat({ max: 100 }), { nil: undefined }),
});

// ── Assertion helpers ────────────────────────────────────────────────────────

/**
 * Asserts that the rendered HTML does not contain "undefined" or "null" text,
 * empty src/href attributes, or broken attribute references.
 *
 * @param {string} html - The rendered HTML string to validate
 */
function assertNoUndefinedOrNull(html) {
  // No literal "undefined" text in output
  expect(html).not.toContain('undefined');
  // No literal "null" text in output
  expect(html).not.toContain('null');
}

/**
 * Asserts that the rendered HTML has no empty src="" or href="" attributes.
 *
 * @param {string} html - The rendered HTML string to validate
 */
function assertNoEmptyAttributes(html) {
  expect(html).not.toMatch(/src=""/);
  expect(html).not.toMatch(/href=""/);
}

/**
 * Asserts that every <img> tag in the HTML has a non-empty alt attribute.
 *
 * @param {string} html - The rendered HTML string to validate
 */
function assertImagesHaveAlt(html) {
  const imgRegex = /<img\b[^>]*>/g;
  const imgs = html.match(imgRegex) || [];
  for (const img of imgs) {
    // Must have an alt attribute
    expect(img).toMatch(/alt="/);
    // alt must not be empty
    expect(img).not.toMatch(/alt=""/);
  }
}

/**
 * Asserts that the HTML has no unclosed tags from conditional rendering.
 * Checks that opening and closing counts match for key elements.
 *
 * @param {string} html - The rendered HTML string to validate
 */
function assertWellFormedHtml(html) {
  const tagsToCheck = ['div', 'p', 'article', 'span', 'a'];
  for (const tag of tagsToCheck) {
    const openRegex = new RegExp(`<${tag}[\\s>]`, 'g');
    const closeRegex = new RegExp(`</${tag}>`, 'g');
    const openCount = (html.match(openRegex) || []).length;
    const closeCount = (html.match(closeRegex) || []).length;
    expect(openCount).toBe(closeCount);
  }
}

// ── Property tests ───────────────────────────────────────────────────────────

describe('Property 4: Templates handle missing optional front matter fields gracefully', () => {
  /**
   * **Validates: Requirements 8.3**
   *
   * For any content entry where optional front matter fields are absent,
   * the rendered HTML SHALL not contain empty or broken elements referencing
   * those fields. No "undefined" text, no "null" text, no empty src/href
   * attributes, and no unclosed tags from conditional rendering.
   */
  it('experience entries with random optional fields omitted produce clean HTML', () => {
    fc.assert(
      fc.property(
        experienceWithOptionalFieldsArb,
        fc.nat({ max: 20 }),
        (entry, index) => {
          const html = renderTimelineEntry(entry, index);

          // No "undefined" or "null" text in output
          assertNoUndefinedOrNull(html);

          // No empty src="" or href="" attributes
          assertNoEmptyAttributes(html);

          // All images must have non-empty alt text
          assertImagesHaveAlt(html);

          // HTML must be well-formed (matching open/close tags)
          assertWellFormedHtml(html);

          // Required fields must always be present
          expect(html).toContain(entry.title);
          expect(html).toContain(entry.date.getFullYear().toString());
          expect(html).toContain(entry.body);

          // When optional fields are absent, their HTML blocks must not appear
          if (!entry.endDate) {
            // Date badge should only show the year, no dash separator
            expect(html).not.toContain('\u2009–\u2009');
          }
          if (!entry.company) {
            // No company paragraph should be rendered
            expect(html).not.toContain('font-semibold text-sm sm:text-base mb-3');
          }
          if (!entry.image) {
            // No img tag should be rendered
            expect(html).not.toContain('<img');
          }
        }
      ),
      { numRuns: 150 }
    );
  });

  it('project entries with random optional fields omitted produce clean HTML', () => {
    fc.assert(
      fc.property(projectWithOptionalFieldsArb, (project) => {
        const html = renderProjectCard(project);

        // No "undefined" or "null" text in output
        assertNoUndefinedOrNull(html);

        // No empty src="" or href="" attributes
        assertNoEmptyAttributes(html);

        // All images must have non-empty alt text
        assertImagesHaveAlt(html);

        // HTML must be well-formed (matching open/close tags)
        assertWellFormedHtml(html);

        // Required field must always be present
        expect(html).toContain(project.title);

        // When optional fields are absent, their HTML blocks must not appear
        if (!project.summary) {
          expect(html).not.toContain('text-slate-300 text-sm sm:text-base leading-relaxed mb-4');
        }
        if (!project.tags || project.tags.length === 0) {
          expect(html).not.toContain('aria-label="Technologies used"');
          expect(html).not.toContain('font-mono');
        }
        if (!project.link) {
          expect(html).not.toContain('<a\n');
          expect(html).not.toContain('<a ');
          expect(html).not.toContain('href=');
          expect(html).not.toContain('View Project');
        }
      }),
      { numRuns: 150 }
    );
  });
});
