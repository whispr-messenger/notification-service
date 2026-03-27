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


Bearer Token:

eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6ImRldi1raWQtMSJ9.eyJzdWIiOiIxMTExMTExMS0xMTExLTExMTEtMTExMS0xMTExMTExMTExMTEiLCJpc3MiOiJ3aGlzcHItYXV0aCIsImF1ZCI6IndoaXNwci1ub3RpZmljYXRpb24iLCJleHAiOjE4OTM0NTYwMDB9.d4oG6Ngs_OfzzOF-BNxTiNLJpNA2rf689Zm4WgbYgVE
