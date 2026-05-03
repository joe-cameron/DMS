# Expressions — Complete Syntax Reference

## Core Syntax Rules

1. Expressions start with `@{}` in the flow designer or are entered directly in the expression editor.
2. Functions are case-sensitive: `utcNow()` works, `UtcNow()` does not.
3. String literals use single quotes: `'hello'` not `"hello"`.
4. Property access uses `?['name']` for null-safe access, `['name']` for required access.
5. Nested functions read inside-out: `toLower(trim(body('Get')?['name']))` trims first, then lowercases.

---

## String Functions

```
// Concatenation (preferred over string interpolation)
concat('Contract-', variables('contractNumber'), '-', formatDateTime(utcNow(), 'yyyyMMdd'))

// Length
length('hello')  // 5

// Substring (startIndex, length)
substring('WO24162-A1', 0, 7)  // 'WO24162'

// Replace
replace(body('Get')?['phone'], '-', '')  // strip dashes

// Split and Join
split('HVAC,Plumbing,Electrical', ',')  // array
join(variables('tradeArray'), ' | ')     // 'HVAC | Plumbing | Electrical'

// Contains / StartsWith / EndsWith
contains('HVAC Maintenance', 'HVAC')     // true
startsWith(variables('code'), 'WO')      // true
endsWith(variables('file'), '.docx')     // true

// Case
toLower('HELLO')  // 'hello'
toUpper('hello')  // 'HELLO'

// Trim
trim('  hello  ')  // 'hello'

// indexOf (returns -1 if not found)
indexOf('hello world', 'world')  // 6

// Encoding
encodeUriComponent('hello world')  // 'hello%20world'
decodeUriComponent('hello%20world')  // 'hello world'
base64('hello')
base64ToString(variables('encoded'))
```

---

## Date and Time Functions

```
// Current UTC time
utcNow()  // '2026-03-13T14:30:00.0000000Z'

// Format dates
formatDateTime(utcNow(), 'yyyy-MM-dd')              // '2026-03-13'
formatDateTime(utcNow(), 'MMMM d, yyyy')             // 'March 13, 2026'
formatDateTime(utcNow(), 'dddd, MMMM d, yyyy')       // 'Friday, March 13, 2026'
formatDateTime(utcNow(), 'MM/dd/yyyy hh:mm tt')       // '03/13/2026 02:30 PM'

// DCFG MSA_DATE_LONG pattern
// "13th day of March, 2026"
// Build with: concat(dayOfMonth, ordinal, ' day of ', monthName, ', ', year)

// Date arithmetic
addDays(utcNow(), 30)
addDays(utcNow(), -7)         // 7 days ago
addHours(utcNow(), 2)
addMinutes(utcNow(), 45)
addSeconds(utcNow(), 30)

// Date parts
dayOfMonth(utcNow())          // 13
dayOfWeek(utcNow())           // 5 (Friday, 0=Sunday)
dayOfYear(utcNow())           // 72

// Date difference
dateDifference('2026-01-01', '2026-03-13')  // returns duration string
// For numeric days: div(ticks(dateDifference(start, end)), 864000000000)

// Parse date from string
formatDateTime('March 13, 2026', 'yyyy-MM-dd')

// Null-safe date formatting
if(empty(body('Get')?['dcfg_expiration_date']),
   '',
   formatDateTime(body('Get')?['dcfg_expiration_date'], 'MM/dd/yyyy'))

// Convert to ticks for comparison
ticks(utcNow())
ticks('2026-12-31T00:00:00Z')
```

### Ordinal Suffix Helper
For "1st", "2nd", "3rd", "4th" etc:
```
if(or(equals(mod(dayOfMonth(utcNow()), 10), 1),
      and(not(equals(mod(dayOfMonth(utcNow()), 100), 11)))),
   if(equals(mod(dayOfMonth(utcNow()), 10), 1), 'st',
   if(equals(mod(dayOfMonth(utcNow()), 10), 2), 'nd',
   if(equals(mod(dayOfMonth(utcNow()), 10), 3), 'rd', 'th'))),
   'th')
```

