// The syntax tree.

// --- expressions ---

type e_num = i64;
type e_fnum = f64;
type e_const = struct { v: value };
type e_str = struct { parts: []part };
type e_var = struct { name: str, line: int };
type e_list = struct { items: []*expr };
type e_map = struct { keys: []*expr, vals: []*expr };
type e_bin = struct { op: str, a: *expr, b: *expr, line: int };
type e_un = struct { op: str, a: *expr, line: int };
type e_call = struct { name: str, args: []*expr, line: int };
type e_method = struct { obj: *expr, name: str, args: []*expr, line: int };
type e_cap = struct { raw: str, line: int };
type e_index = struct { obj: *expr, idx: *expr, line: int };
type e_attr = struct { obj: *expr, name: str, line: int };
type expr = (e_num | e_fnum | e_const | e_str | e_var | e_list | e_map | e_bin
	| e_un | e_call | e_method | e_cap | e_index | e_attr);

// Parts of a "string" or of a command word.
type p_lit = str;
type p_var = str;
type p_expr = *expr;
type p_cap = str;
type part = (p_lit | p_var | p_expr | p_cap);

// --- commands ---

type word = struct { parts: []part, quoted: bool };
type redir = struct { target: word, app: bool };
type stage = struct {
	args: []word,
	out: nullable *redir,
	err: nullable *redir,
	inp: nullable *word,
};

// --- statements ---

type s_let = struct { name: str, val: *expr, line: int };
type s_assign = struct { target: *expr, op: str, val: *expr, line: int };
type s_if = struct { cond: *expr, body: []stmt, els: []stmt, line: int };
type s_while = struct { cond: *expr, body: []stmt, line: int };
type s_for = struct { var: str, it: *expr, par: nullable *expr, body: []stmt, line: int };
type s_fn = struct { name: str, params: []str, body: []stmt, line: int };
type s_return = struct { val: nullable *expr, line: int };
type s_cmd = struct { stages: []stage, try_: bool, line: int };
type s_expr = struct { e: *expr, line: int };
type s_break = int;
type s_continue = int;
type stmt = (s_let | s_assign | s_if | s_while | s_for | s_fn | s_return
	| s_cmd | s_expr | s_break | s_continue);
