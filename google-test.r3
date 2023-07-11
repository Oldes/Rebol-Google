Rebol [
	Title:  "Google API test"
	Date:   11-Jul-2023
	Author: @Oldes
	File:   %google-test.r3
]

;system/options/quiet: false
google: import %google.reb

;google/drop-token ;; without token, user will be forced to authenticate again

;probe google/people/profile
data: google/people/contacts
foreach person data/connections [
	if person/emailAddresses [
		print [
			as-green person/names/1/displayName
			person/emailAddresses/1/value
		]
	]
]
;probe google/people/other-contacts
