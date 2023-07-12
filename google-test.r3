Rebol [
	Title:  "Google API test"
	Date:   11-Jul-2023
	Author: @Oldes
	File:   %google-test.r3
]

;system/options/quiet: false
google: import %google.reb

;google/drop-token ;; without token, user will be forced to authenticate again


print as-yellow "User's contacts:"
try/with [
	get-all-contacts: function[
		"Resolve all connections and their name/email/phone fields"
	][
		url: https://people.googleapis.com/v1/people/me/connections?personFields=names,emailAddresses,phoneNumbers
		nextPageToken: none
		result: clear []
		until [
			data: google/api-get rejoin [url "&pageToken=" any [nextPageToken ""]]
			if any [not data not data/connections][break]
			append result data/connections
			none? nextPageToken: data/nextPageToken
		]
		result
	]

	;; Display all contacts...
	foreach person get-all-contacts [
		;; It looks, that there may be contacts without names,
		;; if so, ignore these...
		unless person/names [continue]
		prin as-green person/names/1/displayName
		;; Each contact may have multiple emails and phone numbers,
		;; but for now, display just one, if any.
		if person/emailAddresses [ prin SP	prin person/emailAddresses/1/value ]
		if person/phoneNumbers   [ prin SP	prin person/phoneNumbers/1/value   ]
		prin LF
	]

	;probe google/people/other-contacts
] :print

print-horizontal-line

;google/add-scope @gmail.readonly

print as-yellow "User's GMail profile:"
try/with [
	probe google/gmail [profile]
] :print

print as-yellow "User's first page of message ids"
try/with [
	probe data: first google/gmail [messages]
] :print

print as-yellow "User's first message content"
try/with [
	probe google/gmail compose [message (data/messages/1/id)]
] :print

