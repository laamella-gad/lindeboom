## The token kinds of a grammar, in the order of the generated `TokenKind`
## enum: EOF, literals used in parser rules, lexer rules, then `tokens { }`.
##
## A parser literal that is exactly the body of a lexer rule (`IF : 'if' ;`)
## is that rule's token instead of a token of its own, as in ANTLR.

import std/[sets, strutils, tables, unicode]
import ./[ast, idents]

type
  TokenSource* = enum
    tsEof, tsLiteral, tsRule, tsImaginary

  TokenInfo* = object
    name*: string    ## as written in the grammar: `EOF`, `'if'`, `ID`
    ident*: string   ## Nim enum identifier: `tkEOF`, `tkIf`, `tkID`
    source*: TokenSource
    text*: string    ## tsLiteral: the decoded literal
    rule*: int       ## tsRule: index into `Grammar.rules`
    pos*: SourcePos  ## declaration, or first use of a literal

  Vocabulary* = object
    tokens*: seq[TokenInfo]       ## index = token kind; 0 is EOF
    byName*: Table[string, int]   ## lexer rule or `tokens { }` name -> kind
    byLiteral*: Table[string, int] ## parser literal text -> kind

const punctNames = [
  ('!', "Bang"), ('"', "DQuote"), ('#', "Hash"), ('$', "Dollar"),
  ('%', "Percent"), ('&', "Amp"), ('\'', "Quote"), ('(', "LParen"),
  (')', "RParen"), ('*', "Star"), ('+', "Plus"), (',', "Comma"),
  ('-', "Minus"), ('.', "Dot"), ('/', "Slash"), (':', "Colon"),
  (';', "Semi"), ('<', "Lt"), ('=', "Eq"), ('>', "Gt"), ('?', "Question"),
  ('@', "At"), ('[', "LBracket"), ('\\', "Backslash"), (']', "RBracket"),
  ('^', "Caret"), ('`', "Backtick"), ('{', "LBrace"), ('|', "Pipe"),
  ('}', "RBrace"), ('~', "Tilde")]

func quoteLiteral*(text: string): string =
  ## `text` as a grammar literal: `'if'`, `'\n'`, `'\''`.
  result = "'"
  for r in text.runes:
    case int32(r)
    of int32('\''): result.add "\\'"
    of int32('\\'): result.add "\\\\"
    of int32('\n'): result.add "\\n"
    of int32('\r'): result.add "\\r"
    of int32('\t'): result.add "\\t"
    of 0 .. 8, 11, 12, 14 .. 31, 127:
      result.add "\\u" & toHex(int32(r), 4)
    else: result.add $r
  result.add "'"

func identPart(text: string): string =
  ## `'if'` -> `If`, `'**'` -> `StarStar`, `'é'` -> `U00E9`.
  var word = false
  for r in text.runes:
    let c = int32(r)
    if c < 128 and char(c) in IdentChars:
      if word: result.add char(c)
      else: result.add toUpperAscii(char(c))
      word = true
    else:
      word = false
      var name = ""
      for (p, n) in punctNames:
        if c == int32(p): name = n
      if name.len == 0: name = "U" & toHex(c, 4)
      result.add name

proc assignIdents(v: var Vocabulary) =
  ## Rule and `tokens { }` names come first, so a literal that would clash
  ## with one gets the numbered identifier.
  var idents: HashSet[string]
  for pass in [{tsEof, tsRule, tsImaginary}, {tsLiteral}]:
    for t in v.tokens.mitems:
      if t.source in pass:
        t.ident = uniqueIdent("tk" & (if t.source == tsLiteral: identPart(t.text) else: t.name),
          idents)

func aliasLiteral(r: Rule): string =
  ## The literal a lexer rule consists of, "" if it is anything more.
  if r.kind == rkLexer and not r.isFragment and r.alts.len == 1 and
      r.alts[0].commands.len == 0 and r.alts[0].body.items.len == 1:
    let e = r.alts[0].body.items[0]
    if e.kind == ekLiteral: result = e.text

proc buildVocabulary*(g: Grammar): Vocabulary =
  var aliases: Table[string, string]  # literal text -> lexer rule name
  for r in g.rules:
    let text = aliasLiteral(r)
    if text.len > 0 and text notin aliases: aliases[text] = r.name
  result.tokens.add TokenInfo(name: "EOF", source: tsEof)
  for r in g.rules:
    if r.kind == rkParser:
      for a in r.alts:
        for e in a.body.walk:
          if e.kind == ekLiteral and e.text notin aliases and
              e.text notin result.byLiteral:
            result.byLiteral[e.text] = result.tokens.len
            result.tokens.add TokenInfo(name: quoteLiteral(e.text),
              source: tsLiteral, text: e.text, pos: e.pos)
  for i, r in g.rules:
    if r.kind == rkLexer and not r.isFragment:
      result.byName[r.name] = result.tokens.len
      result.tokens.add TokenInfo(name: r.name, source: tsRule, rule: i,
        pos: r.pos)
  for t in g.tokens:
    result.byName[t.name] = result.tokens.len
    result.tokens.add TokenInfo(name: t.name, source: tsImaginary, pos: t.pos)
  for text, name in aliases:
    result.byLiteral[text] = result.byName[name]
  result.assignIdents()
