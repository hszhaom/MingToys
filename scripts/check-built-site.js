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

checkPage("index.html", { ads: 1, faq: 0, sources: 0 });
checkPage("posts/2026/05/31/golden-retrievers-sunshine-dogs-of-the-world/index.html", { ads: 1, faq: 1, sources: 1 });
checkPage("posts/2026/06/08/papillon-butterfly-eared-little-fluffy-acrobat/index.html", { ads: 0, faq: 0, sources: 0 });
checkPage("labrador-vs-golden-retriever/index.html", { ads: 1, faq: 1, sources: 1 });
checkPage("apartment-dog-breeds/index.html", { ads: 0, faq: 1, sources: 1 });
checkPage("dog-cost-calculator/index.html", { ads: 0, faq: 1, sources: 1 });

function walk(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const fullPath = path.join(directory, entry.name);
    return entry.isDirectory() ? walk(fullPath) : [fullPath];
  });
}

for (const file of walk(site).filter((item) => item.endsWith(".html"))) {
  const html = fs.readFileSync(file, "utf8");
  for (const match of html.matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g)) {
    try {
      JSON.parse(match[1]);
    } catch (error) {
      throw new Error(`Invalid JSON-LD in ${path.relative(site, file)}: ${error.message}`);
    }
  }
}

const sitemap = read("sitemap.xml");
const urls = [...sitemap.matchAll(/<loc>([^<]+)<\/loc>/g)].map((match) => match[1]);
if (urls.length < 80) throw new Error(`Sitemap contains only ${urls.length} URLs.`);
if (new Set(urls).size !== urls.length) throw new Error("Sitemap contains duplicate URLs.");
if (!urls.includes("https://petstorie.com/posts/2026/05/28/first-story/")) {
  throw new Error("Corgi comparison is missing from the sitemap.");
}

console.log(`Built-site checks passed for ${urls.length} sitemap URLs.`);
