[![rebol-google](https://github.com/user-attachments/assets/5710b178-0860-463f-8b8e-1693dffddc06)](https://github.com/Oldes/Rebol-Google)

[![Rebol-Google CI](https://github.com/Oldes/Rebol-Google/actions/workflows/main.yml/badge.svg)](https://github.com/Oldes/Rebol-Google/actions/workflows/main.yml)
[![Gitter](https://badges.gitter.im/rebol3/community.svg)](https://app.gitter.im/#/room/#Rebol3:gitter.im)
[![Zulip](https://img.shields.io/badge/zulip-join_chat-brightgreen.svg)](https://rebol.zulipchat.com/)

# Rebol/Google

Google API integration module for [Rebol3](https://github.com/Oldes/Rebol3).

## Usage:

To use this module, you need a Client ID and Secret for OAuth2 authentication.  
Follow these steps to obtain them: https://support.google.com/googleapi/answer/6158849

The module stores these values in encrypted local storage.  
If no user is set up yet, you will be prompted to provide a username, password for the local storage and the Client ID and Secret obtained from the Google Console.

A browser window will then open, where you'll need to choose a Google account and grant the required scopes for the script to access.

The module can be imported like any other Rebol module:
```rebol
google: import %google.reb ;; when the module is in the current location
```
or:
```rebol
google: import google      ;; when the module is in the common modules location
```

It does not export any functions; instead, it currently contains the following API access points:
* `google/people` to access user's Contacts
* `google/gmail` to access Gmail mailboxes and send mail
* `google/photos` to see, upload, and organize items in your Google Photos library
* `google/drive` to access user's files (WIP)

Access points should be considered experimental shortcuts only and may be used, for example, like this:
```rebol
data: google/people/contacts ;; resolves user's contacts data
foreach person data/connections [
    if person/emailAddresses [
        print [
            as-green person/names/1/displayName
            person/emailAddresses/1/value
        ]
    ]
]
```
It is also possible to use direct API requests like:
```rebol
data: google/api-get https://gmail.googleapis.com/gmail/v1/users/me/messages?q=newer_than:1d
```
Which is same like:
```rebol
data: google/gmail [messages "newer_than:1d"]
```

It should also be noted that the module, by default, expects only basic scopes. To access additional API functions, you may need to include the required scopes using the `add-scope` function. When scopes are modified, the token is dropped and the user must authenticate again!
```rebol
google/add-acope https://www.googleapis.com/auth/userinfo.profile
;; which is same like:
google/add-scope @userinfo.profile
```

List of all Google's OAuth2 scopes may be found here:
https://developers.google.com/identity/protocols/oauth2/scopes

