Rebol [
	Title:  "Google API test"
	Date:   10-Apr-2025
	Author: @Oldes
	File:   %google-test.r3
	Needs:  3.16.0
	Note: {
		When running this test in CI, a valid token is expected.
		Since authentication requires user input, the test may fail if the user is not authenticated.
	}
]

system/options/quiet: false  ;; allow traces
system/options/log/http: 0   ;; turn off all HTTP traces 

unless system/user/name [
	sys/log/info 'REBOL {Using "google-test" as the user!}
	su/p google-test ""
]

google: import %google.reb

try [system/schemes/httpd/set-verbose 1]

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
	;google/add-scope @userinfo.profile  ;; See your personal info, including any personal info you've made publicly available
	probe people/profile
]

do-test "Create a new contact" [
	probe person: people/create #[
		names: [#[
			familyName: "Example"
			givenName:  "Test"
		]]
		emailAddresses: [
			#[value: "test@example.com"]
			#[value: "another-test@example.com"]
		]
	]
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
do-test "User's message ids newer than 1 day" [
	probe data: first gmail[messages "newer_than:1d"]
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
