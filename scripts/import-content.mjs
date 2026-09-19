import { readFile, writeFile, mkdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// One-time, explicit allowlist import. The ordinary Hugo build never reads private input.
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const read = async (file) => readFile(path.join(root, file), 'utf8');
const load = async (file) => JSON.parse(await read(file));
const write = async (file, value) => {
  const target = path.join(root, file);
  await mkdir(path.dirname(target), { recursive: true });
  await writeFile(target, value, 'utf8');
};
const page = async (file, frontmatter, body = '') => write(file, `${JSON.stringify(frontmatter, null, 2)}\n\n${body.trim()}\n`);
const spec = (await read('_build_sources/website_content_specification_v1.0.md')).replace(/\r\n/g, '\n');
const between = (start, end) => {
  const startIndex = spec.indexOf(start);
  if (startIndex < 0) throw new Error(`Missing specification heading: ${start}`);
  const from = startIndex + start.length;
  const to = spec.indexOf(end, from);
  if (to < 0) throw new Error(`Missing specification delimiter: ${end}`);
  return spec.slice(from, to).trim();
};
const areaLabels = await load('_build_sources/publication_database/research_areas.json');
const publications = await load('_build_sources/publication_database/publications.json');
const projects = await load('_build_sources/project_database/projects.json');
// Public, verified link additions survive a deliberate re-import of the private package.
const verifiedPublicationLinks = {
  ...await load('data/verified-publication-links-journals.json'),
  ...await load('data/verified-publication-links-books-policy.json'),
};
const verifiedProjectLinks = await load('data/verified-project-links.json');
const typeMap = {
  journal_article: ['article-journal', 'Journal Articles'],
  book: ['book', 'Books'],
  book_chapter: ['chapter', 'Book Chapters'],
  book_review: ['review-book', 'Book Reviews'],
  research_report: ['report', 'Other Research and Policy Publications'],
  policy_report: ['report', 'Other Research and Policy Publications'],
  policy_brief: ['report', 'Other Research and Policy Publications'],
  research_paper: ['report', 'Other Research and Policy Publications'],
  policy_article: ['article', 'Other Research and Policy Publications'],
};
const labels = (tags) => tags.map((tag) => {
  if (!areaLabels[tag]) throw new Error(`Unrecognised research area: ${tag}`);
  return areaLabels[tag];
});
const nonempty = (object) => Object.fromEntries(Object.entries(object).filter(([, value]) => value !== '' && value !== null && value !== undefined));

for (const record of publications.filter((record) => record.public === true)) {
  const mapping = typeMap[record.type];
  if (!mapping || !/^[-a-z0-9]+$/.test(record.slug)) throw new Error(`Invalid record: ${record.title}`);
  const metadata = nonempty({
    name: record.venue || record.book_title,
    volume: record.volume,
    issue: record.issue,
    pages: record.pages,
    publisher: record.publisher,
    editors: record.editors,
    location: record.location,
  });
  const frontmatter = {
    title: record.title.replace(': střícný přístup', ': vstřícný přístup'),
    authors: record.authors,
    year: record.year,
    date: `${record.year}-01-01`,
    date_precision: 'year',
    show_date: true,
    publication_types: [mapping[0]],
    categories: [mapping[1]],
    publication_kind: record.type,
    publication: metadata,
    tags: labels(record.research_areas),
    featured: record.featured,
    status: record.status,
    publication_language: record.language,
  };
  if (record.abstract) frontmatter.abstract = record.abstract;
  if (!record.needs_link_verification) {
    const links = [];
    if (record.doi) frontmatter.hugoblox = { ids: { doi: record.doi } };
    for (const [key, type] of [['publisher_url', 'source'], ['pdf_url', 'pdf'], ['data_url', 'dataset'], ['code_url', 'code']]) {
      if (key === 'publisher_url' && record.doi && record[key] === `https://doi.org/${record.doi}`) continue;
      if (record[key]) links.push({ type, url: record[key] });
    }
    if (links.length) frontmatter.links = links;
  }
  const body = [];
  if (verifiedPublicationLinks[record.slug]?.length) {
    frontmatter.links = [...new Map([...(frontmatter.links ?? []), ...verifiedPublicationLinks[record.slug]].map((link) => [link.url, link])).values()];
  }
  if (record.status === 'online_first') body.push('Online-first publication.');
  if (record.type === 'book_chapter' && record.editors) body.push(`Edited by ${record.editors}.`);
  await page(`content/publications/${record.slug}/index.md`, frontmatter, body.join('\n\n'));
}

const projectSlugs = [
  'interfer-foreign-interference-in-the-context-of-geopolitical-and-technological-change',
  'acteu-towards-a-new-era-of-representative-democracy-activating-european-citizens-trust-in',
  'mapping-and-explaining-the-politicisation-and-framing-of-european-integration-in-the-polit',
  'immigrants-asylum-seekers-and-refugees-during-the-eu-migration-crisis-analysing-their-fram',
  'eu-idea-eu-integration-and-differentiation-for-effectiveness-and-accountability',
];
if (projects.length !== projectSlugs.length) throw new Error('Project selection changed: review before importing.');
for (let index = 0; index < projects.length; index++) {
  const record = projects[index];
  const frontmatter = {
    title: record.acronym ? `${record.acronym}: ${record.title}` : record.title,
    ...nonempty({ acronym: record.acronym }),
    date: `${record.start_year}-01-01`,
    date_precision: 'year',
    start_year: record.start_year,
    end_year: record.end_year,
    status: record.status,
    funder: record.funder,
    role: record.role,
    tags: labels(record.research_areas),
    summary: `${record.start_year}–${record.end_year} · ${record.funder} · ${record.role}. ${record.description}`,
    featured: record.featured,
    show_date: false,
    reading_time: false,
  };
  if (record.project_url) frontmatter.links = [{ type: 'site', url: record.project_url }];
  if (verifiedProjectLinks[projectSlugs[index]]?.length) frontmatter.links = verifiedProjectLinks[projectSlugs[index]];
  const body = `**${record.start_year}–${record.end_year} · ${record.status === 'current' ? 'Current project' : 'Selected past project'}**\n\n**Funder:** ${record.funder}  \n**Role:** ${record.role}\n\n${record.description}`;
  await page(`content/projects/${projectSlugs[index]}/index.md`, frontmatter, body);
}

const bio = between('## About\n\n', '\n\nUse first person');
const descriptor = between('### Descriptor\n\n', '\n\n## About');
const identity = '**Research Director, Institute of International Relations Prague**  \n**Associate Professor, University of New York in Prague**';
const homepageAreas = between('## Homepage research cards\n\n', '\n\nThe three areas');
const htmlEscape = (text) => text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
const researchCards = homepageAreas.split(/^### /m).filter(Boolean).map((area) => {
  const [heading, ...paragraph] = area.trim().split('\n\n');
  return `<section><h3>${htmlEscape(heading)}</h3><p>${htmlEscape(paragraph.join('\n\n'))}</p></section>`;
}).join('\n');
const markdownSection = (title, text, id, extraContent = {}) => ({
  block: 'markdown',
  ...(id ? { id } : {}),
  content: { title, text, ...extraContent },
  design: { columns: '1' },
});
await page('content/_index.md', {
  title: '',
  summary: 'Jan Kovář — research on European integration, political competition, migration, and political communication.',
  type: 'landing',
  sections: [
    markdownSection('', `# Jan Kovář\n\n${identity}\n\n${descriptor}\n\n[Publications →](/publications/) · [Current research →](/projects/)`, 'introduction', { portrait: { filename: 'images/jan-kovar.jpg', alt: 'Portrait of Jan Kovář' } }),
    markdownSection('', `## About {#about-heading}\n\n${bio}`, 'about'),
    markdownSection('', `## Research {#research-heading}\n\n<div class="research-grid">\n${researchCards}\n</div>\n\n[Explore my research →](/research/)`, 'research'),
    {
      block: 'collection',
      id: 'featured-publications',
      content: {
        title: '## Featured Publications {#featured-publications-heading}',
        text: '[View all publications →](/publications/)',
        count: 0,
        order: 'desc',
        filters: { folders: ['publications'], featured_only: true },
      },
      design: { view: 'citation' },
    },
  ],
});

