# Kusina Cooking Context

The language of a kitchen that tracks its own stock, decides what it can cook, and guides a cook through a recipe. This is a glossary only; the rules live in [docs/06 section 3](docs/06-flutter-product-scope.md) for the MVP, with [docs/02-domain-model.md](docs/02-domain-model.md) retained as the MySQL/React contingency record.

## Language

### People and places

**Kitchen profile**:
The name, equipment, and stock of the single on-device kitchen; no account, no sign-in.
_Avoid_: User, account, customer

**Kitchen**:
The set of stock, equipment, and cooking activity tracked for one cooking location. In the MVP, one device holds exactly one kitchen.
_Avoid_: Household

### Stock and catalog

**Ingredient**:
A food or seasoning item that can be stocked and required by a recipe. Ingredients come from a shared catalog in v1.
_Avoid_: Item, product

**Canonical unit** (deferred tier):
The one unit in which a kitchen would store stock for a given ingredient. Not used for comparison in the MVP; display vocabulary only.
_Avoid_: Base unit, default unit

**Stock status**:
The presence state of one ingredient in a kitchen: `unknown`, `have`, `low`, or `out`. Replaces the measured stock level.
_Avoid_: Stock level, quantity, amount

**Stock**:
The set of stock statuses for one kitchen.
_Avoid_: Inventory, pantry

**Stock event**:
An append-only record of one ingredient’s stock status changing in one kitchen, with a reason and a timestamp. The full set of stock events is the kitchen’s stock history.
_Avoid_: Inventory transaction, movement, ledger entry

**Equipment**:
A major cooking appliance whose presence changes which recipes can be cooked. Basic hand tools are not equipment in this domain.
_Avoid_: Utensil, tool, kitchenware

### Recipes and cooking

**Recipe**:
A defined set of instructions with a base serving yield, required equipment, required and optional ingredients, and ordered guided steps. The prepared food is a dish; the recipe is the plan for making it.

**Base yield** (replaces Serving yield):
The serve count a recipe’s instructions are written for; display-only in the MVP, with no scaling.
_Avoid_: Portion, batch, serving selector

**Required ingredient**:
An ingredient that counts toward availability: `out` is treated as missing (advisory, Guide anyway still allowed) and `unknown` as a prompt to confirm.
_Avoid_: Main ingredient

**Optional ingredient**:
An ingredient that can improve a recipe but does not block availability.
_Avoid_: Extra, garnish (a garnish is one kind of optional ingredient)

**Availability**:
Whether a recipe can be cooked now: `ready`, `needs_confirmation`, or `blocked`, computed for display. `out` blocks, `unknown` prompts, `have`/`low` are available; when a recipe ships more than one method, availability is computed for the method the cook picked.
_Avoid_: Cookability, match

**Missing requirement**:
A required equipment item not owned for the cook’s chosen method, or a required ingredient whose status is `out`. `unknown` is a prompt, not missing.
_Avoid_: Blocker, gap

**Guide anyway**:
The explicit start mode for a `blocked` recipe: it names the missing requirements and records `started_without_availability`. Availability is advice, never a gate.
_Avoid_: Force start, override

**Stock event reasons**:
`initial`, `restock`, `used_some`, `used_up`, `waste`, `correction`. `used_some` and `used_up` are the only reasons that may link to a cooking session; `Used it` / `Used it up` are the user-facing labels for the last two.
_Avoid_: consume, adjustment, deduction

**Cooking session**:
One tracked attempt to cook one recipe in one kitchen, from start to completion or abandonment.
_Avoid_: Cook, run, attempt

**Guided step**:
One ordered instruction in a recipe that the cook advances manually. A step may carry an optional countdown timer.
_Avoid_: Task, instruction (the instruction is the text inside a step)

**Usage**:
The cook’s report of what a dish used, expressed as a status transition (internal reasons `used_some` / `used_up`; labels **Used it** / **Used it up**), not an amount. Usage is confirmed at the end of a session; it is not assumed at the start.
_Avoid_: Consumption, deduction

**Usage review**:
The end-of-session screen where the cook marks each ingredient **Didn’t use** / **Used it** / **Used it up** before the stock statuses change.
_Avoid_: Consumption review, checkout, confirmation page

**Active session**:
A cooking session that is still in progress. In the MVP, a kitchen may have at most one active session.
_Avoid_: Open session, current cook
