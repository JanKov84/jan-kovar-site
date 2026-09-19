import { readFileSync, readdirSync, existsSync, statSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// Check only editable public content and a completed Hugo build. Private input is unnecessary.
const root = fileURLToPath(new URL('../', import.meta.url));
const output = path.resolve(root, process.argv[2] ?? 'public');
const errors = new Set();
const check = (condition, message) => { if (!condition) errors.add(message); };
const read = (file) => readFileSync(file, 'utf8');
const walk = (directory) => existsSync(directory) ? readdirSync(directory, { withFileTypes: true })
  .flatMap((entry) => entry.isDirectory() ? walk(path.join(directory, entry.name)) : [path.join(directory, entry.name)]) : [];
const relative = (file) => path.relative(root, file).replaceAll('\\', '/');
const privateKey = /^(?:source(?:_.*)?|.*_internal|quartiles?|qa(?:_.*)?|needs_.*|.*_verification)$/i;
const privateMarkers = /_build_sources|CODING_AGENT_PROMPT|website_content_specification|PUBLICATION_INVENTORY|publication_database|project_database|\bquartiles?\b|\b(?:[a-z_]+_internal|needs_[a-z_]+|source_[a-z_]+|qa_[a-z_]+)\b|["']source["']\s*:/i;
const inspectKeys = (value, location) => {
  if (!value || typeof value !== 'object') return;
  for (const [key, nested] of Object.entries(value)) {
    check(!privateKey.test(key), `${location}: private field ${key}`);
    inspectKeys(nested, `${location}.${key}`);
  }
};
const frontmatter = (file) => {
  const text = read(file).replace(/^\uFEFF/, '').trimStart();
  if (!text.startsWith('{')) throw new Error(`${relative(file)}: expected JSON frontmatter`);
  let depth = 0, quoted = false, escaped = false;
  for (let index = 0; index < text.length; index++) {
    const character = text[index];
    if (quoted) {
      if (escaped) escaped = false;
      else if (character === '\\') escaped = true;
      else if (character === '"') quoted = false;
    } else if (character === '"') quoted = true;
    else if (character === '{') depth++;
    else if (character === '}' && --depth === 0) return JSON.parse(text.slice(0, index + 1));
  }
  throw new Error(`${relative(file)}: unclosed JSON frontmatter`);
};
const decode = (value) => value.replace(/&(?:amp|quot|apos|lt|gt|#\d+|#x[\da-f]+);/gi, (entity) => {
  const named = { '&amp;': '&', '&quot;': '"', '&apos;': "'", '&lt;': '<', '&gt;': '>' };
  if (named[entity.toLowerCase()]) return named[entity.toLowerCase()];
  return String.fromCodePoint(entity.toLowerCase().startsWith('&#x') ? parseInt(entity.slice(3), 16) : parseInt(entity.slice(2), 10));
});
const attributes = (html, names = 'href|src') => [...html.matchAll(new RegExp(`\\b(${names})\\s*=\\s*(?:"([^"]*)"|'([^']*)'|([^\\s"'=<>\x60]+))`, 'gi'))]
  .map((match) => ({ name: match[1].toLowerCase(), value: decode(match[2] ?? match[3] ?? match[4]) }));

if (!existsSync(path.join(output, 'index.html'))) {
  console.error(`No completed build in ${output}. Run pnpm build first, or pass the Hugo destination directory.`);
  process.exit(1);
}

const records = [];
const years = new Set();
for (const collection of ['publications', 'projects']) {
  const files = walk(path.join(root, 'content', collection)).filter((file) => path.basename(file) === 'index.md');
  check(files.length > 0, `content/${collection}: no detail records found`);
  for (const file of files) {
    try {
      const metadata = frontmatter(file);
      inspectKeys(metadata, relative(file));
      const slug = path.relative(path.join(root, 'content', collection), path.dirname(file)).replaceAll('\\', '/');
      const record = { ...metadata, collection, slug, file, url: `/${collection}/${slug}/` };
      records.push(record);
      if (metadata.date_precision === 'year') {
        const year = collection === 'publications' ? metadata.year : metadata.start_year;
        check(Number.isInteger(year) && year >= 1000 && year <= 9999, `${relative(file)}: missing authoritative ${collection === 'publications' ? 'year' : 'start_year'}`);
        check(metadata.date === `${year}-01-01`, `${relative(file)}: internal sort date does not match authoritative year`);
        years.add(year);
      }
      check(existsSync(path.join(output, collection, slug, 'index.html')), `${record.url}: missing built detail page`);
    } catch (error) { errors.add(error.message); }
  }
  const built = walk(path.join(output, collection)).filter((file) => path.basename(file) === 'index.html' && path.dirname(file) !== path.join(output, collection) && !relative(file).includes('/page/'));
  check(built.length === files.length, `${collection}: ${files.length} records but ${built.length} built detail pages (clean stale output if necessary)`);
}

const home = read(path.join(output, 'index.html'));
const canonicalFor = (html) => {
  for (const tag of html.matchAll(/<link\b[^>]*>/gi)) {
    const attrs = Object.fromEntries(attributes(tag[0], 'rel|href').map(({ name, value }) => [name, value]));
    if (attrs.rel === 'canonical') return attrs.href;
  }
};
const siteBase = new URL(process.argv[3] ?? canonicalFor(home) ?? 'http://localhost:1313/');
const basePath = siteBase.pathname.endsWith('/') ? siteBase.pathname : `${siteBase.pathname}/`;
const localPath = (url) => url.origin === siteBase.origin && url.pathname.startsWith(basePath)
  ? `/${url.pathname.slice(basePath.length)}` : null;
check(canonicalFor(home) === siteBase.href, 'Homepage canonical does not match the requested build base URL');
const featured = records.filter((record) => record.collection === 'publications' && record.featured);
const homepagePublications = new Set(attributes(home, 'href').map(({ value }) => localPath(new URL(value, siteBase))).filter((url) => /^\/publications\/[^/]+\/$/.test(url ?? '')));
check(homepagePublications.size === featured.length, `Homepage shows ${homepagePublications.size} publication links; metadata selects ${featured.length}`);
for (const record of featured) check(homepagePublications.has(record.url), `Homepage is missing featured publication ${record.url}`);

const outputFiles = walk(output);
const textFiles = outputFiles.filter((file) => /\.(?:html|json|xml|css|js|svg|txt|map|webmanifest)$/i.test(file));
for (const file of outputFiles) {
  const name = path.relative(output, file).replaceAll('\\', '/');
  check(!/(?:^|\/)(?:_build_sources|\.git|\.tools|\.cache|node_modules|scripts|config)(?:\/|$)|\.(?:md|ps1|toml|ya?ml)$/i.test(name), `Unexpected private/source file in output: ${name}`);
}
const publicationsByFile = new Map(records.filter((record) => record.collection === 'publications')
  .map((record) => [path.join(output, record.collection, record.slug, 'index.html'), record]));
const htmlCache = new Map();
const caseCache = new Map();
const exactPathCase = (target) => {
  if (caseCache.has(target)) return caseCache.get(target);
  let directory = output;
  for (const segment of path.relative(output, target).split(path.sep)) {
    if (!readdirSync(directory).includes(segment)) { caseCache.set(target, false); return false; }
    directory = path.join(directory, segment);
  }
  caseCache.set(target, true);
  return true;
};
const ids = (file) => {
  if (!htmlCache.has(file)) htmlCache.set(file, new Set(attributes(read(file), 'id|name').map(({ value }) => value)));
  return htmlCache.get(file);
};
const sortDates = new RegExp(`\\b(?:${[...years].join('|')})(?:-01-01|/01/01)\\b|\\b(?:January|Jan)\\s+0?1,?\\s+(?:${[...years].join('|')})\\b|\\b0?1\\s+(?:January|Jan)\\s+(?:${[...years].join('|')})\\b`, 'i');
let linkCount = 0, schemas = 0;
for (const file of textFiles) {
  const html = read(file);
  const label = relative(file);
  check(!privateMarkers.test(label) && !privateMarkers.test(html), `${label}: private source marker found`);
  check(!/file:\/\/\/|[A-Z]:[\\/](?:Users|Downloads|Program Files)|\/(?:home|Users)\/[^\s"'<>]+/i.test(html), `${label}: local filesystem path found`);
  check(!/href\s*=\s*["']?tel:/i.test(html), `${label}: unexpected telephone link`);
  if (siteBase.hostname !== 'localhost') check(!/https?:\/\/(?:localhost|127\.0\.0\.1)(?::\d+)?(?:\/|\b)/i.test(html), `${label}: localhost URL in production output`);
  check(!sortDates.test(html), `${label}: internal January 1 sort date exposed`);
  if (!file.endsWith('.html')) continue;
  const redirectPage = /http-equiv\s*=\s*["']?refresh/i.test(html);
  check(/<title>\s*[^<]+<\/title>/i.test(html), `${label}: missing page title`);
  if (!redirectPage) {
    const descriptionTag = [...html.matchAll(/<meta\b[^>]*>/gi)].map(([tag]) => Object.fromEntries(attributes(tag, 'name|content').map(({ name, value }) => [name, value]))).find((attrs) => attrs.name === 'description');
    check(Boolean(descriptionTag?.content?.trim()), `${label}: missing meta description`);
    const canonical = canonicalFor(html);
    check(Boolean(canonical) && localPath(new URL(canonical, siteBase)) !== null, `${label}: canonical outside build base URL`);
  }
  const structuredData = [];
  for (const schema of html.matchAll(/<script\b[^>]*type\s*=\s*["']?application\/ld\+json["']?[^>]*>([\s\S]*?)<\/script>/gi)) {
    try { structuredData.push(JSON.parse(schema[1])); schemas++; } catch { errors.add(`${label}: invalid JSON-LD`); }
  }
  const publication = publicationsByFile.get(file);
  if (publication) {
    const work = structuredData.find((item) => item.mainEntityOfPage);
    check(Boolean(work), `${label}: missing publication JSON-LD`);
    if (work) {
      check(JSON.stringify(work.author?.map((author) => author.name)) === JSON.stringify(publication.authors), `${label}: structured authors differ from supplied names/order`);
      check((work.publisher?.name ?? '') === (publication.publication?.publisher ?? ''), `${label}: structured publisher differs from supplied publisher`);
    }
  }
  const pagePath = path.relative(output, file).replaceAll('\\', '/').replace(/index\.html$/, '');
  const pageURL = new URL(pagePath, siteBase);
  for (const { name, value } of attributes(html)) {
    if (/^(?:mailto:|tel:|data:|javascript:)/i.test(value)) continue;
    let url;
    try { url = new URL(value, pageURL); } catch { errors.add(`${label}: invalid ${name} URL ${value}`); continue; }
    if (url.origin !== siteBase.origin || url.pathname === '/livereload.js') continue;
    linkCount++;
    check(value !== '', `${label}: empty ${name} attribute`);
    let target;
    const route = localPath(url);
    if (route === null) { errors.add(`${label}: local URL misses project base path ${value}`); continue; }
    try { target = path.resolve(output, `.${decodeURIComponent(route)}`); } catch { errors.add(`${label}: malformed URL ${value}`); continue; }
    if (target !== output && !target.startsWith(output + path.sep)) { errors.add(`${label}: URL leaves output directory ${value}`); continue; }
    if (existsSync(target) && statSync(target).isDirectory()) target = path.join(target, 'index.html');
    if (!existsSync(target)) { errors.add(`${label}: missing local target ${value}`); continue; }
    check(exactPathCase(target), `${label}: local target has incorrect filename casing ${value}`);
    if (url.hash && url.hash !== '#' && target.endsWith('.html')) {
      let fragment;
      try { fragment = decodeURIComponent(url.hash.slice(1)); } catch { fragment = url.hash.slice(1); }
      check(ids(target).has(fragment), `${label}: missing anchor ${value}`);
    }
  }
}

const sitemap = path.join(output, 'sitemap.xml');
check(existsSync(sitemap), 'Missing sitemap.xml');
if (existsSync(sitemap)) {
  const xml = read(sitemap);
  const locations = [...xml.matchAll(/<loc>([^<]+)<\/loc>/g)].map((match) => decode(match[1]));
  check(locations.length >= records.length + 7, 'Sitemap omits required pages');
  check(!/<lastmod>/i.test(xml), 'Sitemap must not expose unverified technical modification dates');
  for (const location of locations) {
    const route = localPath(new URL(location));
    check(route !== null && existsSync(path.join(output, route, 'index.html')), `Sitemap target missing/outside build base: ${location}`);
  }
}
check(!existsSync(path.join(output, 'index.xml')), 'RSS should remain disabled');
const contact = read(path.join(output, 'contact', 'index.html'));
check(contact.includes('kovar [at] iir.cz') && !/kovar@iir\.cz/i.test(contact), 'Contact email obfuscation changed');
const cv = read(path.join(output, 'cv', 'index.html'));
check(attributes(cv, 'href').some(({ value }) => localPath(new URL(value, siteBase)) === '/uploads/Jan_Kovar_Academic_CV_2026.pdf'), 'CV download link missing or incorrectly based');
const cvPath = path.join(output, 'uploads', 'Jan_Kovar_Academic_CV_2026.pdf');
check(existsSync(cvPath) && readFileSync(cvPath).equals(readFileSync(path.join(root, 'static/uploads/Jan_Kovar_Academic_CV_2026.pdf'))), 'CV output differs from supplied PDF');

if (errors.size) {
  console.error(`Site checks failed (${errors.size}):\n${[...errors].map((error) => `- ${error}`).join('\n')}`);
  process.exit(1);
}
console.log(`Site checks passed: ${records.filter((record) => record.collection === 'publications').length} publications, ${records.filter((record) => record.collection === 'projects').length} projects, ${featured.length} featured publications; ${textFiles.length} output documents, ${schemas} valid JSON-LD blocks, ${linkCount} local links/assets. No private markers or internal January 1 dates found.`);
