const assert = require("node:assert/strict")
const path = require("node:path")

const clone = require(path.resolve(process.argv[2]))
const stock = require(path.resolve(process.argv[3]))

const normalize = source => source.replace(/\s+/g, " ").trim()

for (const name of ["eventKeyboardName", "isTypedKeyboard", "layoutBriefs", "selectKeyboard", "shortLabel"]) {
	assert.equal(normalize(clone[name].toString()), normalize(stock[name].toString()), `${name} drifted from stock`)
}
assert.equal(clone.shortLabel("Esperanto", { Esperanto: "eo" }), stock.shortLabel("Esperanto", { Esperanto: "eo" }))
