import { describe, it, expect, beforeAll } from 'vitest';
import { readFileSync } from 'fs';
import { resolve } from 'path';
import { JSDOM } from 'jsdom';

let document;

beforeAll(() => {
  const htmlPath = resolve(__dirname, '..', 'public', 'index.html');
  const html = readFileSync(htmlPath, 'utf-8');
  const dom = new JSDOM(html);
  document = dom.window.document;
});

describe('Hero Section', () => {
  it('contains "Makitall" brand in h1', () => {
    const h1 = document.querySelector('h1');
    expect(h1).not.toBeNull();
    expect(h1.textContent).toContain('Makitall');
  });

  it('contains "Database Reliability Engineer" role text', () => {
    const main = document.querySelector('main');
    expect(main.textContent).toContain('Database Reliability Engineer');
  });

  it('contains LinkedIn link in the page', () => {
    const linkedinLink = document.querySelector('a[href*="linkedin.com/in/sergioagoncalves"]');
    expect(linkedinLink).not.toBeNull();
  });

  it('contains "View Projects" CTA with href="/projects/"', () => {
    const links = document.querySelectorAll('a[href="/projects/"]');
    const cta = Array.from(links).find(link => link.textContent.includes('View Projects'));
    expect(cta).not.toBeNull();
  });
});

describe('Semantic HTML Elements', () => {
  it('has a <nav> element', () => {
    expect(document.querySelector('nav')).not.toBeNull();
  });

  it('has a <main> element', () => {
    expect(document.querySelector('main')).not.toBeNull();
  });

  it('has <section> elements', () => {
    const sections = document.querySelectorAll('section');
    expect(sections.length).toBeGreaterThan(0);
  });

  it('has a <footer> element', () => {
    expect(document.querySelector('footer')).not.toBeNull();
  });
});

describe('Heading Hierarchy', () => {
  it('has exactly one h1 element', () => {
    const h1s = document.querySelectorAll('h1');
    expect(h1s.length).toBe(1);
  });

  it('has h2 elements', () => {
    const h2s = document.querySelectorAll('h2');
    expect(h2s.length).toBeGreaterThan(0);
  });

  it('does not skip heading levels (no h3 without a preceding h2, no gaps)', () => {
    const headings = document.querySelectorAll('h1, h2, h3, h4, h5, h6');
    let maxLevelSeen = 0;
    for (const heading of headings) {
      const level = parseInt(heading.tagName.charAt(1), 10);
      // Each heading level should not jump more than 1 beyond the max seen so far
      expect(level).toBeLessThanOrEqual(maxLevelSeen + 1);
      if (level > maxLevelSeen) {
        maxLevelSeen = level;
      }
    }
  });
});

describe('Font Loading', () => {
  it('uses async pattern with media="print" and onload attribute for Google Fonts', () => {
    const fontLinks = document.querySelectorAll('link[rel="stylesheet"]');
    const asyncFontLink = Array.from(fontLinks).find(
      (link) =>
        link.getAttribute('href')?.includes('fonts.googleapis.com') &&
        link.getAttribute('media') === 'print' &&
        link.hasAttribute('onload')
    );
    expect(asyncFontLink).not.toBeNull();
  });
});

describe('Favicon References', () => {
  it('has favicon.ico reference', () => {
    const link = document.querySelector('link[href*="favicon.ico"]');
    expect(link).not.toBeNull();
  });

  it('has favicon-16x16.png reference', () => {
    const link = document.querySelector('link[href*="favicon-16x16"]');
    expect(link).not.toBeNull();
  });

  it('has favicon-32x32.png reference', () => {
    const link = document.querySelector('link[href*="favicon-32x32"]');
    expect(link).not.toBeNull();
  });

  it('has apple-touch-icon reference', () => {
    const link = document.querySelector('link[href*="apple-touch-icon"]');
    expect(link).not.toBeNull();
  });

  it('has site.webmanifest reference', () => {
    const link = document.querySelector('link[href*="site.webmanifest"]');
    expect(link).not.toBeNull();
  });
});

describe('ARIA Labels', () => {
  it('has aria-label on navigation element', () => {
    const nav = document.querySelector('nav[aria-label]');
    expect(nav).not.toBeNull();
    expect(nav.getAttribute('aria-label').length).toBeGreaterThan(0);
  });

  it('has aria-label on header element', () => {
    const header = document.querySelector('header[aria-label]');
    expect(header).not.toBeNull();
    expect(header.getAttribute('aria-label').length).toBeGreaterThan(0);
  });
});
