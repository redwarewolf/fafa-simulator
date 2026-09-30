class_name MoneyFormat

## Formats an integer amount with thousands separators, e.g. 1234567 -> "1,234,567"
## and -1620 -> "-1,620".
static func format(amount: int) -> String:
	var s := str(absi(amount))
	var result := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = s[i] + result
		count += 1
	return ("-" + result) if amount < 0 else result

## "$1,234" / "-$1,234" — a signed dollar amount, e.g. a budget in the red.
static func dollars(amount: int) -> String:
	return ("-$" if amount < 0 else "$") + format(absi(amount))
