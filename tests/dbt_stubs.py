import hashlib
import json
import re
from pathlib import Path

from jinja2 import Environment, StrictUndefined, nodes
from jinja2.ext import ExprStmtExtension


class CompilerError(Exception):
    pass


class MacroReturn(Exception):
    def __init__(self, value):
        super().__init__("macro return")
        self.value = value


class Target:
    def __init__(self):
        self.database = "ANALYTICS"
        self.schema = "PUBLIC"
        self.name = "test"


class Exceptions:
    def raise_compiler_error(self, message):
        raise CompilerError(message)


class QueryResult:
    def __init__(self, rows=None, columns=None):
        self.rows = rows or []
        self.columns = columns or []


class Namespace:
    pass


class ThisProxy:
    def __init__(self, context):
        self.context = context

    def __str__(self):
        return self.context.this

    def __repr__(self):
        return self.context.this


ROOT = Path(__file__).resolve().parent.parent
TEST_OPEN = re.compile(r"\{%-?\s*test\s+")
TEST_CLOSE = re.compile(r"\{%-?\s*endtest\s*-?%\}")


def tojson(value, sort_keys=False, indent=None):
    return json.dumps(value, sort_keys=sort_keys, indent=indent)


def local_md5(value):
    return hashlib.md5(str(value).encode("utf-8")).hexdigest()


def macro_names(env, source):
    return [node.name for node in env.parse(source).find_all(nodes.Macro)]


def wrap_macro(fn):
    def call(*args, **kwargs):
        try:
            return fn(*args, **kwargs)
        except MacroReturn as early:
            return early.value

    return call


def as_test_free(source):
    text = TEST_OPEN.sub("{% macro ", source)
    return TEST_CLOSE.sub("{% endmacro %}", text)


class MacroContext:
    def __init__(self):
        self.vars = {}
        self.incremental = False
        self.this = '"ANALYTICS"."PUBLIC"."MODEL"'
        self.target = Target()
        self.exceptions = Exceptions()
        self.statements = []
        self.query_results = []
        self.env = Environment(undefined=StrictUndefined, extensions=[ExprStmtExtension])
        self.env.filters["tojson"] = tojson
        self.env.globals["tojson"] = tojson
        self.env.globals["local_md5"] = local_md5
        self.env.globals["var"] = self.get_var
        self.env.globals["target"] = self.target
        self.env.globals["exceptions"] = self.exceptions
        self.env.globals["is_incremental"] = self.is_incremental
        self.env.globals["this"] = ThisProxy(self)
        self.env.globals["run_query"] = self.run_query
        self.env.globals["print"] = self.capture_print
        self.env.globals["log"] = self.capture_log
        self.env.globals["return"] = self.do_return
        self.jevflake = Namespace()
        self.env.globals["jevflake"] = self.jevflake
        self.printed = []
        self.logs = []
        self.load_macros()

    def get_var(self, name, default=None):
        return self.vars.get(name, default)

    def is_incremental(self):
        return self.incremental

    def run_query(self, statement):
        self.statements.append(statement)
        if self.query_results:
            return self.query_results.pop(0)
        return QueryResult()

    def capture_print(self, *args):
        self.printed.append(" ".join(str(part) for part in args))
        return ""

    def capture_log(self, message, info=None):
        self.logs.append(message)
        return ""

    def do_return(self, value):
        raise MacroReturn(value)

    def load_macros(self):
        for path in sorted(ROOT.glob("macros/**/*.sql")):
            source = as_test_free(path.read_text())
            template = self.env.from_string(source)
            module = template.make_module()
            for name in macro_names(self.env, source):
                setattr(self.jevflake, name, wrap_macro(getattr(module, name)))

    def call(self, name, *args, **kwargs):
        return getattr(self.jevflake, name)(*args, **kwargs)
