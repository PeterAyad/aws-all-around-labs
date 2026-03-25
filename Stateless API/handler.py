import json


def lambda_handler(event, context):
    """
    Simple stateless Lambda function for learning AWS.
    Handles GET /hello and POST /echo routes.
    """

    http_method = event.get("httpMethod", "")
    path = event.get("path", "/")
    query_params = event.get("queryStringParameters") or {}
    body_raw = event.get("body") or "{}"

    # Parse body safely
    try:
        body = json.loads(body_raw)
    except json.JSONDecodeError:
        body = {}

    # --- Route: GET /hello ---
    if http_method == "GET" and path == "/hello":
        name = query_params.get("name", "World")
        return respond(200, {"message": f"Hello, {name}!"})

    # --- Route: POST /echo ---
    if http_method == "POST" and path == "/echo":
        return respond(200, {"you_sent": body})

    # --- Fallback ---
    return respond(404, {"error": f"Route not found: {http_method} {path}"})


def respond(status_code, body_dict):
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
        },
        "body": json.dumps(body_dict),
    }
