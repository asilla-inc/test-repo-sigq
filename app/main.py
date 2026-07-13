"""Dummy app entrypoint used only to generate realistic diffs/conflicts."""


def get_version() -> str:
    return "5.1.0"


def greet(name: str) -> str:
<<<<<<< HEAD
    # hotfix: guard against empty name (dummy bug fix)
    # v5.1: friendlier greeting copy
    name = name or "anonymous"
    return f"Hi there, {name}! (v{get_version()})"
=======
    return f"hello, {name}! Running v{get_version()}."
>>>>>>> f07cd08 (feat: my lab change to greet())


if __name__ == "__main__":
    print(greet("world"))
