const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "..");
const site = path.join(root, "_site");

function read(relativePath) {
  const file = path.join(site, ...relativePath.split("/"));
  if (!fs.existsSync(file)) throw new Error(`Built file is missing: ${relativePath}`);
  return fs.readFileSync(file, "utf8");
}

function count(text, token) {
  return text.split(token).length - 1;
}

function checkPage(relativePath, expected) {
  const html = read(relativePath);
  const adCount = count(html, "pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=");
  const faqSchemaCount = count(html, '"@type": "FAQPage"');
  const visibleFaqCount = count(html, 'id="faq-title"');
  const sourceCount = count(html, 'id="sources-title"');

  if (adCount !== expected.ads) throw new Error(`${relativePath} has ${adCount} AdSense scripts; expected ${expected.ads}.`);
  if (faqSchemaCount !== expected.faq) throw new Error(`${relativePath} has ${faqSchemaCount} FAQ schemas; expected ${expected.faq}.`);
  if (visibleFaqCount !== expected.faq) throw new Error(`${relativePath} has ${visibleFaqCount} visible FAQ sections; expected ${expected.faq}.`);
  if (sourceCount !== expected.sources) throw new Error(`${relativePath} has ${sourceCount} source sections; expected ${expected.sources}.`);
  if (html.includes("{{") || html.includes("{%")) throw new Error(`${relativePath} contains unrendered Liquid.`);
}

checkPage("index.html", { ads: 0, faq: 0, sources: 0 });
checkPage("posts/2026/05/31/golden-retrievers-sunshine-dogs-of-the-world/index.html", { ads: 0, faq: 1, sources: 1 });
checkPage("posts/2026/06/08/papillon-butterfly-eared-little-fluffy-acrobat/index.html", { ads: 0, faq: 0, sources: 0 });
checkPage("labrador-vs-golden-retriever/index.html", { ads: 0, faq: 1, sources: 1 });
checkPage("apartment-dog-breeds/index.html", { ads: 0, faq: 1, sources: 1 });
checkPage("dog-cost-calculator/index.html", { ads: 0, faq: 1, sources: 1 });

const aboutPage = read("about/index.html");
if (!aboutPage.includes('"@type": "Person"') || !aboutPage.includes('"name": "ming.zhao"')) {
  throw new Error("The About page is missing the named Person schema for ming.zhao.");
}

const reviewedPost = read("posts/2026/05/31/golden-retrievers-sunshine-dogs-of-the-world/index.html");
if (!reviewedPost.includes('"author": {\n    "@type": "Person"') || !reviewedPost.includes('"name": "ming.zhao"')) {
  throw new Error("Reviewed articles must retain the named ming.zhao author schema.");
}

function walk(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const fullPath = path.join(directory, entry.name);
    return entry.isDirectory() ? walk(fullPath) : [fullPath];
  });
}

for (const file of walk(site).filter((item) => item.endsWith(".html"))) {
  const html = fs.readFileSync(file, "utf8");
  if (count(html, "pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=") !== 0) {
    throw new Error(`${path.relative(site, file)} renders an AdSense script while site-wide advertising is paused.`);
  }
  for (const match of html.matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g)) {
    try {
      JSON.parse(match[1]);
    } catch (error) {
      throw new Error(`Invalid JSON-LD in ${path.relative(site, file)}: ${error.message}`);
    }
  }
}

const postFiles = fs.readdirSync(path.join(root, "_posts")).filter((file) => file.endsWith(".md"));

if (fs.existsSync(path.join(root, "_data", "breed_owner_guidance.json"))) {
  throw new Error("Retired owner-guidance data is still present.");
}
if (fs.existsSync(path.join(root, "_includes", "breed-owner-guidance.html"))) {
  throw new Error("Retired owner-guidance include is still present.");
}

