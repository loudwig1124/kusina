# Product Scope

**Project:** Kusina (working title) — kitchen inventory and guided cooking  
**Status:** Design phase. The application is not built yet.  
**Platform:** Responsive web app (mobile-first), React front end, MySQL database.

## 1. The problem

Home cooks repeatedly ask three practical questions:

1. What food do I already have, and how much of it?
2. What can I cook right now with the equipment and ingredients in my kitchen?
3. How do I follow a recipe without losing my place, forgetting a timer, or losing track of what I used?

Paper notes, chat messages, and memory make this hard. Recipes found online also ignore what a specific kitchen actually owns, so they suggest dishes that require an oven the user does not have.

## 2. Target user

**Primary persona:** a Filipino student or home cook who manages one household kitchen and cooks local dishes regularly. They use a phone while cooking and want to check stock while away from home. They know basic cooking, but want guidance on order and timing.

**Secondary users (future):** household members who share the same kitchen, and users who track more than one kitchen. These are intentionally outside the MVP.

## 3. Product principles

- **Local first.** Start with a small, reviewed set of Filipino dishes rather than a huge international catalog.
- **Honest availability.** A recipe appears as cookable only when the kitchen has the required equipment and enough required ingredients.
- **Small database, real relationships.** Every shortcut that would weaken stock accuracy is avoided; every speculative feature is deferred.
- **Phone in one hand.** The guided-cooking flow is designed for a cook who can only tap “next.”
- **No silent stock changes.** Stock is deducted only after the cook confirms actual consumption.
- **One kitchen first.** Multi-kitchen and sharing are designed for but not built.

## 4. MVP scope and user stories

| ID | User story | Acceptance summary |
|---|---|---|
| US-01 | As a new user, I can register and get one kitchen automatically. | Account and kitchen are created together; my kitchen is private to me. |
| US-02 | As a cook, I can select the major appliances my kitchen has. | Selection is limited to the fixed equipment list; I can update it later. |
| US-03 | As a cook, I can add or correct stock for an ingredient. | Quantity is entered in a compatible unit, stored in the canonical unit, and recorded in stock history. |
| US-04 | As a cook, I can see my current stock and how it changed over time. | Each change shows amount, reason, and time; the balance never goes below zero. |
| US-05 | As a cook, I can see recipes I can cook with what I have. | Results respect both equipment and required ingredients at the chosen servings. |
| US-06 | As a cook, I can understand why a recipe is not available. | The recipe detail lists missing equipment and short ingredients. |
| US-07 | As a cook, I can start a guided cooking session. | The recipe starts at step 1; only an available recipe can start. |
| US-08 | As a cook, I can run step timers without leaving the guide. | Steps with a duration show a countdown; the timer does not advance the step automatically. |
| US-09 | As a cook, I can put the phone down and resume later. | The session returns to the current step without changing stock. |
| US-10 | As a cook, I can review and confirm what I actually used. | Editable amounts are prefilled from the recipe; confirming deducts stock and records history. |
| US-11 | As a cook, I can abandon a session. | The session is marked abandoned and no stock changes. |
| US-12 | As a cook, I can review past sessions and stock movements. | Completed sessions and their consumption are visible in history. |

### MVP functional scope

1. **Account and kitchen**
   - Email + password registration, login, and logout.
   - Exactly one kitchen per user, created automatically.
   - Kitchen name and selected equipment are editable.
2. **Inventory**
   - Shared ingredient catalog with search and categories.
   - Stock in, quantity correction, quick consumption outside a guided cook, and history.
   - Quantities stored in canonical units; user input converted only within compatible units.
3. **Recipes**
   - Twelve seeded Filipino recipes with base servings, required equipment, required/optional ingredients, ordered steps, and step timers.
   - “Cook now” list and a full recipe list showing availability and missing requirements.
   - Serving-size selection with linear scaling.
4. **Guided cooking**
   - Start, step forward, timer, resume, abandon, and completion.
   - Completion review with editable actual amounts and atomic stock deduction.
5. **History**
   - Completed/abandoned cooking sessions.
   - Stock transaction history per kitchen and ingredient.

## 5. Out of scope

Deferred and **not built** in the MVP:

