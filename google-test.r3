Rebol [
	Title:  "Google API test"
	Date:   11-Jul-2023
	Author: @Oldes
	File:   %google-test.r3
]

system/options/quiet: false
system/options/log/http: 0



google: import %google.reb
;google/drop-token ;; without token, user will be forced to authenticate again


do-test: func[title code [block!]][
	print-horizontal-line
	print as-yellow title
	probe code
	try/with code :print
]

;--------------------------------------------------------------------------------
;-- Testing Google People API                                                    
;--------------------------------------------------------------------------------
people: :google/people ;; shortcut to People API context

;google/add-scope @contacts

do-test "User's profile" [
	probe people/profile
]
quit
do-test "Create a new contact" [
	probe person: people/create #(
		names: [#(
			familyName: "Example"
			givenName:  "Test"
		)]
		emailAddresses: [
			#(value: "test@example.com")
			#(value: "another-test@example.com")
		]
	)
]

if person [
	;; if the contact was created, we already have the info,
	;; but we can also get it using the resourceName
	do-test "The new contact info" [
		probe people/contact person/resourceName
	]
	do-test "Delete the new test contact" [
		probe people/delete person/resourceName
	]
	do-test "Delete the deleted contact (should report an error now)" [
		probe people/delete person/resourceName
	]
]

do-test "Display some contacts info (limit the result to max 10 contacts)" [
	foreach person people/contacts/part/with 10 "names,emailAddresses,phoneNumbers" [
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
]

print [LF LF LF]
;--------------------------------------------------------------------------------
;-- Testing Google GMail API                                                     
;--------------------------------------------------------------------------------
gmail: :google/gmail ;; shortcut to GMail API
;google/add-scope @gmail.readonly

do-test "User's GMail profile" [
	probe gmail[profile]
]
do-test "User's first page of message ids" [
	probe data: first gmail[messages]
]

if all [block? data/messages not empty? data/messages][
	do-test "User's first message content" [
		probe gmail compose [message (data/messages/1/id)]
	]
]

print [LF LF LF]
;--------------------------------------------------------------------------------
;-- Testing Google Photos API                                                    
;--------------------------------------------------------------------------------
photos: :google/photos ;; shortcut to Google Photos API
;google/add-scope @photoslibrary.readonly 

do-test "User's Google Photos albums" [
	probe albums: photos/albums
]

if all [albums not empty? albums] [
	do-test "Get first item from the album" [
		probe photos/items/part albums/1/id 1
	]
]
