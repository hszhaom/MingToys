const fs = require("fs");
const path = require("path");
const assert = require("assert/strict");
const { execFileSync } = require("child_process");

const root = path.resolve(__dirname, "..");
const built = process.argv.includes("--built");
const source = fs.readFileSync(path.join(root, built ? "_site/dog-breed-finder/index.html" : "pages/dog-breed-finder.html"), "utf8");
const data = JSON.parse(execFileSync("ruby", ["-ryaml", "-rjson", "-e",
  "puts YAML.load_file(ARGV[0]).select { |b| b['publication_status'] == 'published' }.to_json",
  path.join(root, "_data/breeds.yml")], { encoding: "utf8" }));
const records = data.map(b => ({
  key: b.key, name: b.name, url: "https://petstorie.com" + b.url, summary: b.summary,
  size: b.size, home: b.home, experience: b.experience, kids: b.kids, exercise: b.exercise,
  shedding: b.shedding, grooming: b.grooming, training: b.training, healthRisk: b.health_risk,
  costLevel: b.cost_level, caution: b.caution, hasEvidence: Boolean(b.evidence)
}));
let script = [...source.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(m => m[1]).find(s => s.includes("function assessBreed"));
assert.ok(script, "Finder script exists");
script = script.replace(/{% for breed in site\.data\.breeds %}[\s\S]*?{% endfor %}/, records.map(b => JSON.stringify(b)).join(","));
script = script.replace(/{{ site.url }}/g, "https://petstorie.com");
assert.deepEqual(new Function("return " + script.match(/var breeds = (\[[\s\S]*?\]);/)[1])(), records,
  "Finder records must agree with the shared dataset");

const defaults = { "home-type": "apartment", experience: "first", kids: "yes", exercise: "low",
  shedding: "low", grooming: "low", "care-cooling": "unsure", "care-weekday": "unsure", "care-vet": "unsure" };
function run(code) {
  const elements = {};
  function get(id) {
    return elements[id] ||= { value: defaults[id] || "", innerHTML: "", textContent: "", listeners: {},
      addEventListener(event, handler) { this.listeners[event] = handler; } };
  }
  const document = { getElementById: get, querySelectorAll: () => Object.keys(defaults).map(get) };
  const exposed = code.replace(/render\(\);\s*\}\)\(\);\s*$/, "render(); return { assessBreed, renderBreed, breeds }; })();");
  const api = new Function("document", "return " + exposed.trim())(document);
  return { ...api, get, change(id, value) { get(id).value = value; get(id).listeners.change(); } };
}
const app = run(script);
assert.match(app.get("finder-status").textContent, /3 care checks/);
assert.equal((app.get("best-breed-results").innerHTML.match(/<article /g) || []).length, 6);
const originalCards = app.get("best-breed-results").innerHTML;
for (const cooling of ["unsure", "planned", "missing"]) {
  for (const weekday of ["unsure", "planned", "missing"]) {
    for (const vet of ["unsure", "planned", "missing"]) {
      app.change("care-cooling", cooling); app.change("care-weekday", weekday); app.change("care-vet", vet);
      const values = [cooling, weekday, vet];
      const remaining = values.filter(v => v !== "planned").length;
      assert.equal((app.get("care-next-steps").innerHTML.match(/<li>/g) || []).length, remaining);
      assert.match(app.get("finder-status").textContent, values.includes("missing") ? /Pause shortlisting/ : remaining ? new RegExp(remaining + " care checks") : /self-reported, not verified/);
      assert.equal(app.get("best-breed-results").innerHTML, originalCards, "Care answers must not alter ranking or imply validated suitability");
    }
  }
}

// Keep the existing ordering while making its limitations visible.
const levels = { home: ["apartment", "house", "rural"], experience: ["first", "some", "experienced"],
  exercise: ["low", "medium", "high"], shedding: ["low", "medium", "high"], grooming: ["low", "medium", "high"], kids: ["yes", "no"] };
let combinations = [{}];
for (const [key, values] of Object.entries(levels)) combinations = combinations.flatMap(f => values.map(value => ({ ...f, [key]: value })));
for (const b of records) {
  for (const f of combinations) {
    let expected = 100;
    for (const [key, weight] of Object.entries({ home: 22, experience: 18, exercise: 15, shedding: 10, grooming: 8 })) {
      expected -= Math.abs(levels[key].indexOf(f[key]) - levels[key].indexOf(b[key])) * weight;
    }
    if (f.kids !== b.kids) expected -= 12;
    if (f.experience === "first" && b.training === "hard") expected -= 10;
    if (f.home === "apartment" && b.size === "giant") expected -= 12;
    if (f.exercise === "low" && b.exercise === "high") expected -= 10;
    assert.equal(app.assessBreed(b, f).score, Math.max(18, Math.min(100, expected)), b.key);
  }
  const assessment = app.assessBreed(b, b);
  const card = app.renderBreed({ ...b, ...assessment });
  assert.ok(!card.includes("/100") && !card.includes("score-bar"));
  assert.ok(card.includes(b.hasEvidence ? "#evidence-" + b.key : "#field-evidence"));
  if (built) {
    assert.ok(fs.existsSync(path.join(root, "_site", new URL(b.url).pathname, "index.html")));
    const evidencePage = fs.readFileSync(path.join(root, "_site/data-sources/index.html"), "utf8");
    assert.ok(evidencePage.includes('id="' + (b.hasEvidence ? 'evidence-' + b.key : 'field-evidence') + '"'));
  }
  assert.match(card, /Matching labels:/); assert.match(card, /Main care trade-off to check:/);
  assert.ok(assessment.matches.includes("Activity: " + b.exercise[0].toUpperCase() + b.exercise.slice(1)));
}
const frenchie = records.find(b => b.key === "french-bulldog");
assert.equal(app.assessBreed(frenchie, frenchie).score, 100);
assert.match(app.assessBreed(frenchie, frenchie).difference, /individual-dog checks still apply/);
const golden = records.find(b => b.key === "golden-retriever");
assert.match(app.assessBreed(golden, { ...golden, exercise: "low" }).difference, /Activity label: High; your answer: Low/);
const unsafe = app.renderBreed({ ...frenchie, ...app.assessBreed(frenchie, frenchie), name: '<img src=x onerror="bad()">', caution: "<script>bad()</script>" });
assert.ok(!unsafe.includes("<img") && !unsafe.includes("<script>"));
for (const id of Object.keys(defaults)) {
  app.change(id, "invalid");
  assert.match(app.get("finder-status").textContent, /Choose an available option/);
  assert.ok(!app.get("best-breed-results").innerHTML.includes("<article"));
  assert.equal(app.get("possible-breed-results").innerHTML, "");
  app.change(id, defaults[id]);
  assert.ok(app.get("best-breed-results").innerHTML.includes("<article"));
}
const empty = run(script.replace(/var breeds = \[[\s\S]*?\];/, "var breeds = [];"));
assert.match(empty.get("finder-status").textContent, /results are unavailable/);
assert.match(empty.get("best-breed-results").innerHTML, /Browse the breed directory/);
assert.ok(source.includes('role="status"') && source.includes('aria-atomic="true"'));
assert.ok(source.includes("Interactive results require JavaScript"));
console.log(`Finder checks passed: ${records.length} shared records, ${combinations.length} preference combinations each, 27 care states, empty/error recovery and escaping${built ? " (built HTML)" : ""}.`);