- Multiple kitchens per user, inviting other users, kitchen sharing, roles, and permissions.
- Ingredient substitutions, “almost cookable” recommendations beyond a missing-requirement list, meal planning, and shopping lists.
- User-created ingredients or recipes, recipe editing, ratings, comments, and photos.
- Expiry dates, batches, barcode scanning, nutrition facts, and allergen filtering.
- Native mobile apps, offline mode, push notifications, and background timers.
- Admin/moderation tools, email verification, password reset, social features, and analytics.
- Deployment beyond a local/class demo.

The database design documents how multi-kitchen and sharing would be added later, but no tables for them are created in v1.

## 6. Screens

| Screen | Purpose |
|---|---|
| Sign in / Register | Authenticate and start onboarding. |
| Kitchen setup | Name the kitchen and select major appliances. |
| Cook now (home) | Available recipes, active-session resume, quick links to stock and full catalog. |
| Inventory | Search stock, add/correct/consume quantities, open history. |
| All recipes | Browse every recipe with availability badges and filter by availability. |
| Recipe detail | Requirements, missing items, serving selector, and start button. |
| Guided cook | Current step, progress, timer, and abandon control. |
| Consumption review | Editable actual ingredient amounts and confirm action. |
| History | Past sessions and stock transactions. |
| Kitchen settings | Kitchen name and equipment changes. |

## 7. Core product flows

1. **Onboarding:** register → kitchen created → choose equipment → add first stock items → see available recipes.
2. **Stock management:** pick an ingredient → enter quantity and unit → balance and history update together.
3. **Recipe discovery:** open Cook now → equipment filter → required-ingredient sufficiency check at chosen servings → available list; full list explains missing requirements.
4. **Guided cooking:** start available recipe → follow ordered steps → use timers → resume if interrupted → review actual amounts → confirm → stock and session history update.
5. **Abandon:** leave the guide → session marked abandoned → stock untouched.

## 8. Demo scenario

Maria registers and sets up a kitchen with a **stovetop** and an **air fryer** only. She stocks chicken thighs, pork belly, rice, garlic, onion, soy sauce, vinegar, bay leaves, cooking oil, salt, pepper, eggs, and eggplant.

- **Cook now** shows Chicken Adobo, Sinangag, Tortang Talong, and Air-Fried Crispy Pork Belly.
- **Baked Macaroni** is hidden from Cook now because Maria has no oven; **Chicken Inasal** because she has no grill; **Bulalo** because she has no pressure cooker.
- Maria opens Chicken Adobo, keeps the default 4 servings, and follows six guided steps. She uses the simmer timer, locks her phone, and resumes at the same step.
- At the end, she confirms the actual amounts. Chicken, soy sauce, vinegar, garlic, and bay leaves decrease in stock. The session and each consumption appear in history.
- She starts another recipe, abandons it, and verifies that stock did not change.

This scenario is the primary class demonstration.

## 9. MVP success criteria

- A new user can register, set equipment, stock at least five ingredients, and reach the Cook now screen without administrator help.
- Equipment filtering is correct: a missing oven, grill, or pressure cooker hides the recipes that require it.
- Availability is exact at the boundary: sufficient stock shows the recipe; 0.001 below the scaled requirement does not.
- Optional ingredients never hide an otherwise cookable recipe.
- Confirming a cooking session reduces each selected stock balance and creates matching consumption history in one operation; a failure leaves both unchanged.
- Abandoning a session changes no stock.
- Reloading during a session returns to the same step.
- No operation can make a stock balance negative.
- Every user can access only their own kitchen and sessions.
- All five equipment types are used by at least one of the twelve seeded recipes.

## 10. Constraints and assumptions

- The course requires React and a SQL database; MySQL 8.0.16+ is the target. The API is planned as Node.js + Express.
- The catalog is shared and closed in v1; users cannot add arbitrary ingredients.
- One kitchen per user is enforced for now; multi-kitchen/sharing has a documented migration path.
- Recipes are seed data and are treated as immutable during a session. There is no recipe editor.
- The 12-recipe seed is authored in Phase 2; this package contains the plan and one fully specified recipe.
- Timers are client-side aids. Closing the app stops the timer, and the step remains where the user left it.
- A local Filipino ingredient catalog is used rather than importing an external nutrition or recipe database.