---

## Logic and Comparison

```
// Equality (case-sensitive for strings)
equals(variables('status'), 'Active')
equals(int(body('Get')?['dcfg_status']), 100000000)

// Comparison
greater(variables('amount'), 0)
greaterOrEquals(variables('count'), 10)
less(variables('daysLeft'), 90)
lessOrEquals(variables('balance'), 0)

// Boolean operators
and(greater(variables('x'), 0), less(variables('x'), 100))
or(equals(variables('a'), 'Draft'), equals(variables('a'), 'Generated'))
not(empty(triggerBody()?['email']))

// Conditional (if/then/else)
if(equals(variables('isActive'), true), 'Active', 'Inactive')

// Nested conditional
if(greater(variables('days'), 90), 'Current',
   if(greater(variables('days'), 0), 'Expiring Soon', 'Expired'))

// Empty check (works for strings, arrays, objects, null)
empty(variables('myValue'))            // true if null, '', [], or {}
empty(body('List')?['value'])          // true if no results
```

---

## Collection Functions

```
// Array operations
length(body('List_rows')?['value'])        // count of items
first(body('List_rows')?['value'])         // first item
last(body('List_rows')?['value'])          // last item
contains(createArray('a','b','c'), 'b')    // true

// Create array
createArray('HVAC', 'Plumbing', 'Electrical')

// Union / Intersection
union(variables('array1'), variables('array2'))
intersection(variables('array1'), variables('array2'))

// Access by index
body('List_rows')?['value']?[0]?['name']   // first item's name
```

---

## Flow Metadata Functions

```
// Current flow info
workflow()?['name']                         // flow GUID
workflow()?['run']?['name']                 // current run GUID
workflow()?['tags']?['flowDisplayName']      // human-readable name
workflow()?['tags']?['environmentName']      // environment GUID

// Build flow run URL
concat(
  'https://make.powerautomate.com/environments/',
  workflow()?['tags']?['environmentName'],
  '/flows/',
  workflow()?['name'],
  '/runs/',
  workflow()?['run']?['name']
)

// Action results (inside Catch scope)
result('Try_Scope')   // array of all action results in the scope

// Filter to failed actions only
// Use in Filter Array "From": result('Try_Scope')
// Filter condition:
or(equals(item()?['Status'], 'Failed'), equals(item()?['Status'], 'TimedOut'))

// Get specific action error
actions('My_Action_Name')?['error']?['message']
actions('My_Action_Name')?['status']

// Trigger info
triggerOutputs()?['headers']?['x-ms-user-email-encoded']
triggerBody()
```

---

## Type Conversion

```
int('42')              // string → integer
float('3.14')          // string → float
string(42)             // integer → string
string(true)           // boolean → string 'True'
bool('true')           // string → boolean
json('{"a":1}')        // string → object
array(variables('x'))  // wrap single item in array
xml(variables('str'))  // string → XML

// Picklist integer from string
int(body('Get_Contract')?['dcfg_status'])

// Currency: store as decimal, display rounded
// Store: body('Get')?['dcfg_contract_fee'] (exact)
// Display: formatNumber(float(body('Get')?['dcfg_contract_fee']), 'C0')
```

---

## Common Pitfalls

| Pitfall | What Happens | Fix |
|---|---|---|
| `body('X')['prop']` | Null crash if X returns null | `body('X')?['prop']` |
| `formatDateTime(null, 'fmt')` | Runtime error | Wrap in `if(empty(...))` |
| `equals(stringField, 1)` | Always false (type mismatch) | `equals(int(stringField), 1)` |
| `add(variables('x'), 1)` where x is string | Runtime error | `add(int(variables('x')), 1)` |
| `concat(null, 'text')` | Returns null, not 'text' | `concat(coalesce(val,''), 'text')` |
| Comparing dates as strings | Lexicographic, not chronological | Compare with `ticks()` |
