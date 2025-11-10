# Authentication

Basic-Fit uses an OAuth2 based authentication system.

**If you just need a quick and dirty token for testing, use [this url](https://login.basic-fit.com/?redirect_uri=com.basicfit.trainingapp%3A%2Foauthredirect&client_id=hMN33iw3DpHNg5VQaeNKoRUQKmIIvQV5vxOKba8AnrM&response_type=token&auto_login=false&app=true) and extract your token from the console.**

## Constants ([string.xml](qr/src/string.xml))

- `client_id` (android)  
    `hMN33iw3DpHNg5VQaeNKoRUQKmIIvQV5vxOKba8AnrM`
- `redirect_uri` (android)  
    `com.basicfit.trainingapp:/oauthredirect`  
- `client_id` (iOS)  
    `q6KqjlQINmjOC86rqt9JdU_i41nhD_Z4DwygpBxGiIs`
- `redirect_uri` (iOS)  
    `com.basicfit.bfa:/oauthredirect`

### Login method 1: PKCE authorization_code grant

`GET https://login.basic-fit.com/`

| URL parameter | value |
| -             | -     |
| redirect_uri  | [{redirect_uri}](#constants) |
| client_id     | [{client_id}](#constants)    |
| response_type | code |
| code_challenge | [{code_challenge}](https://www.authlete.com/developers/pkce/#24-code-challenge-method) |
| code_challenge_method | S256 |

***user logs in***  
\
`com.basicfit.trainingapp:/oauthredirect?code=<authorization_code>`  
  \
  \
`POST https://auth.basic-fit.com/token`[^2]  

| Form parameter | value |
| -              | -     |
| redirect_uri   | [{redirect_uri}](#constants) |
| client_id      | [{client_id}](#constants)    |
| grant_type     | authorization_code |
| code           | \<authorization_code> |
| code_verifier  | [{code_verifier}](https://www.authlete.com/developers/pkce/#24-code-challenge-method) |

Returns

```jsonc
{
    "access_token": "eyJh...EL5l", // access token (jwt format)
    "token_type": "Bearer",
    "expires_in": 1762758098, // access_token is valid for 12 hours from now
    "refresh_token": "18...J8" // can be used to refresh access_token
}
```

### Login method 2: token grant (less secure)

`GET https://login.basic-fit.com/`

| URL parameter | value |
| -             | -     |
| redirect_uri  | [{redirect_uri}](#constants) |
| client_id     | [{client_id}](#constants)    |
| response_type | token |
| auto_login[^1]    | false |

***user logs in***  
\
`com.basicfit.trainingapp:/oauthredirect?access_token=<access_token>&refresh_token=<refresh_token>`  \
\
This doesn't require any step to convert the authorization_code to an access_token (easier to implement), but is less secure.

### Refreshing the token

`POST https://auth.basic-fit.com/token`[^2]  

| Form parameter | value |
| -              | -     |
| redirect_uri   | [{redirect_uri}](#constants) |
| client_id      | [{client_id}](#constants)    |
| grant_type     | refresh_token |
| refresh_token  | \<refresh_token> |

Returns

```jsonc
{
    "access_token": "eyJh...EL5l", // access token (jwt format)
    "token_type": "Bearer",
    "expires_in": 1762758098, // access_token is valid for 12 hours from now
    "refresh_token": "18...J8" // can be used to refresh access_token
}
```

### Logging out

`POST https://auth.basic-fit.com/token`[^2]  

| Form parameter | value |
| -              | -     |
| token          | \<refresh_token> |
| client_id      | [{client_id}](#constants)    |

Returns `{"message":"OK"}`

### Miscellaneous

- Login my.basic-fit.com using access_token  
  `https://my.basic-fit.com/sso?token=<access_token>&returl=/overview`

[^1]: required to prevent a faulty redirect within the browser, if the user was logged in already.
[^2]: both `Content-Type: application/x-www-form-urlencoded` and `Content-Type: application/json` are supported.
