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
  "cost-setup": "lean",
  "cost-base-care": "assumption",
  "cost-walks": "excluded"
};
const baseInputs = [...source.matchAll(/<input id="(cost-base-[^"]+)"[^>]*>/g)];
assert.equal(baseInputs.length, 4);
const baseRules = Object.fromEntries(baseInputs.map(([tag, id]) => [id,
  Object.fromEntries([...tag.matchAll(/(min|max|step|type)="([^"]*)"/g)].map(m => [m[1], m[2]]))]));
const walkInputs = [...source.matchAll(/<input id="(cost-walk-[^"]+)"[^>]*>/g)];
assert.equal(walkInputs.length, 4);
const inputRules = Object.fromEntries(walkInputs.map(([tag, id]) => [id,
  Object.fromEntries([...tag.matchAll(/(min|max|step|type)="([^"]*)"/g)].map(m => [m[1], m[2]]))]));
Object.assign(inputRules, baseRules);
for (const id of Object.keys(inputRules)) values[id] = "";

const elements = {};
function getElement(id) {
  if (!elements[id]) {
    elements[id] = {
      id,
      ...inputRules[id],
      value: values[id] || "",
      textContent: "",
      innerHTML: "",
      listeners: {},
      attributes: {},
      setAttribute(name, value) { this.attributes[name] = value; },
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

const window = {
  listeners: {},
  prints: 0,
  addEventListener(event, handler) { this.listeners[event] = handler; },
  print() { this.prints++; }
};
new Function("document", "window", calculator)(document, window);

if (getElement("monthly-cost").textContent !== "$105–$255") {
  throw new Error(`Unexpected default monthly range: ${getElement("monthly-cost").textContent}`);
}
if (getElement("first-year-cost").textContent !== "$1,660–$3,910") {
  throw new Error(`Unexpected default first-year range: ${getElement("first-year-cost").textContent}`);
}
if ((getElement("cost-breakdown").innerHTML.match(/<tr>/g) || []).length !== 5) {
  throw new Error("Monthly breakdown does not contain five categories.");
}
assert.ok(getElement("cost-breakdown").innerHTML.includes("Base care by size (assumption)"));
assert.ok(getElement("cost-breakdown").innerHTML.includes("Emergency savings contribution (assumption)"));
change("cost-insurance", "insurance");
assert.ok(getElement("cost-breakdown").innerHTML.includes("Pet-insurance premium (assumption)"));
change("cost-insurance", "savings");

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
for (const id of Object.keys(values).filter(id => !inputRules[id])) {
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
assert.ok(source.includes('aria-describedby="financial-plan-note"'));
assert.ok(source.includes('aria-describedby="base-care-input-note"'));
assert.ok(source.includes("Emergency savings contribution (assumption)"));
assert.ok(source.includes("Pet-insurance premium (assumption)"));
assert.ok(source.includes('scope="col"'));
console.log(`Preset and recovery checks passed for all ${presets.length} published breeds${process.argv.includes("--built") ? " in rendered HTML" : ""}.`);

// Local base-care quotes replace, rather than add to, the broad size assumption.
for (const [id, value] of Object.entries({ "cost-breed": "", "cost-size": "toy", "cost-grooming": "low",
  "cost-food": "basic", "cost-insurance": "savings", "cost-training": "basic", "cost-setup": "lean", "cost-walks": "excluded" })) change(id, value);
change("cost-base-care", "local");
assert.equal(getElement("monthly-cost").textContent, "Not calculated", "Blank local base quotes must not silently become free care");
function baseQuote(foodLow, foodHigh, vetLow, vetHigh) {
  [foodLow, foodHigh, vetLow, vetHigh].forEach((v, i) => change(Object.keys(baseRules)[i], String(v)));
}
baseQuote(50, 70, 240, 360);
assert.equal(getElement("monthly-cost").textContent, "$120–$250", "Local base quotes must replace the toy size assumption");
assert.equal(getElement("annual-cost").textContent, "$1,440–$3,000");
assert.equal(getElement("first-year-cost").textContent, "$1,840–$3,850");
assert.ok(getElement("cost-breakdown").innerHTML.includes("Local base care (your quotes)"));
for (const [id, bad] of [["cost-base-food-low", ""], ["cost-base-food-low", "-1"], ["cost-base-food-high", "49"], ["cost-base-vet-low", "10000.001"], ["cost-base-vet-high", "239"]]) {
  baseQuote(50, 70, 240, 360);
  change(id, bad);
  assert.equal(getElement("monthly-cost").textContent, "Not calculated", `${id}=${bad} retained stale total`);
  assert.equal(getElement(id).attributes["aria-invalid"], "true");
}
for (const id of Object.keys(baseRules)) {
  for (const bad of ["", "NaN", "Infinity", "-0.01", String(Number(baseRules[id].max) + 0.01), "50.001"]) {
    baseQuote(50, 70, 240, 360);
    change(id, bad);
    for (const total of ["monthly-cost", "annual-cost", "setup-cost", "first-year-cost"]) {
      assert.equal(getElement(total).textContent, "Not calculated", `${id}=${bad}: stale ${total}`);
    }
    assert.equal(getElement(id).attributes["aria-invalid"], "true");
  }
}
baseQuote(0, 0, 0, 0);
assert.equal(getElement("annual-cost").textContent, "$600–$1,800");
baseQuote(5000, 5000, 10000, 10000);
assert.equal(getElement("annual-cost").textContent, "$70,600–$71,800");
baseQuote(19.99, 19.99, 100.01, 100.01);
assert.equal(getElement("annual-cost").textContent, "$940–$2,140");
baseQuote(50, 70, 240, 360);
change("cost-walks", "included");
for (const [id, value] of Object.entries({"cost-walk-low":"20", "cost-walk-high":"30", "cost-walk-visits":"5", "cost-walk-weeks":"48"})) change(id, value);
assert.equal(getElement("annual-cost").textContent, "$6,240–$10,200", "Local base and optional walks must each count once");
change("cost-walks", "excluded");
change("cost-breed", "labrador-retriever");
assert.equal(getElement("cost-base-food-low").value, "50", "Breed changes must preserve local quotes");
change("cost-breed", "");
change("cost-size", "toy");
change("cost-grooming", "low");
baseQuote(50, 70, 240, 360);
change("cost-base-care", "assumption");
assert.equal(getElement("monthly-cost").textContent, "$105–$255", "Returning to the assumption must recover defaults");

// Local quotes: weeks, not four-week months; no intermediate money rounding.
for (const [, id] of walkInputs) change(id, "");
for (const [id, value] of Object.entries({ "cost-breed": "", "cost-size": "toy", "cost-grooming": "low",
  "cost-food": "basic", "cost-insurance": "savings", "cost-training": "basic", "cost-setup": "lean", "cost-base-care": "assumption" })) change(id, value);
assert.equal(getElement("annual-cost").textContent, "$1,260–$3,060");
assert.equal(getElement("setup-cost").textContent, "$400–$850");
assert.equal(getElement("cost-walk-fields").hidden, true);
change("cost-walks", "included");
assert.equal(getElement("monthly-cost").textContent, "Not calculated", "Blank quote must not silently become free care");
assert.equal(getElement("cost-walk-low").attributes["aria-invalid"], "true");
function quote(low, high, visits, weeks) {
  [low, high, visits, weeks].forEach((v, i) => change(Object.keys(inputRules)[i], String(v)));
}
quote(20, 30, 5, 48);
assert.equal(getElement("monthly-cost").textContent, "$505–$855");
assert.equal(getElement("annual-cost").textContent, "$6,060–$10,260");
assert.equal(getElement("first-year-cost").textContent, "$6,460–$11,110");
assert.equal(getElement("setup-cost").textContent, "$400–$850");
assert.ok(getElement("cost-walk-note").textContent.includes("240 visits per year"));
assert.equal((getElement("cost-breakdown").innerHTML.match(/<tr>/g) || []).length, 6);
change("cost-breed", "labrador-retriever");
assert.equal(getElement("cost-walk-low").value, "20", "Breed preset must preserve the local quote");
assert.equal(getElement("cost-walk-weeks").value, "48");
change("cost-breed", "");
change("cost-size", "toy");
change("cost-grooming", "low");
quote(19.99, 19.99, 3, 50);
assert.ok(getElement("cost-walk-note").textContent.includes("at $19.99 per visit"));
assert.ok(getElement("cost-walk-note").textContent.includes("Added annual cost: $2,999; monthly average: $250"));
assert.equal(getElement("annual-cost").textContent, "$4,259–$6,059");
assert.equal(getElement("first-year-cost").textContent, "$4,659–$6,909");
quote(0, 0, 0, 0);
assert.equal(getElement("monthly-cost").textContent, "$105–$255");
quote(1000, 1000, 21, 52);
assert.ok(getElement("cost-walk-note").textContent.includes("Added annual cost: $1,092,000"));
quote(20, 30, 5, 0);
assert.equal(getElement("annual-cost").textContent, "$1,260–$3,060");
for (const [id, bad] of [
  ["cost-walk-low", ""], ["cost-walk-low", "-1"], ["cost-walk-low", "1001"],
  ["cost-walk-low", "NaN"], ["cost-walk-low", "Infinity"], ["cost-walk-low", "20.001"],
  ["cost-walk-high", "19"], ["cost-walk-high", ""], ["cost-walk-high", "1001"],
  ["cost-walk-visits", ""], ["cost-walk-visits", "22"], ["cost-walk-visits", "1.5"],
  ["cost-walk-weeks", ""], ["cost-walk-weeks", "53"], ["cost-walk-weeks", "-1"], ["cost-walk-weeks", "2.5"]
]) {
  quote(20, 30, 5, 48);
  change(id, bad);
  for (const total of ["monthly-cost", "annual-cost", "setup-cost", "first-year-cost"]) {
    assert.equal(getElement(total).textContent, "Not calculated", `${id}=${bad} retained stale ${total}`);
  }
  assert.equal(getElement(id).attributes["aria-invalid"], "true");
  assert.equal(getElement("cost-walk-note").textContent, "");
  change("cost-walks", "excluded");
  assert.equal(getElement("monthly-cost").textContent, "$105–$255");
  assert.equal(getElement("cost-walk-error").textContent, "");
  change("cost-walks", "included");
}
quote(20, 30, 5, 48);
getElement("cost-walk-low").value = "25";
getElement("cost-walk-low").listeners.input();
assert.equal(getElement("monthly-cost").textContent, "$605–$855", "Typing must update the estimate");
let prevented = false;
getElement("dog-cost-form").listeners.submit({ preventDefault() { prevented = true; } });
assert.ok(prevented, "Enter must not reload and discard quote inputs");
assert.ok(source.includes("USD") && source.includes("No currency conversion"));
const care = JSON.parse(execFileSync("ruby", ["-ryaml", "-rjson", "-e", "puts YAML.load_file(ARGV[0]).to_json",
  path.join(root, "_data", "care_costs.yml")], { encoding: "utf8" }));
const walk = care.items.paid_dog_walks;
for (const key of ["name", "frequency", "region", "dog_scope", "qualitative_range", "currency", "baseline_year", "includes", "excludes", "calculation", "confidence", "editorial_note", "accessed"]) assert.ok(walk[key], key);
assert.equal(walk.minimum, null);
assert.equal(walk.maximum, null);
assert.equal(walk.currency, "USD");
assert.equal(care.review_status, "not professionally reviewed");
const protection = care.items.financial_protection;
for (const key of ["name", "frequency", "region", "dog_scope", "qualitative_range", "currency", "baseline_year", "includes", "excludes", "calculation", "confidence", "editorial_note", "accessed"]) assert.ok(protection[key], key);
assert.equal(protection.minimum, null);
assert.equal(protection.maximum, null);
assert.equal(protection.sources.length, 2);
const baseCare = care.items.local_base_care_quotes;
for (const key of ["name", "frequency", "region", "dog_scope", "qualitative_range", "currency", "baseline_year", "includes", "excludes", "calculation", "confidence", "editorial_note", "accessed"]) assert.ok(baseCare[key], key);
assert.equal(baseCare.minimum, null);
assert.equal(baseCare.maximum, null);
assert.equal(baseCare.sources.length, 1);
assert.equal(walk.care_plan.length, 4);
assert.ok(walk.sources.length >= 2);
assert.equal(walk.cancellation_checks.length, 4);
for (const check of walk.cancellation_checks) assert.ok(check.question && check.action);
if (process.argv.includes("--built")) {
  const escapeHTML = text => text.replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  for (const task of walk.care_plan) assert.ok(source.includes(escapeHTML(task.action)), "Rendered care plan must use shared data");
  for (const reference of walk.sources) assert.ok(source.includes(reference.url) && source.includes(reference.accessed));
  for (const reference of protection.sources) assert.ok(source.includes(reference.url) && source.includes(reference.accessed));
  for (const reference of baseCare.sources) assert.ok(source.includes(reference.url) && source.includes(reference.accessed));
  assert.ok(source.includes(walk.confidence));
  const routines = fs.readFileSync(path.join(root, "_site", "home-routines", "index.html"), "utf8");
  for (const check of walk.cancellation_checks) {
    assert.ok(routines.includes(escapeHTML(check.question)) && routines.includes(escapeHTML(check.action)), "Cancellation worksheet must render shared data");
  }
  assert.ok(source.includes('/home-routines/#walker-cancellation'));
  assert.ok(routines.includes('/dog-cost-calculator/#paid-walks') && routines.includes('/dog-cost-calculator/#walk-care-plan'));
}
console.log("Paid-walk quote checks passed: missing/min/max/invalid inputs, USD, annual averaging, cents, optional exclusion, preserved quote, recovery and shared evidence.");

// Browser-menu printing and the button must use current inputs and retain evidence.
assert.equal(getElement("cost-print").hidden, false);
getElement("cost-print").listeners.click();
assert.equal(window.prints, 1);
for (const open of [false, true]) {
  getElement("paid-walk-evidence").open = open;
  getElement("base-care-evidence").open = open;
  getElement("financial-protection-evidence").open = !open;
  getElement("cost-walk-low").value = "20";
  window.listeners.beforeprint();
  assert.equal(getElement("monthly-cost").textContent, "$505–$855");
  assert.equal(getElement("paid-walk-evidence").open, true);
  assert.equal(getElement("base-care-evidence").open, true);
  assert.equal(getElement("financial-protection-evidence").open, true);
  window.listeners.beforeprint();
  window.listeners.afterprint();
  assert.equal(getElement("paid-walk-evidence").open, open, "Printing must restore the disclosure state");
  assert.equal(getElement("base-care-evidence").open, open);
  assert.equal(getElement("financial-protection-evidence").open, !open);
}
getElement("cost-walk-low").value = "";
window.listeners.beforeprint();
assert.equal(getElement("monthly-cost").textContent, "Not calculated", "Printing cannot preserve an outdated valid total");
assert.equal(getElement("cost-breakdown").innerHTML, "");
window.listeners.afterprint();
assert.ok(source.includes('@media print') && source.includes('Page version:'));
console.log("Print checks passed: native print, latest inputs, invalid totals and evidence restoration.");
