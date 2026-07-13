"""Dummy app entrypoint used only to generate realistic diffs/conflicts."""


def get_version() -> str:
    return "4.6.3"


def greet(name: str) -> str:
    return f"Hello, {name}! Running v{get_version()}."


if __name__ == "__main__":
    print(greet("world"))
