# Improvement Plan

Decisions from working through the layered-legal-rails challenge feedback
(`/Users/technician/Development/layered-legal-rails/CHALLENGE_NOTES.md` and
`CHALLENGE_RESULTS.md`). Pre-launch, so no backwards-compat constraints.

Items parked for layered-ui (not in this gem's scope):

- Skill/docs examples for hand-rolled forms with `l-ui-form__group` etc.
- `l_ui_form_group(form, :body, as: :text)` companion helper.
- Section-header / collapsible nav group helper.

---

## 1. View context for `render:` procs

**Problem:** Class-level `render:` procs have no view context, so emitting
HTML requires `ActionController::Base.helpers` workarounds.

**Decision:** Arity-tolerant dispatch.

```ruby
def call_column_renderer(proc, record)
  proc.arity == 1 ? proc.call(record) : proc.call(record, view_context)
end
```

Two-arity procs opt into receiving `view_context`. Update both call sites
(`show.html.erb:42` and the index row partial).

Position `render:` procs as the **escape hatch** — most consumers reach for
the partial-based `as:` types from #7 first.

---

## 2. Member / collection actions

**Problem:** Custom verbs ("approve_payment", "publish") today require a
hand-written route plus an ejected controller — two separate definitions for
the same resource.

**Decision:** Block form on `layered_resources`, mirroring Rails' `resources`.
Ejection remains the path for the action body itself.

```ruby
layered_resources :questions, controller: "questions" do
  member do
    post :approve_payment
  end
  collection do
    post :bulk_archive
  end
end
```

- Custom routes get `_layered_resource_route_key` baked in so
  `load_layered_resource` still runs.
- Raise early if a block declares actions without a `controller:` override —
  the default controller can't satisfy them.
- Extend `Routing.register` to track member/collection action names (cheap;
  opens the door to UI helpers later without forcing them now).

**Companion generator:**

```
rails g layered:resource:controller questions
```

Generates `app/controllers/questions_controller.rb` as a
`Layered::Resource::ResourcesController` subclass with comments showing
where to add member actions and how to use `@record` / `@resource` /
`layered_routes`. Pairs with the existing `layered:resource:views`
generator — frames ejection as the paved path for non-CRUD.

---

## 3. Virtual attributes / nested params

**Surprise finding:** Most of what was reported as missing already works.
`permitted_params` is `fields.map(&:attribute)`, so a `fee_dollars=` virtual
setter is already permitted as long as it's listed in `fields`. The form
view delegates to `l_ui_form` which uses `as:` directly — no
`column_for_attribute` introspection.

**Real gap:** `permitted_params` only produces scalar permit keys. Can't
express `documents: []`, `address_attributes: [:street, :city]`, etc.

**Decision:** Add `permit:` override on field entries.

```ruby
fields [
  { attribute: :title },
  { attribute: :documents, as: :file, permit: [] },             # → documents: []
  { attribute: :address_attributes, permit: [:street, :city] }
]
```

`permitted_params` becomes a hash builder instead of a flat array.

**Skip:** `param:` rename (form posts X, model accepts Y). The virtual-setter
pattern already covers this.

**Docs:** Explicit note + one-line example confirming virtual attributes are
supported.

---

## 4. Show view

**Problem:** Default show iterates `@columns` indiscriminately. Two issues:
(a) badges designed for table cells leak as paragraph blocks;
(b) `columns` has no per-user gating, so anything declared for the index
renders in full on show — quiet exposure footgun.

**Decision:** Strip the column iteration from the default show view.
Default show becomes: breadcrumbs, primary column as heading, edit/delete
buttons. Anything else → eject via `rails g layered:resource:views`.

- Don't add `show_fields`. Show is the natural ejection point.
- Pair docs with the eject-generator story from #2 and #7.

---

## 5. Authorisation

**Problem:** `scope(controller)` is the only seam; per-action gating
("can this user edit this record?") and UI button visibility are reinvented
per app.

**Decisions:**

1. **Rename `@can_*` → `@resource_can_*`.** These are *route-exposure*
   flags, not authority flags. Renaming disclaims authz semantics.

2. **Stay out of authorisation generally.** `scope(controller)` remains the
   universal seam. Inside it, consumers compose Pundit / CanCan / POROs as
   they like. Per-action gating on records the user can see but can't
   mutate → eject the controller and add `before_action`.

3. **First-class Pundit support via opt-in `use_pundit`.**

   ```ruby
   class QuestionResource < Layered::Resource::Base
     use_pundit
   end
   ```

   When enabled:
   - `scope(controller)` defaults to
     `Pundit.policy_scope(controller.current_user, model)`.
   - `load_layered_resource` calls `controller.authorize(@record, "#{action}?")`
     for member actions.
   - `@resource_can_show/_edit/_destroy` are ANDed with
     `policy(record).show?/edit?/destroy?` so action buttons auto-hide.

   Why opt-in, not auto-detect: silently changing behaviour when Pundit is
   present elsewhere in the host app would be surprising and hard to debug.

   Why Pundit specifically: per-action `policy.edit?` maps cleanly onto
   flag derivation. CanCan's `current_ability.can?` would need different
   shape. Ship one, do it well; CanCan / POROs still work via `scope`.

4. **Drop the bespoke `authorize?` hook.** Half-baked authz framework
   competing with Pundit/CanCan; `scope` + `use_pundit` cover the cases.

---

## 6. Ownership shorthand

**Decision:** Ship `owned_by` as a purely behavioural shortcut.

```ruby
class QuoteResource < Layered::Resource::Base
  owned_by :user                          # default via: :current_user
  # or:
  owned_by :account, via: :current_account
end
```

What it does:
1. `scope(c) = model.where(column => c.public_send(via))`.
2. `build_record(c) = scope(c).build` (owner assigned via the `where`).
3. Defaults to `model.none` when `c.public_send(via)` is nil — defuses the
   unauthenticated footgun for the most common case.

**Composition with `use_pundit`:** Pundit wins for `scope` (read filter
comes from `Policy::Scope#resolve`). `owned_by` still handles owner
assignment on create. Document this explicitly.

**Position in docs:** ownership as a fact about the data, not a gate on what
users can do. Use `use_pundit` / Pundit policies for the gate.

---

## 7. Column-type partials

**Decision:** `as:` dispatches to partials at conventional paths.

```ruby
columns [
  { attribute: :status, as: :badge,
    variants: { open: :warning, answered: :success } },
  { attribute: :created_at, as: :datetime },
  { attribute: :verified, as: :boolean }
]
```

**Built-ins shipped:**
- `:text` — default (current behaviour).
- `:datetime` — strftime formatting.
- `:badge` — wraps in `l-ui-badge l-ui-badge--{variant}`. `variants:` maps
  values to variant names; default `:default`.
- `:boolean` — ✓/✗ or `true_label:` / `false_label:`.

**Lookup order (most specific wins):**
1. `app/views/layered/<resource>/columns/_<type>.html.erb` — per-resource.
2. `app/views/layered/resource/columns/_<type>.html.erb` — host-wide.
3. Gem default.

Custom `as:` types are just partials at these paths. No new abstraction.

**Locals contract:** `(record, value, options)`.

**Eject generator:**

```
rails g layered:resource:column badge              # eject built-in to host-wide path
rails g layered:resource:column badge questions    # eject scoped to QuestionResource
rails g layered:resource:column priority_badge     # scaffold custom type
```

**Note:** `:badge` variants tie us to layered-ui class names — acceptable
since the gems are designed to ship together, but skill docs need to list
available variants so consumers don't guess.

---

## 8. Documentation & skill updates

Mostly absorbed by other items. What's left:

**README:**
- Section on the `scope(controller)` seam: `current_user` convention,
  Pundit/CanCan/PORO composition, `Model.none` footgun for hand-rolled
  scopes (defused for `owned_by`).
- Section on `build_record(controller)` with the owner-assignment pattern.
- "When to eject" page pairing the three generators:
  `layered:resource:controller` (custom verbs),
  `layered:resource:views` (custom presentation),
  `layered:resource:column` (custom column rendering).
- Note that show is intentionally minimal.

**Skill (layered-resource-rails):**
- `use_pundit` opt-in + minimal Pundit example.
- `owned_by` shorthand.
- `as:` column types + three-level partial lookup.
- New generators (`controller`, `column`).
- Renamed `@resource_can_*` flags so agents stop suggesting `@can_edit`.

---

## 9. Custom-action generator — DROPPED

Subsumed by #2: block form on `layered_resources` declares the route,
`layered:resource:controller` scaffolds the ejected controller. Composing
those two is trivial. Revisit if real demand for a meta-generator shows up.

---

## 10. Turbo / Stimulus recipes

**Decision:** Extract the index row into a partial (`_record.html.erb`) with
`id: dom_id(record)` on the wrapper. Document the turbo-stream pattern for
member actions; ship no Stimulus controllers.

```ruby
# in an ejected QuestionsController#approve_payment
def approve_payment
  @question.update!(status: :answered)
  respond_to do |format|
    format.turbo_stream do
      render turbo_stream: turbo_stream.replace(
        dom_id(@question),
        partial: "layered/resource/resources/record",
        locals: { record: @question, columns: @columns }
      )
    end
    format.html { redirect_to layered_routes.question_path(@question), notice: "Approved" }
  end
end
```

- One tiny refactor unlocks the entire turbo-stream-update story.
- Stimulus opinions belong in layered-ui, not here.

---

## Implementation phases

### Phase 1 — Foundations & renames

Small mechanical changes that touch everything. Land first so later phases
build on stable names and view shape, and so external skill/doc snippets
only need re-revising once.

1. **Renames + view-context arity (#1, #5 partial):** `@can_*` →
   `@resource_can_*`, two-arity render procs.
2. **Show view minimisation (#4):** strip column iteration, update default.
3. **Index row partial extraction (#10):** unlocks turbo recipes.

### Phase 2 — Rendering & ejection surface

Additive expansion of the consumer-facing API. Each item is self-contained
and shippable on its own.

4. **`as:` partials + column generator (#7):** built-ins + three-level
   lookup + eject generator.
5. **Member/collection block form + controller generator (#2).**
6. **`permit:` on fields (#3).**

### Phase 3 — Auth, ownership & docs

The most opinionated work. Phases 1 and 2 should be settled so the docs
sweep describes the final shape in one pass.

7. **`owned_by` (#6) and `use_pundit` (#5 main).**
8. **Docs + skill update sweep (#8).** Last so it covers everything.
