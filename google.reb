Rebol [
	Title:   "Google"
	Purpose: "Google Web API access (experimental)"
	Date:    10-Apr-2025
	Author:  @Oldes
	File:    %google.reb
	Name:    google
	Type:    module
	Version:  0.0.9
	Require: httpd
	Note: {
		Useful info:
		https://developers.google.com/identity/protocols/oauth2/scopes
		https://developers.google.com/people/api/rest
		https://developers.google.com/gmail/api/reference/rest
		https://aaronparecki.com/oauth-2-simplified/
	}
	Needs: 3.11.0 ;; using try/with instead of deprecated try/except
]

append system/options/log [google: 1]

config: function[
	"Resolve Google API config state from user's persistent data storage"
][
	unless system/user/name [
		name: ask      "User: "
		pass: ask/hide "Password: "
		;; when user does not exists, create a new one!
		set-user/n/p :name :pass
	]
	ctx: user's google-api
	unless map? ctx [
		sys/log/error 'GOOGLE "Client is not configured yet!"
		ctx: make map! 4

		unless all [
			ctx/client-id:     ask/hide "Client ID: "
			ctx/client-secret: ask/hide "Client Secret: "
		][	;; when user hits ESC...
			sys/log/error 'GOOGLE "Missing credentials!"
			return make map! []
		]
		;; All scopes?
		ctx/scopes: [
			https://www.googleapis.com/auth/contacts
			;https://www.googleapis.com/auth/contacts.readonly       ;; See and download your contacts
			;https://www.googleapis.com/auth/contacts.other.readonly ;; See and download contact info automatically saved in your "Other contacts"
			;https://www.googleapis.com/auth/userinfo.profile        ;; See your personal info, including any personal info you've made publicly available

			https://www.googleapis.com/auth/gmail.readonly           ;; View your email messages and settings

			https://www.googleapis.com/auth/photoslibrary.readonly   ;; View your Google Photos library
			https://www.googleapis.com/auth/photoslibrary.readonly.appcreateddata ;; Manage photos added by this app
			https://www.googleapis.com/auth/photoslibrary.edit.appcreateddata     ;; Edit the info in your photos, videos, and albums created within this app, including titles, descriptions, and covers
			
			https://www.googleapis.com/auth/drive.readonly ;; See, edit, create, and delete all of your Google Drive files
		]
		store-config ctx
	]
	ctx
]

