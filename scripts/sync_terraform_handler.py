import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "macros" / "setup" / "handler.sql"
TARGET = ROOT / "terraform" / "handler.py.tftpl"

MODEL_EXPRESSION = "{{ tojson(jevflake.model_name()) }}"
SETTING_PATTERN = re.compile(r"\{\{ var\('jevflake_([a-z_]+)', \d+\) \| int \}\}")


def render(source):
    lines = [line for line in source.splitlines() if not line.strip().startswith("{%")]
    text = "\n".join(lines).strip("\n") + "\n"
    if "${" in text or "%{" in text:
        raise ValueError("handler.sql contains a sequence Terraform would treat as a template directive")
    text = text.replace(MODEL_EXPRESSION, "${jsonencode(model)}")
    text = SETTING_PATTERN.sub(lambda match: "${" + match.group(1) + "}", text)
    if "{{" in text:
        raise ValueError("unrendered Jinja left in handler.sql")
    return text


def main():
    rendered = render(SOURCE.read_text())
    if "--check" in sys.argv:
        if not TARGET.exists() or TARGET.read_text() != rendered:
            print("terraform/handler.py.tftpl is out of date. Run: python3 scripts/sync_terraform_handler.py")
            return 1
        print("terraform/handler.py.tftpl is up to date")
        return 0
    TARGET.write_text(rendered)
    print("wrote", TARGET.relative_to(ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
