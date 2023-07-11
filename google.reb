Rebol [
	Title:   "Google"
	Purpose: "Google Web API access (experimental)"
	Date:    11-Jul-2023
	Author:  @Oldes
	File:    %google.reb
	Name:    'google
	Type:    'module
	Version:  0.0.2
	Require: 'httpd
	Note: {
		Useful info:
		https://developers.google.com/identity/protocols/oauth2/scopes
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
	ctx: user's 'google-api
	unless map? ctx [
		sys/log/error 'GOOGLE "Google API must be configured!"
		ctx: make map! 6

		unless all [
			ctx/client-id:     ask/hide "Client ID: "
			ctx/client-secret: ask/hide "Client Secret: "
		][
			sys/log/error 'GOOGLE "Missing credentials!"
			return #()
		]
		;; All scopes?
		ctx/scopes: [
			https://www.googleapis.com/auth/contacts.readonly        ;; See and download your contacts
			https://www.googleapis.com/auth/contacts.other.readonly  ;; See and download contact info automatically saved in your "Other contacts"
			https://www.googleapis.com/auth/userinfo.profile         ;; See your personal info, including any personal info you've made publicly available
		]
		store-config ctx
	]
	ctx
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
	ctx: user's 'google-api
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
	result: system/modules/httpd/http-server/config/actor port [
		root:       #[false] ; we are not serving any content!
		keep-alive: #[false]
	][	;- Server's actor functions
		On-Accept: func [info [object!]][
			; allow only connections from localhost
			; TRUE = accepted, FALSE = refuse
			find [ 127.0.0.1 ] info/remote-ip 
		]
		On-Header: func [ctx [object!]][
			either ctx/inp/target/file == %/ [
				ctx/out/status: 200
				ctx/out/content: ajoin [
					"<h1>OAuth2 Google Callback</h1>"
					"<br/>Request header:<pre>" mold ctx/inp/header </pre>
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

	; validate result from first step
	if any [
		not block? result
		none? result/code
		state <> result/state
	][
		sys/log/error 'GOOGLE {Unexpected result from Google authorization!}
		return none
	]

	sys/log/debug 'GOOGLE result

	;-- 2. Request refresh and access tokens using the result code
	try/with [
		time: now
		result: write/all https://www.googleapis.com/oauth2/v4/token compose [
			POST [
				Content-Type: "application/x-www-form-urlencoded"
			] ( probe rejoin [
				"grant_type=authorization_code"
				"&code="          result/code
				"&scope="        enhex :scopes
				"&redirect_uri="  redirect-uri
				"&client_id="     ctx/client-id
				"&client_secret=" ctx/client-secret
				"&code_verifier=" code-verifier
			])
		]
		either result/1 == 200 [
			ctx/token: load-json result/3
			ctx/token/expires_in: time + (to time! ctx/token/expires_in)
		][
			result: load-json result/3
			sys/log/error 'GOOGLE "Failed to receive Google token!"
			if result/error [
				sys/log/error 'GOOGLE [result/error_description "-" result/error]
			]
			return none
		]
		
	][
		sys/log/error 'GOOGLE "Failed to receive Google token!"
		sys/log/error 'GOOGLE system/state/last-error
		return none
	]

	store-config ctx
]

refresh: function[
	ctx [map!]
][
	sys/log/info 'GOOGLE "Refreshing Google API token."
	ctx/token: load-json write https://accounts.spotify.com/api/token compose [
		POST [
			Content-Type: "application/x-www-form-urlencoded"
		]( rejoin [
			"grant_type=refresh_token"
			"&refresh_token=" ctx/token/refresh_token
			"&client_id="     ctx/client-id
			"&client_secret=" ctx/client-secret
		])
	]
]

request: func [
	method [word!]
	what   [any-string!]
	data   [any-type!]
	/local ctx header result
][
	header: clear #()

	try/with [
		ctx: config
		unless ctx/token [authorize ctx]
		if now >= ctx/token/expires_in [ refresh ctx ]
		header/Authorization: join "Bearer " ctx/token/access_token
		if map? data [
			data: to-json data
			header/Content-Type: "application/json"
		]

		result: write/all what reduce [
			method header any [data ""]
		]
		data: load-json result/3
		either result/1 >= 400 [
			sys/log/error 'GOOGLE ["Failed" method "of" as-green what]
			if result/error [
				sys/log/error 'GOOGLE [result/error_description "-" result/error]
			]
			none
		][	data ]
	][
		sys/log/error 'GOOGLE ["Failed" method "of" as-green what]
		sys/log/error 'GOOGLE system/state/last-error
		none
	]
]

api-get: func [what [any-string!]           ][request 'GET    what none]
api-put: func [what [any-string!] /with data][request 'PUT    what data]
api-del: func [what [any-string!]           ][request 'DELETE what none]


;@@ TODO: write more API functions....
people: context [
	profile: does [
		;; https://developers.google.com/people/v1/profiles
		;; requires scope: auth/userinfo.profile
		api-get https://people.googleapis.com/v1/people/me?personFields=names,emailAddresses
	]
	contacts: does [
		;; https://developers.google.com/people/v1/contacts
		;; requires scope: auth/contacts.readonly
		api-get https://people.googleapis.com/v1/people/me/connections?personFields=names,emailAddresses
	]
	other-contacts: does [
		;; https://developers.google.com/people/v1/other-contacts
		;; requires scope: auth/contacts.other.readonly
		api-get https://people.googleapis.com/v1/otherContacts?readMask=names,emailAddresses
	]
]
