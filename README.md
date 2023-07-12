[![Rebol-Google CI](https://github.com/Oldes/Rebol-Google/actions/workflows/main.yml/badge.svg)](https://github.com/Oldes/Rebol-Google/actions/workflows/main.yml)

# Rebol/Google

A Google API module for [Rebol3](https://github.com/Oldes/Rebol3).

## Usage:

```rebol
google: import %google.reb
data: google/people/contacts
foreach person data/connections [
	if person/emailAddresses [
		print [
			as-green person/names/1/displayName
			person/emailAddresses/1/value
		]
	]
]
```
