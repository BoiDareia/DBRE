import { describe, it, expect, beforeAll } from 'vitest';
import { readFileSync } from 'fs';
import { resolve } from 'path';
import { JSDOM } from 'jsdom';

// --- 404 Page Tests ---

let doc404;

beforeAll(() => {
  const html404Path = resolve(__dirname, '..', 'public', '404.html');
  const html404 = readFileSync(html404Path, 'utf-8');
  const dom404 = new JSDOM(html404);
  doc404 = dom404.window.document;
});

describe('404 Page', () => {
  it('contains an img with src referencing foto-1.png', () => {
    const img = doc404.querySelector('img[src*="foto-1.png"]');
    expect(img).not.toBeNull();
  });

  it('contains descriptive alt text on the image', () => {
    const img = doc404.querySelector('img[src*="foto-1.png"]');
    expect(img).not.toBeNull();
    const alt = img.getAttribute('alt');
    expect(alt).toBeTruthy();
    expect(alt.length).toBeGreaterThan(5);
  });

  it('contains a humorous error message text', () => {
    const main = doc404.querySelector('main');
    expect(main).not.toBeNull();
    // The 404 page should contain the "404" heading and a humorous message
    expect(main.textContent).toContain('404');
    // Check for the desenrasca-themed humorous message
    expect(main.textContent).toMatch(/desenrasca|WHERE clause|Grumpy DBA/i);
  });

  it('contains a "Back to Homepage" link with href="/"', () => {
    const main = doc404.querySelector('main');
    const link = main.querySelector('a[href="/"]');
    expect(link).not.toBeNull();
    expect(link.textContent).toContain('Back to Homepage');
  });
});

// --- Footer Tests (from public/index.html) ---

let docIndex;

beforeAll(() => {
  const htmlIndexPath = resolve(__dirname, '..', 'public', 'index.html');
  const htmlIndex = readFileSync(htmlIndexPath, 'utf-8');
  const domIndex = new JSDOM(htmlIndex);
  docIndex = domIndex.window.document;
});

describe('Footer', () => {
  it('uses a semantic <footer> element', () => {
    const footer = docIndex.querySelector('footer');
    expect(footer).not.toBeNull();
  });

  it('contains a LinkedIn link with target="_blank" and rel="noopener noreferrer"', () => {
    const footer = docIndex.querySelector('footer');
    const link = footer.querySelector('a[href*="linkedin.com"]');
    expect(link).not.toBeNull();
    expect(link.getAttribute('target')).toBe('_blank');
    expect(link.getAttribute('rel')).toContain('noopener');
    expect(link.getAttribute('rel')).toContain('noreferrer');
  });

  it('contains a GitHub link with target="_blank" and rel="noopener noreferrer"', () => {
    const footer = docIndex.querySelector('footer');
    const link = footer.querySelector('a[href*="github.com"]');
    expect(link).not.toBeNull();
    expect(link.getAttribute('target')).toBe('_blank');
    expect(link.getAttribute('rel')).toContain('noopener');
    expect(link.getAttribute('rel')).toContain('noreferrer');
  });

  it('contains a mailto link with target="_blank"', () => {
    const footer = docIndex.querySelector('footer');
    const link = footer.querySelector('a[href^="mailto:"]');
    expect(link).not.toBeNull();
    expect(link.getAttribute('target')).toBe('_blank');
  });
});

// --- Security Headers Tests ---

describe('Security Headers', () => {
  let headersContent;

  beforeAll(() => {
    const headersPath = resolve(__dirname, '..', 'static', '_headers');
    headersContent = readFileSync(headersPath, 'utf-8');
  });

  it('contains X-Frame-Options: DENY', () => {
    expect(headersContent).toContain('X-Frame-Options: DENY');
  });

  it('contains X-Content-Type-Options: nosniff', () => {
    expect(headersContent).toContain('X-Content-Type-Options: nosniff');
  });

  it('contains Referrer-Policy', () => {
    expect(headersContent).toContain('Referrer-Policy');
  });

  it('contains Permissions-Policy', () => {
    expect(headersContent).toContain('Permissions-Policy');
  });

  it('contains Strict-Transport-Security', () => {
    expect(headersContent).toContain('Strict-Transport-Security');
  });

  it('contains Content-Security-Policy', () => {
    expect(headersContent).toContain('Content-Security-Policy');
  });
});
