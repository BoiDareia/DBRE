import fs from 'fs';
import path from 'path';
import { JSDOM } from 'jsdom';
import { describe, it, expect } from 'vitest';

/**
 * Property 3: All images have descriptive alt text
 *
 * **Validates: Requirements 7.4, 11.2**
 *
 * For every <img> element in the generated HTML output,
 * the element SHALL have a non-empty alt attribute.
 *
 * This is a universal property check across all HTML files
 * produced by the Hugo build in public/.
 */

const PUBLIC_DIR = path.resolve(__dirname, '..', 'public');

/**
 * Recursively find all .html files under a directory.
 */
function findHtmlFiles(dir) {
  const results = [];
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      results.push(...findHtmlFiles(fullPath));
    } else if (entry.isFile() && entry.name.endsWith('.html')) {
      results.push(fullPath);
    }
  }
  return results;
}

describe('Property 3: All images have descriptive alt text', () => {
  const htmlFiles = findHtmlFiles(PUBLIC_DIR);

  it('Hugo build output contains at least one HTML file', () => {
    expect(htmlFiles.length).toBeGreaterThan(0);
  });

  it('every <img> element across all HTML files has a non-empty alt attribute', () => {
    const violations = [];

    for (const filePath of htmlFiles) {
      const html = fs.readFileSync(filePath, 'utf-8');
      const dom = new JSDOM(html);
      const images = dom.window.document.querySelectorAll('img');

      for (const img of images) {
        const alt = img.getAttribute('alt');
        const src = img.getAttribute('src') || '(no src)';
        const relativePath = path.relative(PUBLIC_DIR, filePath);

        if (alt === null || alt.trim() === '') {
          violations.push({
            file: relativePath,
            src,
            alt: alt === null ? '(missing)' : '(empty)',
          });
        }
      }
    }

    if (violations.length > 0) {
      const details = violations
        .map((v) => `  ${v.file}: <img src="${v.src}"> alt=${v.alt}`)
        .join('\n');
      expect.fail(
        `Found ${violations.length} image(s) without descriptive alt text:\n${details}`
      );
    }
  });

  it('at least one image exists in the build output', () => {
    let totalImages = 0;

    for (const filePath of htmlFiles) {
      const html = fs.readFileSync(filePath, 'utf-8');
      const dom = new JSDOM(html);
      totalImages += dom.window.document.querySelectorAll('img').length;
    }

    expect(totalImages).toBeGreaterThan(0);
  });
});
