## Grammar AST produced by the `.ldb` front end.

import std/unicode
import ../diagnostics

export SourcePos

type
  ExprKind* = enum
    ekSeq       ## elements in order; empty means epsilon
    ekAlt       ## choice between `items`
    ekOpt       ## `x?`
    ekStar      ## `x*`
    ekPlus      ## `x+`
    ekNot       ## `~x`
    ekRuleRef   ## reference to a parser rule (lowercase)
    ekTokenRef  ## reference to a lexer rule, imaginary token or EOF
    ekLiteral   ## `'text'`
    ekCharSet   ## `[a-z]`
    ekRange     ## `'a'..'z'`
    ekWildcard  ## `.`

  RuneRange* = tuple[lo, hi: Rune]

  GExpr* = ref object
    pos*: SourcePos
    label*: string        ## element label, "" if none
    labelIsList*: bool    ## `+=` instead of `=`
    case kind*: ExprKind
    of ekSeq, ekAlt:
      items*: seq[GExpr]
    of ekOpt, ekStar, ekPlus, ekNot:
      inner*: GExpr
      greedy*: bool       ## false for `??`, `*?`, `+?`
    of ekRuleRef, ekTokenRef:
      name*: string
    of ekLiteral:
      text*: string       ## decoded, UTF-8
    of ekCharSet:
      ranges*: seq[RuneRange]
    of ekRange:
      lo*, hi*: Rune
    of ekWildcard:
      discard

  Assoc* = enum
    assocLeft, assocRight

  LexerCommandKind* = enum
    lcSkip, lcChannel, lcType

  LexerCommand* = object
    pos*: SourcePos
    kind*: LexerCommandKind
    arg*: string          ## channel name or token type

  Alternative* = object
    pos*: SourcePos
    body*: GExpr          ## always an `ekSeq`
    label*: string        ## `# name`, "" if none
    labelPos*: SourcePos
    assoc*: Assoc
    hasAssoc*: bool
    commands*: seq[LexerCommand]

  RuleKind* = enum
    rkParser, rkLexer

  Rule* = object
    pos*: SourcePos
    name*: string
    kind*: RuleKind
    isFragment*: bool
    alts*: seq[Alternative]

  GrammarOption* = object
    pos*: SourcePos
    name*, value*: string

  TokenDecl* = object
    pos*: SourcePos
    name*: string

  Bracket* = object
    pos*: SourcePos
    open*, close*: string

  IndentSetting* = object
    pos*: SourcePos
    value*: string        ## "" when not set

  Indentation* = object
    pos*: SourcePos
    newline*, indent*, dedent*, tabs*: IndentSetting
    brackets*: seq[Bracket]

  Grammar* = object
    name*: string
    pos*: SourcePos
    options*: seq[GrammarOption]
    tokens*: seq[TokenDecl]
    hasIndentation*: bool
    indentation*: Indentation
    rules*: seq[Rule]

func isLexerName*(name: string): bool =
  name.len > 0 and name[0] in {'A'..'Z'}

func newSeqExpr*(pos: SourcePos, items: seq[GExpr] = @[]): GExpr =
  GExpr(kind: ekSeq, pos: pos, items: items)

iterator walk*(e: GExpr): GExpr =
  ## Pre-order traversal of `e` and all sub-expressions.
  var stack = @[e]
  while stack.len > 0:
    let x = stack.pop()
    yield x
    case x.kind
    of ekSeq, ekAlt:
      for i in countdown(x.items.high, 0): stack.add x.items[i]
    of ekOpt, ekStar, ekPlus, ekNot:
      stack.add x.inner
    else:
      discard
