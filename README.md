# Jan Kovář — academic website

Local Hugo + Hugo Blox website. A manual GitHub Pages workflow is prepared for review; it has not been run. GitHub Pages has not been enabled, and nothing has been pushed, published, or connected to a domain.

## Pinned foundation

- Starter: [HugoBlox/hugo-theme-academic-cv](https://github.com/HugoBlox/hugo-theme-academic-cv/tree/3aacb2ac2c3f6aeaecac4febe915c2fb30122903)
- **Exact starter commit: `3aacb2ac2c3f6aeaecac4febe915c2fb30122903`**
- Hugo Blox module: `github.com/HugoBlox/kit/modules/blox v0.0.0-20260527025321-61f41d3667f1`, as specified by that starter; `go.sum` verifies dependencies.
- Hugo **Extended 0.162.0**; pnpm **10.14.0**; Go **1.27.1**; Node.js **24** (tested with 24.19.0).
- The starter's JavaScript dependency versions are retained in `pnpm-lock.yaml`, including Tailwind CSS 4.2.4. Unused Netlify/slides module imports and demo content were not brought into the site.

The upstream license is retained in `LICENSE-HUGOBLOX.md`. The public design uses the starter's navigation, footer, Markdown blocks, collections, citation view, and detail-page templates, with limited adaptations described below.

## Local setup and preview (Windows)

Run these commands from this project folder in PowerShell. Node.js 24, Git, and Windows `tar` must be on PATH. Node is currently supplied by the Codex runtime; a separate terminal may need its own Node.js 24 installation or PATH configuration.

```powershell
.\scripts\setup.ps1
.\scripts\pnpm.ps1 dev
```

Preview: **http://localhost:1313/**. The server binds only to `127.0.0.1`; it does not expose a network/public preview. Stop a foreground server with Ctrl+C.

The wrapper invokes the project-local **pnpm 10.14.0**, regardless of a different global version. With the correct pnpm already on PATH, `pnpm dev` is equivalent. The Hugo wrapper locates the portable Hugo and Go tools and project-local caches.

Setup downloads official portable releases to ignored `.tools/`, checks their pinned SHA256/SHA512 checksums, installs the locked packages, and downloads the Go modules. It makes no global Git/package configuration changes. Windows' trusted certificate store is used without disabling TLS verification.

```powershell
.\scripts\pnpm.ps1 build
.\scripts\pnpm.ps1 check
```

`build` writes static files to ignored `public/`. During a running preview, validate a separate production destination:

```powershell
node scripts/hugo.mjs --minify --destination .preview/production
node scripts/check-site.mjs .preview/production
```

The checker uses only public content and generated output. It verifies record counts, featured selections, local page/asset links, JSON-LD, faithful author/publisher metadata, and the absence of private fields and fabricated January 1 publication dates.

## Content structure

```text
config/_default/       Hugo, theme, navigation, and module configuration
content/_index.md     Homepage: native Blox Markdown and featured collection
content/research/     Research overview
content/publications/<slug>/index.md
content/projects/<slug>/index.md
content/teaching/     Single teaching overview
content/cv/           Academic profile and education
content/contact/     Obfuscated email and academic profiles
data/authors/me.json  Author profile
data/research_areas.json
assets/css/custom.css
assets/js/            Publication filters and keyboard menu enhancement
layouts/              Narrow compatibility/metadata adaptations
scripts/              Portable setup, preview/build, import, and verification
```

The first import contains **54 publications**, **five projects**, and **four featured publications**. It preserves supplied author order, names, diacritics, bibliographic details, research areas, and project wording. The approved chapter-title correction is **“vstřícný přístup”**; the original stable URL slug is retained.

## Maintaining a record

Edit or add one publication's `index.md` JSON frontmatter. Keep `year` authoritative, assign `categories`, `publication_types`, `tags`, and `featured` as appropriate, and supply only confirmed bibliographic data. The homepage reads `featured`; the publication index reads the same records. A record without a research tag remains visible under “All research areas.”

For year-only records, use:

```json
"year": 2026,
"date": "2026-01-01",
"date_precision": "year",
"show_date": true
```

`date` is an **internal sorting value**, not a claim about the publication day. Templates display the verified `year` and suppress full dates from OpenGraph, JSON-LD, and datetime attributes. RSS remains disabled. The sitemap lists public page URLs without unverified modification timestamps. If an exact date is later verified, review the precision field and formatting before exposing it publicly.

Use structured `publication` fields for venue, volume, issue, pages, publisher, and editors. DOI identifiers belong under `hugoblox.ids.doi`; resource links use the standard Blox `links` array. Blank/unverified abstracts and links are omitted, so there are no fake download buttons.

Projects remain separate records. Their approved `status` is retained; `featured: true` selects the current project in the native collection block. Update these together if a project's status changes. Project dates display the supplied year range. ActEU remains a selected past project despite its 2026 end year.

## Private input

`_build_sources/` is gitignored, outside Hugo's content/static/assets mounts, and is never needed by ordinary builds. Internal quartiles, notes, provenance, and QA fields were excluded by an allowlist import. Tools, caches, dependencies, generated output, and local preview logs are also ignored.

`scripts/import-content.mjs` is a **one-time import utility**, not part of `build` or `dev`. Re-running it overwrites imported public records/pages from the private package; use it only deliberately after reviewing changes. Future routine maintenance should edit the individual public records.

The `data/verified-*-links*.json` files preserve verified public links across a deliberate import. They contain only public links, not research notes or provenance. Audit evidence stays in ignored `.preview/` and is not part of the generated site.

## Adaptations and limitations

- A small publication listing template adds combined type/research-area filters while reusing Blox citations. It works as a complete list without JavaScript.
- Upstream template copies have narrow changes for year-only dates, complete/accent-preserving author metadata, supplied-only publisher/image metadata, and citation publisher display. Publication types have two additional English labels.
- Two link helpers fix a Hugo 0.162.0 empty-map error and recognize the starter's DOI identifier schema. The project collection's standard date/title/summary view has a date-visibility guard.
- A small progressive enhancement makes the native mobile checkbox menu keyboard accessible. CSS supplies restrained spacing, a single green accent, the three research columns, and a minimal footer while retaining the Hugo Blox credit.
- The Markdown block has a small homepage-only extension for `assets/images/jan-kovar.jpg`. Hugo serves the original JPEG unchanged; CSS controls its rectangular crop and responsive placement. It is not configured as a global avatar.
- Header search is disabled; publication filtering is available locally without a search-index service.
- Internal navigation uses page references, and the Markdown link hook handles the project-site prefix. Publication meta descriptions use existing bibliographic facts without supplying an invented abstract.
- pnpm reported that the optional `@parcel/watcher` install script was skipped. The supplied Windows binaries worked, including ordinary live reload. No unneeded lifecycle script was enabled.
- During batch creation of new asset/template directories, the pinned Hugo server encountered a stale-asset error and a watcher panic. A clean restart recovered it. If this recurs while adding directories, stop and rerun the preview command; clean production builds pass.

## Awaiting supplied/verified material

- The approved CV is available at `static/uploads/Jan_Kovar_Academic_CV_2026.pdf`. The contact page keeps `kovar [at] iir.cz`; the supplied PDF retains its original plain institutional email.
- Missing abstracts and PDF/data/code fields remain omitted. Verified official publication links have been added, and all 18 supplied DOI resolvers were checked and preserved. Some publisher websites restrict automated access; unresolved links and bibliographic discrepancies are listed in the local audit report.
- Four projects have verified official links. The migration project's dedicated URL and the sentence describing Jan's specific INTERFER responsibilities remain unresolved. EU IDEA's approved personal participation period (2019–2021) differs from the consortium's 2022 end date and has not been changed.
- “Politics in the Age of Austerity” has no research-area assignment. No publication–project relationships were inferred.
- Publication month/day and online-first journal volume/issue/pages remain omitted where not supplied.

## Prepared GitHub Pages deployment

The default production target is **https://jankov84.github.io/jan-kovar-site/**, configured in `config/production/hugo.yaml`. The development server remains at localhost. A project-site production build includes `/jan-kovar-site/` in navigation, assets, CV downloads, canonicals, and sitemap URLs. The checker validates both path prefixes and case-sensitive asset filenames, even on Windows.

`.github/workflows/pages.yml` uses manual `workflow_dispatch` only. Its `deploy` input defaults to **false**: a normal manual run builds, validates, and uploads a build artifact without publishing. The separate deployment job runs only with `deploy: true`, and its Pages configuration step has `enablement: false`; it cannot turn Pages on. Actions are pinned to verified full commit SHAs; Hugo 0.162.0, pnpm 10.14.0, and Go 1.27.1 are pinned, with Node.js 24.

After explicit approval, the repository must receive its initial source commit on `main`, GitHub Pages must be configured to use GitHub Actions, and the workflow must be invoked with deployment selected. For an additional approval checkpoint, configure required reviewers on the `github-pages` environment. None of those remote actions has been performed. The workflow itself has been syntax-reviewed but cannot be execution-tested without uploading it to GitHub.

The workflow packages only `public/`; private build inputs, tools, caches, and audit evidence are excluded. There is no custom domain or `CNAME`. Changing the hosting URL later requires updating both the production `baseURL` and workflow `SITE_BASE_URL`, followed by the same build/link checks.