for (const postFile of postFiles) {
  const match = postFile.match(/^(\d{4})-(\d{2})-(\d{2})-(.+)\.md$/);
  if (!match) throw new Error(`Invalid post filename: ${postFile}`);

  const [, year, month, day, slug] = match;
  const relativePath = `posts/${year}/${month}/${day}/${slug}/index.html`;
  const html = read(relativePath);
  const source = fs.readFileSync(path.join(root, "_posts", postFile), "utf8");
  const moduleCount = count(html, "data-breed-owner-guidance");
  const adCount = count(html, "pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=");
  const expectedAds = 0;
  const updatedMatch = source.match(/^updated:\s*["']?(\d{4}-\d{2}-\d{2})["']?\s*$/m);
  const hasSources = /^sources:\s*$/m.test(source);
  const expectsNoindex = /^noindex:\s*true\s*$/m.test(source);

  if (moduleCount !== 0) throw new Error(`${relativePath} still renders centralized owner guidance.`);
  if (adCount !== expectedAds) throw new Error(`${relativePath} has ${adCount} AdSense scripts; expected ${expectedAds}.`);
  if (!hasSources && !expectsNoindex) {
    throw new Error(`${postFile} is indexable without page-level sources.`);
  }
  if (expectsNoindex && !html.includes('name="robots" content="noindex, follow"')) {
    throw new Error(`${relativePath} must expose noindex while it remains in editorial review.`);
  }
  if (!expectsNoindex && !html.includes('name="robots" content="index, follow"')) {
    throw new Error(`${relativePath} should remain indexable after its source review.`);
  }
  if (!hasSources && updatedMatch) throw new Error(`${postFile} exposes an updated date before source review.`);
  if (!expectsNoindex && !updatedMatch) throw new Error(`${postFile} has sources but no page-level updated date.`);
  if (!source.includes("/dog-cost-calculator/") || !source.includes("/dog-fit-score-cards/")) {
    throw new Error(`${postFile} does not link directly to both dog decision tools.`);
  }
  if (!html.includes('href="https://petstorie.com/dog-cost-calculator/"')) {
    throw new Error(`${relativePath} is missing the dog cost calculator link.`);
  }
  if (!html.includes('href="https://petstorie.com/dog-fit-score-cards/"')) {
    throw new Error(`${relativePath} is missing the dog fit score link.`);
  }
  if (updatedMatch && !html.includes(`"dateModified": "${updatedMatch[1]}"`)) {
    throw new Error(`${relativePath} does not use its page-level updated date.`);
  }
  if (!updatedMatch && html.includes('"dateModified":')) {
    throw new Error(`${relativePath} exposes dateModified without a verified updated date.`);
  }
}

const sitemap = read("sitemap.xml");
const urls = [...sitemap.matchAll(/<loc>([^<]+)<\/loc>/g)].map((match) => match[1]);
if (new Set(urls).size !== urls.length) throw new Error("Sitemap contains duplicate URLs.");

const pageFiles = fs.readdirSync(path.join(root, "pages")).filter((file) => file.endsWith(".html"));
for (const pageFile of pageFiles) {
  const source = fs.readFileSync(path.join(root, "pages", pageFile), "utf8");
  const permalinkMatch = source.match(/^permalink:\s*([^\r\n]+)$/m);
  const isNoindex = /^noindex:\s*true\s*$/m.test(source);
  if (!permalinkMatch || !isNoindex) continue;

  const permalink = permalinkMatch[1].trim();
  const pageUrl = `https://petstorie.com${permalink}`;
  const relativePath = `${permalink.replace(/^\//, "").replace(/\/$/, "")}/index.html`;
  const html = read(relativePath);
  if (!html.includes('name="robots" content="noindex, follow"')) {
    throw new Error(`${pageFile} is marked noindex but does not render the correct robots meta tag.`);
  }
  if (urls.includes(pageUrl)) throw new Error(`${pageFile} is noindex but still appears in the sitemap.`);
}

for (const postFile of postFiles) {
  const [, year, month, day, slug] = postFile.match(/^(\d{4})-(\d{2})-(\d{2})-(.+)\.md$/);
  const source = fs.readFileSync(path.join(root, "_posts", postFile), "utf8");
  const updatedMatch = source.match(/^updated:\s*["']?(\d{4}-\d{2}-\d{2})["']?\s*$/m);
  const postUrl = `https://petstorie.com/posts/${year}/${month}/${day}/${slug}/`;
  const hasSources = /^sources:\s*$/m.test(source);
  const isNoindex = /^noindex:\s*true\s*$/m.test(source);
  if (isNoindex && urls.includes(postUrl)) throw new Error(`${postFile} is noindex but still appears in the sitemap.`);
  if (!isNoindex) {
    if (!hasSources) throw new Error(`${postFile} is indexable without page-level sources.`);
    const expected = `<loc>${postUrl}</loc>\n    <lastmod>${updatedMatch[1]}</lastmod>`;
    if (!sitemap.includes(expected)) throw new Error(`Sitemap lastmod is incorrect for ${postFile}.`);
  }
}

console.log(`Built-site checks passed for ${urls.length} sitemap URLs and ${postFiles.length} direct article updates.`);
