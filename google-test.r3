Rebol [
	Title:  "Google API test"
	Date:   11-Jul-2023
	Author: @Oldes
	File:   %google-test.r3
]

system/options/quiet: false
google: import %google.reb

;google/drop-token ;; without token, user will be forced to authenticate again

;probe google/people/profile
data: google/people/contacts
foreach person data/connections [
	prin as-green person/names/1/displayName
	if person/emailAddresses [
		prin SP	prin person/emailAddresses/1/value
	]
	if person/phoneNumbers [
		prin SP	prin person/phoneNumbers/1/value
	]
	prin LF
]
;probe google/people/other-contacts
