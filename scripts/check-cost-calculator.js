const fs = require("fs");
const path = require("path");
const assert = require("assert/strict");
const { execFileSync } = require("child_process");

const root = path.resolve(__dirname, "..");
const source = fs.readFileSync(path.join(root, process.argv.includes("--built") ? "_site/dog-cost-calculator/index.html" : "pages/dog-cost-calculator.html"), "utf8");
const breeds = JSON.parse(execFileSync("ruby", ["-ryaml", "-rjson", "-e",
  "puts YAML.load_file(ARGV[0]).select { |b| b['publication_status'] == 'published' }.to_json",
  path.join(root, "_data", "breeds.yml")], { encoding: "utf8" }));
const presets = breeds.map(breed => ({
  key: breed.key, name: breed.name, size: breed.size, grooming: breed.grooming,
  training: breed.training, healthRisk: breed.health_risk, costLevel: breed.cost_level,
  url: "https://petstorie.com" + breed.url, costEvidence: breed.evidence?.fields.cost_level.note || null,
  caution: breed.caution
}));
const scripts = [...source.matchAll(/<script>([\s\S]*?)<\/script>/g)].map((match) => match[1]);
let calculator = scripts.find((script) => script.includes("var sizeMonthly"));

if (!calculator) {
  throw new Error("Cost calculator script was not found.");
}

calculator = calculator.replace(/{% for breed in site\.data\.breeds %}[\s\S]*?{% endfor %}/, presets.map(b => JSON.stringify(b)).join(","));
assert.deepEqual(new Function("return " + calculator.match(/var breedPresets = (\[[\s\S]*?\]);/)[1])(), presets,
  "Calculator presets must match the shared dataset, including evidence notes");

const values = {
  "cost-breed": "",
  "cost-size": "toy",
  "cost-grooming": "low",
  "cost-food": "basic",
  "cost-insurance": "savings",
  "cost-training": "basic",
  "cost-setup": "lean"
};

const elements = {};
function getElement(id) {
  if (!elements[id]) {
    elements[id] = {
      id,
      value: values[id] || "",
      textContent: "",
      innerHTML: "",
      listeners: {},
      addEventListener(event, handler) {
        this.listeners[event] = handler;
      }
    };
  }
  return elements[id];
}

const document = {
  getElementById: getElement,
  querySelectorAll() {
    return Object.keys(values).map(getElement);
  }
};

new Function("document", calculator)(document);

if (getElement("monthly-cost").textContent !== "$105–$255") {
  throw new Error(`Unexpected default monthly range: ${getElement("monthly-cost").textContent}`);
}
if (getElement("first-year-cost").textContent !== "$1,660–$3,910") {
  throw new Error(`Unexpected default first-year range: ${getElement("first-year-cost").textContent}`);
}
if ((getElement("cost-breakdown").innerHTML.match(/<tr>/g) || []).length !== 5) {
  throw new Error("Monthly breakdown does not contain five categories.");
}

getElement("cost-size").value = "giant";
getElement("cost-grooming").value = "high";
getElement("cost-food").value = "premium";
getElement("cost-insurance").value = "insurance";
getElement("cost-size").listeners.change();

if (getElement("monthly-cost").textContent === "$105–$255") {
  throw new Error("Changing calculator inputs did not update the range.");
}

console.log("Cost calculator checks passed.");

function change(id, value) {
  getElement(id).value = value;
  getElement(id).listeners.change();
}

// Exercise every real published preset, including both cost/health flag branches.
for (const breed of presets) {
  change("cost-food", "basic");
  change("cost-breed", breed.key);
  assert.equal(getElement("cost-food").value, "basic", `${breed.key} forced a food upgrade`);
  assert.equal(getElement("cost-size").value, breed.size);
  assert.equal(getElement("cost-grooming").value, breed.grooming);
  assert.equal(getElement("cost-guide-link").href, breed.url);
  assert.equal(getElement("cost-guide-link").hidden, false);
  assert.ok(getElement("cost-preset-reason").textContent.includes("cost flag " + breed.costLevel));
  assert.ok(getElement("cost-note").textContent.includes(breed.caution));
  assert.ok(/^\$[\d,]+–\$[\d,]+$/.test(getElement("monthly-cost").textContent));
  assert.ok(getElement("cost-evidence-note").textContent.includes(breed.costEvidence || "No field-level cost evidence"));
  assert.ok(getElement("cost-evidence-link").href.endsWith(breed.costEvidence ? "#evidence-" + breed.key : "#household-fit-data"));
  change("cost-food", "premium");
  change("cost-breed", breed.key);
  assert.equal(getElement("cost-food").value, "premium", "Breed changes must preserve an explicit food allowance");
}
change("cost-food", "basic");
change("cost-breed", "french-bulldog");
assert.equal(getElement("monthly-cost").textContent, "$200–$470");
assert.equal(getElement("first-year-cost").textContent, "$3,200–$7,590");
change("cost-food", "premium");
assert.equal(getElement("monthly-cost").textContent, "$225–$545");
change("cost-grooming", "low");
assert.equal(getElement("monthly-cost").textContent, "$200–$495");
assert.ok(getElement("cost-reserve-note").textContent.includes("$40–$110"), "Editing controls must not silently remove the breed buffer");
change("cost-breed", "");
assert.equal(getElement("cost-food").value, "premium");
assert.equal(getElement("cost-guide-link").hidden, true);
assert.ok(getElement("cost-preset-reason").textContent.startsWith("Manual settings:"));
assert.ok(getElement("cost-reserve-note").textContent.includes("$0–$20"));

// Invalid selections must clear stale totals, notes and breed links, then recover.
for (const id of Object.keys(values)) {
  const previous = getElement(id).value;
  change(id, "unrecognized");
  assert.equal(getElement("monthly-cost").textContent, "Not calculated");
  assert.equal(getElement("first-year-cost").textContent, "Not calculated");
  assert.equal(getElement("cost-breakdown").innerHTML, "");
  assert.equal(getElement("cost-guide-link").hidden, true);
  change(id, previous);
  assert.notEqual(getElement("monthly-cost").textContent, "Not calculated");
}
assert.ok(source.includes("<noscript>"));
assert.ok(source.includes('aria-describedby="food-plan-note"'));
assert.ok(source.includes('scope="col"'));
console.log(`Preset and recovery checks passed for all ${presets.length} published breeds${process.argv.includes("--built") ? " in rendered HTML" : ""}.`);
