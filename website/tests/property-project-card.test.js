import fc from 'fast-check';
import { describe, it, expect } from 'vitest';

/**
 * Simulated Hugo project-card.html partial renderer.
 *
 * Mirrors the logic in layouts/partials/project-card.html:
 *   - article element with slate-800 bg, rounded-lg, border-2, hover:border-amber-600
 *   - h3 with title
 *   - Summary paragraph (optional via `with`)
 *   - Tags as pill-shaped spans with font-mono class
 *   - Optional external link anchor with target="_blank" rel="noopener noreferrer"
 *     and "View Project" text + SVG icon
 *
 * @param {object} project
 * @param {string} project.title   - Project name (required)
 * @param {string} [project.summary] - Brief project description (optional via `with`)
 * @param {string[]} [project.tags]  - List of technology names (optional via `with`)
 * @param {string} [project.link]    - External URL (optional via `with`)
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
  .map((s) => `https://example.com/${s}`);

/**
 * Arbitrary for a non-empty array of safe tag strings (1–6 tags).
 */
const safeTagsArray = fc.array(safeString, { minLength: 1, maxLength: 6 });

/**
 * Arbitrary for a complete project entry with required and optional fields.
 */
const projectEntryArb = fc.record({
  title: safeString,
  summary: fc.option(safeString, { nil: undefined }),
  tags: fc.option(safeTagsArray, { nil: undefined }),
  link: fc.option(safeUrl, { nil: undefined }),
});

describe('Property 2: Project card rendering preserves front matter fields and handles optional link', () => {
  /**
   * **Validates: Requirements 4.4, 8.2**
   *
   * For any project entry with title, summary, and tags,
   * the rendered project card HTML SHALL contain the title text,
   * summary text, and every tag as a Tech_Tag element.
   * If an optional link field is present, the card SHALL contain
   * an anchor element with that URL; if absent, no broken anchor SHALL appear.
   */
  it('rendered HTML contains title, summary, all tags, and correct link handling for any project entry', () => {
    fc.assert(
      fc.property(projectEntryArb, (project) => {
        const html = renderProjectCard(project);

        // Article wrapper with correct classes
        expect(html).toContain('<article');
        expect(html).toContain('bg-slate-800');
        expect(html).toContain('rounded-lg');
        expect(html).toContain('border-2');
        expect(html).toContain('hover:border-amber-600');

        // Title must appear inside an h3
        expect(html).toContain('<h3');
        expect(html).toContain(project.title);

        // Summary: if present, must appear in a paragraph
        if (project.summary) {
          expect(html).toContain(project.summary);
          expect(html).toContain('text-slate-300');
        }

        // Tags: if present, every tag must appear as a font-mono span
        if (project.tags && project.tags.length > 0) {
          for (const tag of project.tags) {
            expect(html).toContain(tag);
          }
          expect(html).toContain('font-mono');
          expect(html).toContain('aria-label="Technologies used"');
        }

        // Link: if present, anchor with URL must exist; if absent, no anchor
        if (project.link) {
          expect(html).toContain(`href="${project.link}"`);
          expect(html).toContain('target="_blank"');
          expect(html).toContain('rel="noopener noreferrer"');
          expect(html).toContain('View Project');
          expect(html).toContain('<svg');
        } else {
          expect(html).not.toContain('<a\n');
          expect(html).not.toContain('<a ');
          expect(html).not.toContain('View Project');
        }
      }),
      { numRuns: 150 }
    );
  });

  it('rendered HTML includes summary paragraph when summary is provided', () => {
    const withSummary = projectEntryArb.filter((p) => p.summary !== undefined);

    fc.assert(
      fc.property(withSummary, (project) => {
        const html = renderProjectCard(project);

        expect(html).toContain('<p');
        expect(html).toContain(project.summary);
        expect(html).toContain('leading-relaxed');
      }),
      { numRuns: 100 }
    );
  });

  it('rendered HTML omits summary paragraph when summary is absent', () => {
    const withoutSummary = projectEntryArb.filter((p) => p.summary === undefined);

    fc.assert(
      fc.property(withoutSummary, (project) => {
        const html = renderProjectCard(project);

        // No summary paragraph should be rendered
        expect(html).not.toContain('text-slate-300 text-sm sm:text-base leading-relaxed mb-4');
      }),
      { numRuns: 100 }
    );
  });

  it('rendered HTML renders all tags as pill-shaped Tech_Tag spans when tags are provided', () => {
    const withTags = projectEntryArb.filter(
      (p) => p.tags !== undefined && p.tags.length > 0
    );

    fc.assert(
      fc.property(withTags, (project) => {
        const html = renderProjectCard(project);

        // Each tag must appear in the output
        for (const tag of project.tags) {
          expect(html).toContain(tag);
        }

        // Tags container must have correct styling
        expect(html).toContain('font-mono');
        expect(html).toContain('rounded-full');
        expect(html).toContain('text-amber-600 bg-slate-900');
      }),
      { numRuns: 100 }
    );
  });

  it('rendered HTML omits tags section when tags are absent', () => {
    const withoutTags = projectEntryArb.filter((p) => p.tags === undefined);

    fc.assert(
      fc.property(withoutTags, (project) => {
        const html = renderProjectCard(project);

        // No tags container should be rendered
        expect(html).not.toContain('aria-label="Technologies used"');
        expect(html).not.toContain('font-mono');
      }),
      { numRuns: 100 }
    );
  });

  it('rendered HTML contains anchor with correct attributes when link is present', () => {
    const withLink = projectEntryArb.filter((p) => p.link !== undefined);

    fc.assert(
      fc.property(withLink, (project) => {
        const html = renderProjectCard(project);

        expect(html).toContain(`href="${project.link}"`);
        expect(html).toContain('target="_blank"');
        expect(html).toContain('rel="noopener noreferrer"');
        expect(html).toContain('View Project');
        // SVG icon must be present
        expect(html).toContain('<svg');
        expect(html).toContain('aria-hidden="true"');
      }),
      { numRuns: 100 }
    );
  });

  it('rendered HTML has no broken anchor when link is absent', () => {
    const withoutLink = projectEntryArb.filter((p) => p.link === undefined);

    fc.assert(
      fc.property(withoutLink, (project) => {
        const html = renderProjectCard(project);

        // No anchor tag should be rendered at all
        expect(html).not.toContain('<a\n');
        expect(html).not.toContain('<a ');
        expect(html).not.toContain('href=');
        expect(html).not.toContain('View Project');
        expect(html).not.toContain('<svg');
      }),
      { numRuns: 100 }
    );
  });
});
