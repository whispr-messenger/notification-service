#Lancez :

python -m http.server 8081

Où il y a le jwks.json
avec
{
    "keys": [
      {
        "kty": "oct",
        "kid": "dev-kid-1",
        "alg": "HS256",
        "use": "sig",
        "k": "bXktc2VjcmV0LWtleS0xMjM0NTY3ODkwNDU2OTg3NDUz"
      }
    ]
}

Dans le terminal:

$env:JWT_JWKS_URL="http://localhost:8081/jwks.json"
$env:JWT_ISSUER="whispr-auth"
$env:JWT_AUDIENCE="whispr-notification"
$env:JWT_ALLOWED_ALGS="HS256"
$env:JWT_JWKS_REFRESH_INTERVAL_MS="300000"

https://www.jwt.io/

Header

{
  "alg": "HS256",
  "typ": "JWT",
  "kid": "dev-kid-1"
}

Payload

{
  "sub": "11111111-1111-1111-1111-111111111111",
  "iss": "whispr-auth",
  "aud": "whispr-notification",
  "exp": 1893456000
}

Sign JWT

my-secret-key-1234567890456987453


Bearer Token generated

