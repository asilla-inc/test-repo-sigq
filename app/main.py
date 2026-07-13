"""Dummy app entrypoint used only to generate realistic diffs/conflicts."""


def get_version() -> str:
    return "5.0.0-dev"


def greet(name: str) -> str:
    return f"Hello, {name}! Running v{get_version()}."


if __name__ == "__main__":
    print(greet("world"))
