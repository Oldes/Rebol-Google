[![rebol-google](https://github.com/user-attachments/assets/5710b178-0860-463f-8b8e-1693dffddc06)](https://github.com/Oldes/Rebol-Google)

[![Rebol-Google CI](https://github.com/Oldes/Rebol-Google/actions/workflows/main.yml/badge.svg)](https://github.com/Oldes/Rebol-Google/actions/workflows/main.yml)
[![Gitter](https://badges.gitter.im/rebol3/community.svg)](https://app.gitter.im/#/room/#Rebol3:gitter.im)
[![Zulip](https://img.shields.io/badge/zulip-join_chat-brightgreen.svg)](https://rebol.zulipchat.com/)

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