has-scope?: function[
	"Returns true if the user has the requested scope"
	scope [url! ref!]
][
	if ref? scope [scope: join https://www.googleapis.com/auth/ scope]
	to logic! all [
		ctx: user's google-api
		find ctx/scopes scope
	]
]

add-scope: function[
	"Adds a new scope if it doesn't already exist. The user must reauthorize before any API use!"
	scope [url! ref!]
][
	if ref? scope [scope: join https://www.googleapis.com/auth/ scope]
	if has-scope? scope [return true] ;; returns true if the scope already exists
	ctx: config
	append ctx/scopes scope
	remove/key ctx 'token ;; when scopes changes, token must be reauthorized
	store-config ctx
	true
]

store-config: function[
	"Save the current config state in user's persistent data storage"
	config [map!]
][
	put system/user/data 'google-api config 
	update system/user/data
	config
]

drop-token: function[
	"Used to force authentication"
][
	sys/log/debug 'GOOGLE "Releasing a user's token"
	ctx: user's google-api
	unless map? ctx [exit]
	remove/key ctx 'token
	store-config ctx
]

authorize: function [
	"OAuth2 Google authorization used to get the main context"
	ctx [map!]
][
	import httpd

	sys/log/info 'GOOGLE "OAuth2 Google API authorization."

	unless client-id: ctx/client-id [ 
		sys/log/error 'GOOGLE "`client-id` is needed to authorize with Google API"
		return none
	]

	;; get random unused port for callback server
	loop 10 [
		port: 10000 + random 10000
		if port? try [tmp: open join tcp://: port][ close tmp break ]
	]

	scopes: ctx/scopes

	unless string?  client-id [ client-id: form :client-id ]
	unless string?  scopes    [ scopes:    form :scopes    ]
	client-secret: ctx/client-secret

	redirect-uri: ajoin ["http://localhost:" port]

	code-verifier: form random/secure checksum join client-id now/precise 'sha256
	code-challenge: enbase/url checksum code-verifier 'sha256 64

	;-- 1. Request authorization; the user logs in and authorizes access
	; build request url
	url: rejoin [
		https://accounts.google.com/o/oauth2/v2/auth?
		"response_type=code&show_dialog=false"
		"&client_id="    :client-id
		"&scope="        enhex :scopes
		"&redirect_uri=" redirect-uri
		"&state=" state: form random 99999999999
		"&code_challenge_method=S256&code_challenge=" code-challenge
	]
	; and open the url in user's default browser
	browse url

	; Result from the server is returned as a redirect, so let's start simple server
	; listening on specified port (limited to accept only local requests, as the redirect is
	; going from the browser actually.. it automaticaly close itself once data are received
	result: system/modules/httpd/serve-http [
		port: :port
		actor: [
			;- Server's actor functions
			On-Accept: func [info [object! block!]][
				; allow only connections from localhost
				; TRUE = accepted, FALSE = refuse
				find [ 127.0.0.1 ] info/remote-ip 
			]
			On-Header: func [ctx [object!]][
				either ctx/inp/target/file == %/ [
					ctx/out/status: 200
					ctx/out/content: ajoin [
						"<h1>OAuth2 Google Callback</h1>"
						"<br/>Header:<pre>" mold ctx/inp/header </pre>
						"<br/>Values:<pre>" mold ctx/inp/target/values </pre>
						"<h2>You can close this window and return back to Rebol</h2>"
					]
					ctx/done?: ctx/inp/target/values
				][
					ctx/out/status: 405
					ctx/done?: true
				]
			]
		]
	]

	; validate result from first step
	if any [
		not block? result
		none? result/code
		state <> result/state
	][
		sys/log/error 'GOOGLE {Unexpected result from Google authorization!}
		return none
	]

	;probe result

	;-- 2. Request refresh and access tokens using the result code
	try/with [
		time: now
		result: write/all https://www.googleapis.com/oauth2/v4/token compose [
			POST [
				Content-Type: "application/x-www-form-urlencoded"
			] ( rejoin [
				"grant_type=authorization_code"
				"&code="          result/code
				"&scope="         ;enhex :scopes ;; required here?
				"&redirect_uri="  redirect-uri
				"&client_id="     ctx/client-id
				"&client_secret=" ctx/client-secret
				"&code_verifier=" code-verifier
			])
		]
		data: attempt [load-json result/3]
		either result/1 == 200 [
			ctx/token: data
			ctx/token/expires_in: time + (to time! ctx/token/expires_in)
			;; the refresh_token must be stored outside of the token value, because
			;; the token value is rewriten on refresh with a content, which does not
			;; have the refresh_token value anymore (it is resolved only after authentication)
			ctx/refresh_token: ctx/token/refresh_token
		][
			sys/log/error 'GOOGLE "Failed to receive Google token!"
			if all [data data/error] [
				sys/log/error 'GOOGLE [data/error_description "-" data/error]
			]
			return none
		]
	][
		sys/log/error 'GOOGLE "Failed to receive Google token!"
		sys/log/error 'GOOGLE system/state/last-error
		return none
	]
	sys/log/debug 'GOOGLE ["access_token: " copy/part ctx/token/access_token 15 "..."]
	store-config ctx
]

refresh: function[
	ctx [map!]
][
	sys/log/info 'GOOGLE "Refreshing Google API token."
	if any [
		none? ctx/refresh_token
		none? ctx/client-id
		none? ctx/client-secret
	][
		sys/log/error 'GOOGLE "Not sufficient info to refresh a token!"
		drop-token
		return authorize ctx
	]
	result: write/all https://www.googleapis.com/oauth2/v4/token compose [
		POST [
			Content-Type: "application/x-www-form-urlencoded"
		]( probe rejoin [
			"grant_type=refresh_token"
			"&refresh_token=" enhex ctx/refresh_token
			"&client_id="     ctx/client-id
			"&client_secret=" ctx/client-secret
		])
	]
	data: attempt [load-json result/3]
	either result/1 == 200 [
		ctx/token: data
		ctx/token/expires_in: now + (to time! ctx/token/expires_in)
		store-config ctx
	][
		sys/log/error 'GOOGLE "Failed to refresh the token!"
		if all [data data/error] [
			sys/log/error 'GOOGLE [reason/error_description "-" reason/error]
		]
		drop-token
		return authorize ctx
	]
]

request: function/with [
	method [word!]
	what   [any-string!]
	data   [any-type!]
][
	clear header
	try/with [
		ctx: config
		unless ctx/token [ctx: authorize ctx] ;; resolve the token
		unless ctx/token [return none  ] ;; exit if still not present
		if now >= ctx/token/expires_in [
			unless refresh ctx [ return none ] ;; exit.. as we failed authorize and also refresh
		]
		header/Authorization: join "Bearer " ctx/token/access_token
		header/Accept: "application/json"
		if map? data [
			data: to-json data
			header/Content-Type: "application/json"
		]
		sys/log/info 'GOOGLE [method as-green what]

		result: write/all what reduce [
			method header any [data ""]
		]
		data: load-json result/3
		either result/1 >= 400 [
			sys/log/error 'GOOGLE [method as-red what]
			if all [map? data data/error] [
				if data/error_description [sys/log/error 'GOOGLE data/error_description]
				sys/log/error 'GOOGLE [data/error]
			]
			none
		][	data ]
	][
		sys/log/error 'GOOGLE system/state/last-error
		none
	]
][
	header: make map! 6
]

api-get:  func [what [any-string!]           ][request 'GET    what none]
api-put:  func [what [any-string!] /with data][request 'PUT    what data]
api-del:  func [what [any-string!]           ][request 'DELETE what none]
api-post: func [what [any-string!]       data][request 'POST   what data]

all-personFields: [
	@addresses
	@ageRanges
	@biographies
	@birthdays
	@calendarUrls
	@clientData
	@coverPhotos
	@emailAddresses
	@events
	@externalIds
	@genders
	@imClients
	@interests
	@locales
	@locations
	@memberships
	@metadata
	@miscKeywords
	@names
	@nicknames
	@occupations
	@organizations
	@phoneNumbers
	@photos
	@relations
	@sipAddresses
	@skills
	@urls
	@userDefined
]

;@@ TODO: write more API functions....
people: context [
	profile: does [
		;; https://developers.google.com/people/v1/profiles
		;; requires scope: auth/userinfo.profile
		contact/with none combine/with all-personFields #","
	]
	contact: function[
		"Get contact info"
		id [string! none!] "resource name: people/*"
		/with fields {Default is: "metadata,names,emailAddresses"}
	][
		case [
			not id [id: "people/me"]
			not parse id ["people/" some system/catalog/bitsets/alpha-numeric][
				sys/log/error 'GOOGLE ["Invalid resource name:" as-red mold/flat id]
				return none
			]
		]
		api-get rejoin [
			https://people.googleapis.com/v1/ id
			"?personFields=" any [fields "metadata,names,emailAddresses"]
		]
	]
	contacts: function[
		/with fields {Default is: "metadata,names,emailAddresses"}
		/part        "Limit number of results"
		length [integer!]
	][
		;; https://developers.google.com/people/v1/contacts
		;; requires scope: auth/contacts.readonly
		url: https://people.googleapis.com/v1/people/me/connections

		pageSize: min 1000 any [length 500] ;; request 500, but not more then maximum 1000
		nextPageToken: none 
		result: clear []
		until [
			data: api-get rejoin [
				url "?pageSize=" pageSize
				"&personFields=" any [fields "metadata,names,emailAddresses"]
				"&pageToken=" any [nextPageToken ""]
			]
			if any [not data not data/connections][break]
			append result data/connections
			if all [part length <= length? result][
				;; it is possible to receive more items then requested length
				;; crop it in such a case...
				clear skip result length
				;; and stop, as we have enough results
				break
			]
			none? nextPageToken: data/nextPageToken
		]
		result
	]

	create: function[
		"Create a new contact"
		contact [map!] "https://developers.google.com/people/api/rest/v1/people#Person"
	][	;; https://developers.google.com/people/api/rest/v1/people/createContact
		;; requires scope: https://www.googleapis.com/auth/contacts
		api-post https://people.googleapis.com/v1/people:createContact :contact
	]
	delete: function[
		"Remove contact"
		id [string!] "resource name: people/*"
	][	;; https://developers.google.com/people/api/rest/v1/people/deleteContact
		;; requires scope: https://www.googleapis.com/auth/contacts
		unless parse id ["people/" some system/catalog/bitsets/alpha-numeric][
			sys/log/error 'GOOGLE ["Invalid resource name:" as-red mold/flat id]
			return none
		]
		api-del rejoin [https://people.googleapis.com/v1/ id ":deleteContact"]
	]
]

;@@ maybe using a dialected requests?
gmail: function [request [ref! block!]][
	unless block? request [request: to block! request]
	collect [
		parse request [any [
			'profile (
				keep api-get https://gmail.googleapis.com/gmail/v1/users/me/profile
				;; Requires one of the following OAuth scopes:
				;; https://mail.google.com/
				;; https://www.googleapis.com/auth/gmail.modify
				;; https://www.googleapis.com/auth/gmail.compose
				;; https://www.googleapis.com/auth/gmail.readonly
				;; https://www.googleapis.com/auth/gmail.metadata

				;; Returns something like:
				;;	#[
				;;		emailAddress: "some@email"
				;;		messagesTotal: 1234
				;;		threadsTotal: 23
				;;		historyId: "16337600"
				;;	]
			)
			|
			'messages opt [set query: string!] (
				keep api-get either query [
					;@@ TODO: url-encode the query?
					join https://gmail.googleapis.com/gmail/v1/users/me/messages?q= query
				][	https://gmail.googleapis.com/gmail/v1/users/me/messages]

				;; Returns something like:
				;;	#[
				;;		messages: [#[
				;;	 	    id: "18949a4bbc4cce97"
				;;	 	    threadId: "189446292fce7946"
				;;	 	)]
				;;	 	nextPageToken: "05405932033369967487"
    			;;	 	resultSizeEstimate: 201
    			;;	]
			)
			| 'message set id: string! (
				keep api-get join https://gmail.googleapis.com/gmail/v1/users/me/messages/ id
			)
		]]
	]
]

photos: context [
	;; Required scopes: photoslibrary.readonly or photoslibrary.readonly.appcreateddata
	albums: function[
		"Resolve all user's Google Photos albums"
		/part          "Limit number of results"
		length [integer!]
	][
		url: https://photoslibrary.googleapis.com/v1/albums
		nextPageToken: none
		result: clear []
		until [
			data: api-get rejoin [url "?pageToken=" any [nextPageToken ""]]
			if any [not data not data/albums][break]
			append result data/albums
			if all [part length <= length? result][
				;; it is possible to receive more items then requested length
				;; crop it in such a case...
				clear skip result length
				;; and stop, as we have enough results
				break
			]
			none? nextPageToken: data/nextPageToken
		]
		result
	]

	items: function[
		"List all of the media items in an album"
		album [string! ref!]
		/with          "Limit search based on content, date, and other properties"
		filters [map!] "https://developers.google.com/photos/library/guides/apply-filters"
		/part          "Limit number of results"
		length [integer!]
	][
		url: https://photoslibrary.googleapis.com/v1/mediaItems:search
		req: make map! 4 ;; no copy, because it is reused for all requests
		req/albumId:  album
		req/pageSize: either part [min 100 length][100]
		nextPageToken: none
		result: clear []
		until [
			data: api-post rejoin [url "?pageToken=" any [nextPageToken ""]] :req
			if any [not data not data/mediaItems][break]
			append result data/mediaItems
			if all [part length <= length? result][
				;; it is possible to receive more items then requested length
				;; crop it in such a case...
				clear skip result length
				;; and stop, as we have enough results
				break
			]
			none? nextPageToken: data/nextPageToken
		]
		result
	]
]

;@@ TODO: write more API functions....
drive: context [
	;- https://developers.google.com/workspace/drive/api/guides/about-sdk
	files: function [
		"Lists the user's files."
		params [block! map! object!] {Query parameters to be used.}
		/part  "Limit number of results"
		length [integer!]
	][
		url: https://www.googleapis.com/drive/v3/files
		;; Google Drive has different API than Google Photos. It uses just GET api!

		nextPageToken: none
		result: clear []

		query: copy "?"
		unless find params 'fields [
			append query ajoin ["fields=" default-files-fields #"&"]
		]

		foreach [key value] params [
			key: any [deprecated-params/:key key]
			switch key [
				limit [length: attempt [to integer! :value] continue]
				query [key: 'q] ;; 'query' looks better, 'q' is the real name
				fields [
					value: either block? :value [
						ajoin ["files(" combine/with value #"," #")"]
					][	to string! :value ]
					unless find value "nextPageToken" [
						insert value "nextPageToken," ;; this field is needed
					]
				]
			]
			;; use only valid key names...
			if find valid-files-params key [
				append query ajoin [key #"=" value #"&"]
			]
		]

		until [
			data: api-get as url! ajoin [
				url query
				if nextPageToken [join "pageToken=" nextPageToken]
			]
			if any [not data not data/files][break]
			append result data/files
			if all [length length <= length? result][
				;; it is possible to receive more items then requested length
				;; crop it in such a case...
				clear skip result length
				;; and stop, as we have enough results
				break
			]
			none? nextPageToken: data/nextPageToken
		]
		result
	]

	drives: function [
		"Lists the user's shared drives"
		/with query [string!] "Extra query params, e.g.: {fields=drives(id,name,createdTime)}"
		/part  "Limit number of results"
		length [integer!]
	][
		url: https://www.googleapis.com/drive/v3/drives

		nextPageToken: none
		result: clear []

		if all [query #"&" <> last query] [query: join query #"&"] 

		until [
			data: api-get as url! ajoin [
				url #"?" any [query ""]
				if nextPageToken [join "pageToken=" nextPageToken]
			]
			if any [not data not data/drives][break]
			append result data/drives
			if all [length length <= length? result][
				;; it is possible to receive more items then requested length
				;; crop it in such a case...
				clear skip result length
				;; and stop, as we have enough results
				break
			]
			none? nextPageToken: data/nextPageToken
		]
		result
	]

	default-files-fields: {nextPageToken,files(id,name,mimeType,modifiedTime,quotaBytesUsed,parents,driveId,size,sha256Checksum)}
	;; Conversion of deprecated paramaters the the prefered one...
	deprecated-params: make map! [
		corpus: corpora
		includeTeamDriveItems: includeItemsFromAllDrives
		supportsTeamDrives: supportsAllDrives
		teamDriveId: driveId
	]
	;; These are valid parameters...
	valid-files-params: [
		corpora
		driveId
		includeItemsFromAllDrives
		orderBy
		pageSize
		pageToken
		q
		spaces
		supportsAllDrives
		includePermissionsForView
		includeLabels
		fields
	]
	;; These values may be used to order the files output...
	orderByKeys: [
		createdTime      ;; When the file was created.
		folder           ;; The folder ID. This field is sorted using alphabetical ordering.
		modifiedByMeTime ;; The last time the file was modified by the user.
		modifiedTime     ;; The last time the file was modified by anyone.
		name             ;; The name of the file. This field is sorted using alphabetical ordering, so 1, 12, 2, 22.
		name_natural     ;; The name of the file. This field is sorted using natural sort ordering, so 1, 2, 12, 22.
		quotaBytesUsed   ;; The number of storage quota bytes used by the file.
		recency          ;; The most recent timestamp from the file's date-time fields.
		sharedWithMeTime ;; When the file was shared with the user, if applicable.
		starred          ;; Whether the user has starred the file.
		viewedByMeTime   ;; The last time the file was viewed by the user.
	]

]