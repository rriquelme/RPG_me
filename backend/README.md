# RPG_me — Serverless backend (Phase 2)

The same `rpgme` engine from Phase 1, exposed over HTTP and persisted to
DynamoDB. The engine code is unchanged — only a new `DynamoStore` and a thin
Lambda router were added.

```
 Flutter APK ──HTTPS──▶ API Gateway (HTTP API) ──▶ Lambda (handler.py)
                                                      │  rpgme.Engine
                                                      ▼
                                                  DynamoDB  (single table)
```

## API

| Method & path        | Body / params                          | Returns                          |
|----------------------|----------------------------------------|----------------------------------|
| `GET  /axes`         | —                                      | the 8 configured axes            |
| `POST /log`          | `{axis, name, exp?, note?, seconds?}`  | the new event + updated skill    |
| `GET  /summary`      | `?user=`                               | levels + all-time/weekly counts  |
| `GET  /time`         | `?user=`                               | tracked time per period (below)  |
| `GET  /octagon`      | `?user=`                               | radar-chart data                 |
| `GET  /streak/{name}`| `?user=`                               | current daily streak             |

`POST /log` with `seconds > 0` records a **timed session** (e.g. a tracked
study block); exp then defaults to one point per minute. `GET /time` returns
totals grouped by activity and by axis for each period:

```json
{ "periods": {
    "today":      { "by_activity": {"study": 2700}, "by_axis": {"mind": 2700}, "total_seconds": 2700 },
    "this_week":  { ... }, "this_month": { ... }, "ytd": { ... }, "all_time": { ... }
} }
```

`?user=<id>` selects the character (single-user defaults to `me`).

## Data model (single table `rpg_me`)

| PK            | SK                          | Item                              |
|---------------|-----------------------------|-----------------------------------|
| `USER#<user>` | `PROFILE`                   | `{user}`                          |
| `USER#<user>` | `SKILL#<axis>`              | `{axis_key, total_exp}`           |
| `USER#<user>` | `EVENT#<timestamp>#<id>`    | the full logged event             |

One query on `PK = USER#<user>` returns everything for a character. Events are
their own items (not one growing blob), so history scales past DynamoDB's
400 KB item limit. `DynamoStore.save()` only writes *new* events.

## Deploy

Requires the [AWS SAM CLI](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html)
and AWS credentials.

```bash
cd backend
sam build            # bundles handler.py + ../rpgme via the Makefile
sam deploy --guided  # first time: pick region, save to samconfig.toml
```

The stack outputs `ApiUrl`. Smoke test:

```bash
API=<ApiUrl from output>
curl "$API/axes"
curl -X POST "$API/log" -H 'content-type: application/json' \
     -d '{"axis":"health","name":"gym","exp":15}'
curl "$API/summary?user=me"
```

Test locally without deploying (uses Docker):

```bash
sam local start-api
```

## Before going public

`?user=` is trust-on-input — fine for a private single-user URL, **not** for a
public endpoint. Add a [Cognito](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-jwt-authorizer.html)
or JWT authorizer to the HTTP API and read the user id from the verified token
claim in `handler.py` instead of the query string.