const pageSettings = { show_date: false, reading_time: false, share: false, profile: false, comments: false };
const researchSection = between('# Research page\n\n', '\n\n# Publications');
const researchBody = researchSection.slice(researchSection.indexOf('## European Integration and EU Governance'));
await page('content/research/index.md', {
  title: 'Research',
  summary: 'European politics: governance, contestation, and communication.',
  ...pageSettings,
}, `My research asks how European politics is governed, contested, and communicated, with a strong empirical focus on Central and Eastern Europe and recurring attention to domestic political competition.\n\n${researchBody}\n\n[Browse publications by research area →](/publications/)`);

await page('content/publications/_index.md', {
  title: 'Publications',
  view: 'citation',
  summary: 'Journal articles, books, book chapters, research and policy publications, and book reviews.',
}, 'My publications are listed newest first.\n\n[Google Scholar](https://scholar.google.com/citations?user=IAWEh-4AAAAJ&hl=cs)');

const projectCollection = (title, filters, id) => ({
  block: 'collection',
  id,
  content: { title: `## ${title}`, count: 0, order: 'desc', filters: { folders: ['projects'], ...filters } },
  design: { view: 'date-title-summary', show_date: false, show_read_time: false, show_read_more: false },
});
await page('content/projects/_index.md', {
  title: 'Projects',
  summary: 'Current research and selected past projects.',
  type: 'landing',
  sections: [
    markdownSection('', '# Projects', 'projects-introduction'),
    projectCollection('Current Project', { featured_only: true }, 'current-projects'),
    projectCollection('Selected Past Projects', { exclude_featured: true }, 'past-projects'),
  ],
});

