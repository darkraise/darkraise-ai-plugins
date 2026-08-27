# Forms

## Two different modules

This trips people up, so get it straight first:

| Module | Holds |
| --- | --- |
| `darkraise-ui/forms` | **Field primitives** — complete, labelled, validated controls |
| `darkraise-ui/components/field` | **Field building blocks** — `Field`, `FieldGroup`, `FieldLabel`, `FieldDescription`, `FieldError`, `FieldSet`, `FieldLegend`, `FieldContent`, `FieldTitle`, `FieldSeparator` |

Reach for the primitives first. The building blocks are for the case a primitive
does not cover.

## Use the field primitives

Seven primitives, each already wrapping `Field` with correct label, description,
error, and ARIA wiring.

| Primitive | Value type |
| --- | --- |
| `TextField` | `string` |
| `TextareaField` | `string` |
| `NumberField` | `number \| undefined` |
| `SelectField` | `string` |
| `CheckboxField` | `boolean` |
| `SwitchField` | `boolean` |
| `RadioGroupField` | `string` |

All seven share `FieldPrimitiveProps<T>`:

```ts
{
  name: string
  value: T
  onChange: (value: T) => void
  onBlur?: () => void
  isInvalid?: boolean
  errors?: Array<{ message?: string } | undefined>
  disabled?: boolean
  readOnly?: boolean
}
```

**Incorrect**

```tsx
<div className="space-y-2">
  <Label htmlFor="email">Email</Label>
  <Input id="email" value={email} onChange={(e) => setEmail(e.target.value)} />
  <p className="text-sm text-red-500">{error}</p>
</div>
```

**Correct**

```tsx
import { TextField } from "darkraise-ui/forms"

<TextField
  name="email"
  label="Email"
  value={email}
  onChange={setEmail}
  isInvalid={!!error}
  errors={[{ message: "Enter a valid email address." }]}
/>
```

Note `onChange` takes the **value**, not the event.

## `errors` is an array of objects, not strings

This is the single most common mistake against this API.

**Incorrect**

```tsx
<TextField errors={["Enter a valid email address."]} />
```

**Correct**

```tsx
<TextField errors={[{ message: "Enter a valid email address." }]} />
```

The shape is `Array<{ message?: string } | undefined>`, which is what most schema
validators already emit — so a validator's error array usually passes straight
through without mapping.

## Validation is `isInvalid` + `errors`

Never hand-roll error markup or paint a border red. The primitives already render
the invalid state, wire `aria-invalid`, and associate the message with the control
for screen readers.

**Incorrect**

```tsx
<Input className={hasError ? "border-red-500" : ""} />
{hasError && <span className="text-red-500">Required</span>}
```

**Correct**

```tsx
<TextField
  name="title"
  label="Title"
  value={title}
  onChange={setTitle}
  isInvalid={hasError}
  errors={[{ message: "Required" }]}
/>
```

## `SelectField` takes options, not children

**Incorrect**

```tsx
<SelectField name="plan" label="Plan" value={plan} onChange={setPlan}>
  <option value="free">Free</option>
</SelectField>
```

**Correct**

```tsx
<SelectField
  name="plan"
  label="Plan"
  value={plan}
  onChange={setPlan}
  placeholder="Choose a plan"
  options={[
    { label: "Free", value: "free" },
    { label: "Pro", value: "pro" },
  ]}
/>
```

`RadioGroupField` takes the same `options` shape.

## Grouping and actions

`FormSection` titles a group of related fields. `FormActions` renders the
submit/cancel pair and owns its pending state — do not build your own.

**Incorrect**

```tsx
<div className="flex justify-end gap-2">
  <Button variant="ghost" onClick={onCancel}>Cancel</Button>
  <Button disabled={isSubmitting}>{isSubmitting ? "Saving…" : "Save"}</Button>
</div>
```

**Correct**

```tsx
<FormSection title="Notifications" description="How we reach you.">
  <SwitchField name="email" label="Email" value={byEmail} onChange={setByEmail} />
  <SwitchField name="sms" label="SMS" value={bySms} onChange={setBySms} />
</FormSection>

<FormActions
  submitLabel="Save"
  submittingLabel="Saving…"
  cancelLabel="Cancel"
  onCancel={onCancel}
  isSubmitting={isSubmitting}
  canSubmit={isDirty && isValid}
/>
```

## When to drop to the building blocks

Only when no primitive covers the control. Use `FieldWrapper` as the bridge — it
keeps label, description, error, and ARIA wiring correct around whatever you
render.

`FieldWrapper`'s `children` is a **render function**, not a node:

```tsx
children: (isInvalid: boolean, ariaDescribedBy: string | undefined) => ReactNode
```

**Correct**

```tsx
import { FieldWrapper } from "darkraise-ui/forms"
import { ColorPicker } from "darkraise-ui/components/color-picker"

<FieldWrapper
  name="brandColor"
  label="Brand color"
  description="Used across the dashboard."
  isInvalid={!!error}
  errors={[{ message: "Pick a color." }]}
>
  {(isInvalid, ariaDescribedBy) => (
    <ColorPicker
      value={color}
      onValueChange={setColor}
      aria-invalid={isInvalid}
      aria-describedby={ariaDescribedBy}
    />
  )}
</FieldWrapper>
```

Read `color-picker.d.ts` before using it — the prop names above are illustrative
of the pattern, not a substitute for reading the type.

## Import from the right module

**Incorrect**

```tsx
import { TextField } from "darkraise-ui/components/field"   // not there
```

**Correct**

```tsx
import { TextField, FieldWrapper, FormSection, FormActions } from "darkraise-ui/forms"
import { Field, FieldGroup, FieldLabel } from "darkraise-ui/components/field"
```
