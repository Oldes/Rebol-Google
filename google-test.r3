Rebol [
	Title:  "Google API test"
	Date:   10-Apr-2025
	Author: @Oldes
	File:   %google-test.r3
	Needs:  3.16.0
	Note: {
		When running this test in CI, a valid token is expected.
		Since authentication requires user input, the test may fail if the user is not authenticated.

		For the GitHub action I store content of the test user in the secret, which I collect using:
		write clipboard:// enbase read ~/.google-test.safe 64

		There is used simple user.reb file which looks like:
		```
		Rebol []
		write ~/.google-test.safe debase (get-env "REBOL_SAFE_FILE") 64
		su/p google-test ""
		```
	}
]

system/options/quiet: false  ;; allow traces
system/options/log/http: 0   ;; turn off all HTTP traces 

if all [
	"true" = get-env "CI"
	none? user's google-api
][
	sys/log/error 'REBOL "Invalid user setup in the CI test configuration!"
	quit
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
;google/add-scope @userinfo.profile ;<-- required for people/profile!
if google/has-scope? @userinfo.profile [
	;; See your personal info, including any personal info you've made publicly available
	do-test "User's profile" [
		probe people/profile
	]
]
if google/has-scope? @contacts [
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
]

print [LF LF LF]
;--------------------------------------------------------------------------------
;-- Testing Google GMail API                                                     
;--------------------------------------------------------------------------------
gmail: :google/gmail ;; shortcut to GMail API
;google/add-scope @gmail.readonly

if any [
	google/has-scope? @gmail.readonly
	google/has-scope? @gmail
][
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
]

print [LF LF LF]
;--------------------------------------------------------------------------------
;-- Testing Google Photos API                                                    
;--------------------------------------------------------------------------------
photos: :google/photos ;; shortcut to Google Photos API
;google/add-scope @photoslibrary.readonly 

if any [
	google/has-scope? @photoslibrary.readonly
	google/has-scope? @photoslibrary
][
	do-test "User's Google Photos albums" [
		probe albums: photos/albums
	]

	if all [albums not empty? albums] [
		do-test "Get first item from the album" [
			probe photos/items/part albums/1/id 1
		]
	]
]


print [LF LF LF]
;--------------------------------------------------------------------------------
;-- Testing Google Drives API                                                    
;--------------------------------------------------------------------------------
drive: :google/drive ;; shortcut to Google Drive API
;google/add-scope @drive.readonly 

if any [
	google/has-scope? @drive.readonly
	google/has-scope? @drive
][
	do-test "User's storage quota info" [
		probe data: google/api-get https://www.googleapis.com/drive/v3/about?fields=storageQuota
	]
	;@@ WIP!!!
	do-test "List some folders from the Drive" [
		probe data: drive/files/part "q=mimeType='application/vnd.google-apps.folder'" 10
	]

]