await page('content/teaching/index.md', {
  title: 'Teaching',
  summary: 'Teaching European politics and international relations at the University of New York in Prague.',
  ...pageSettings,
}, between('# Teaching\n\n', '\n\nNo separate course pages.'));

const cv = between('# CV page\n\n', '\n\nProvide a prominent')
  .replace('\n\nDo not include the former Coordination Council of the National Convention on the European Union.', '');
await page('content/cv/index.md', { title: 'CV', summary: 'Academic positions, education, professional service, and languages.', ...pageSettings }, '[Download full CV](/uploads/Jan_Kovar_Academic_CV_2026.pdf)\n\n' + cv);

await page('content/contact/index.md', { title: 'Contact', summary: 'Contact and academic profiles.', ...pageSettings },
  between('# Contact\n\n', '\n\nDo not add a separate affiliation block')
    .replace(/^- (.+): (https:\/\/\S+)$/gm, '- [$1]($2)'));

await write('data/research_areas.json', `${JSON.stringify(areaLabels, null, 2)}\n`);
await write('data/authors/me.json', `${JSON.stringify({
  schema: 'hugoblox/author/v1',
  slug: 'me',
  is_owner: true,
  name: { display: 'Jan Kovář', given: 'Jan', family: 'Kovář' },
  role: 'Research Director; Associate Professor',
  bio,
  affiliations: [
    { name: 'Institute of International Relations Prague', url: 'https://www.iir.cz/jan-kovar' },
    { name: 'University of New York in Prague', url: 'https://www.unyp.cz/academic-staff/jan-kovar/' },
  ],
  links: [
    { icon: 'academicons/google-scholar', url: 'https://scholar.google.com/citations?user=IAWEh-4AAAAJ&hl=cs', label: 'Google Scholar' },
    { icon: 'academicons/orcid', url: 'https://orcid.org/0000-0002-5267-2090', label: 'ORCID' },
  ],
  interests: Object.values(areaLabels),
}, null, 2)}\n`);

console.log(`Imported ${publications.filter((record) => record.public).length} publications and ${projects.length} projects. Private input remains outside the Hugo content tree.`);
