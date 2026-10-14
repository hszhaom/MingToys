const fs = require("fs");
const path = require("path");
const assert = require("assert/strict");
const { execFileSync } = require("child_process");
const root = path.resolve(__dirname, "..");
const built = process.argv.includes("--built");
const source = fs.readFileSync(path.join(root, built ? "_site/dog-breed-selector/index.html" : "pages/dog-breed-selector.html"), "utf8");
const data = JSON.parse(execFileSync("ruby", ["-ryaml", "-rjson", "-e",
  "puts YAML.load_file(ARGV[0]).select { |b| b['publication_status'] == 'published' }.to_json",
  path.join(root, "_data/breeds.yml")], { encoding: "utf8" }));
const records = data.map(b => ({ key: b.key, name: b.name, url: "https://petstorie.com" + b.url,
  summary: b.summary, size: b.size, home: b.home, experience: b.experience, kids: b.kids,
  exercise: b.exercise, shedding: b.shedding, grooming: b.grooming, training: b.training,
  healthRisk: b.health_risk, costLevel: b.cost_level, caution: b.caution, hasEvidence: Boolean(b.evidence) }));
let script = [...source.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(m => m[1]).find(s => s.includes("function renderComparison"));
script = script.replace(/{% for breed in site\.data\.breeds %}[\s\S]*?{% endfor %}/, records.map(b => JSON.stringify(b)).join(","))
  .replace(/{{ site.url }}/g, "https://petstorie.com");
assert.deepEqual(new Function("return " + script.match(/var breeds = (\[[\s\S]*?\]);/)[1])(), records);
function run(code) {
  const defaults = { "breed-a": "labrador-retriever", "breed-b": "golden-retriever", "owner-priority": "first", "max-grooming": "high" };
  const elements = {};
  const get = id => elements[id] ||= { value: defaults[id] || "", innerHTML: "", listeners: {},
    addEventListener(event, handler) { this.listeners[event] = handler; } };
  const document = { getElementById: get, querySelectorAll: () => Object.keys(defaults).map(get) };
  new Function("document", code)(document);
  return { get, change(id, value) { get(id).value = value; get(id).listeners.change(); } };
}
const app = run(script);
const comparison = () => app.get("selector-comparison").innerHTML;
const clean = html => html.replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim();
if (built) {
  const initial = source.match(/<div id="selector-comparison">([\s\S]*?)<\/div>/)[1];
  assert.equal(clean(initial), clean(comparison()), "Default HTML and interactive comparison must agree, including evidence and cautions");
  assert.match(initial, /<caption>/);
  assert.equal((initial.match(/scope="row"/g) || []).length, 11);
}
assert.match(source, /<noscript>/);
assert.match(source, /aria-live="polite"/);
for (const breed of records) {
  app.change("breed-a", breed.key);
  assert.ok(comparison().includes(breed.url));
  assert.ok(comparison().includes(breed.hasEvidence ? "#evidence-" + breed.key : "Field evidence has not yet been recorded"));
  if (built && breed.hasEvidence) assert.ok(fs.readFileSync(path.join(root, "_site/data-sources/index.html"), "utf8").includes('id="evidence-' + breed.key + '"'));
}
app.change("breed-a", "golden-retriever");
assert.match(comparison(), /same breed twice/);
app.change("breed-a", "invalid");
assert.match(comparison(), /Choose two available breeds/);
app.change("breed-a", "labrador-retriever");
assert.doesNotMatch(comparison(), /Choose two available breeds/);
const original = comparison();
const rules = {
  first: b => b.experience === "first" && b.training !== "hard",
  apartment: b => b.home === "apartment" && b.exercise !== "high",
  family: b => b.kids === "yes" && b.experience !== "experienced",
  "low-shedding": b => b.shedding === "low", active: b => b.exercise === "high",
  guardian: b => b.experience === "experienced" && (b.training === "hard" || b.home === "rural")
};
for (const priority of Object.keys(rules)) for (const grooming of ["low", "medium", "high"]) {
  app.change("owner-priority", priority); app.change("max-grooming", grooming);
  assert.equal(comparison(), original, "Shortlist filters must not change the selected pair");
  const expected = records.filter(b => rules[priority](b) && ["low", "medium", "high"].indexOf(b.grooming) <= ["low", "medium", "high"].indexOf(grooming)).slice(0, 8).map(b => b.url);
  const actual = [...app.get("selector-shortlist").innerHTML.matchAll(/href="([^"]+)"/g)].map(m => m[1]);
  assert.deepEqual(actual, expected, "Preserve shortlist membership and dataset order");
}
const empty = run(script.replace(/var breeds = \[[\s\S]*?\];/, "var breeds = [];"));
assert.match(empty.get("selector-comparison").innerHTML, /Choose two available breeds/);
assert.match(empty.get("selector-shortlist").innerHTML, /No breed profiles match/);
const hostile = run(script.replace('function evidenceStep(breed) {', 'function evidenceStep(breed) { breed = {...breed, name: "<img src=x onerror=alert(1)>"};'));
assert.doesNotMatch(hostile.get("selector-comparison").innerHTML, /<img/);
assert.match(hostile.get("selector-comparison").innerHTML, /&lt;img/);
console.log(`PASS breed selector (${built ? "built" : "source"}): ${records.length} shared records, evidence paths, 18 filters, same/invalid/empty states, escaping${built ? ", default HTML parity" : ""}`);
