"""Dummy feature: basic auth stub for v5.0."""


def is_authorized(token: str) -> bool:
    return token == "dummy-token-v5"
