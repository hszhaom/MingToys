const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "..");
const source = fs.readFileSync(path.join(root, "pages", "dog-cost-calculator.html"), "utf8");
const scripts = [...source.matchAll(/<script>([\s\S]*?)<\/script>/g)].map((match) => match[1]);
let calculator = scripts.find((script) => script.includes("var sizeMonthly"));

if (!calculator) {
  throw new Error("Cost calculator script was not found.");
}

calculator = calculator.replace(/{% for breed in site\.data\.breeds %}[\s\S]*?{% endfor %}/, "");

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
