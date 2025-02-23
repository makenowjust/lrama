require "strscan"
require "lrama/report"

module Lrama
  # Lexer for parse.y
  class Lexer
    include Lrama::Report::Duration

    # s_value is semantic value
    Token = Struct.new(:type, :s_value, keyword_init: true) do
      Type = Struct.new(:id, :name, keyword_init: true)

      attr_accessor :line, :column, :referred
      # For User_code
      attr_accessor :references

      def to_s
        "#{super} line: #{line}, column: #{column}"
      end

      @i = 0
      @types = []

      def self.define_type(name)
        type = Type.new(id: @i, name: name.to_s)
        const_set(name, type)
        @types << type
        @i += 1
      end

      # Token types
      define_type(:P_expect)         # %expect
      define_type(:P_define)         # %define
      define_type(:P_printer)        # %printer
      define_type(:P_lex_param)      # %lex-param
      define_type(:P_parse_param)    # %parse-param
      define_type(:P_initial_action) # %initial-action
      define_type(:P_union)          # %union
      define_type(:P_token)          # %token
      define_type(:P_type)           # %type
      define_type(:P_nonassoc)       # %nonassoc
      define_type(:P_left)           # %left
      define_type(:P_right)          # %right
      define_type(:P_prec)           # %prec
      define_type(:User_code)        # { ... }
      define_type(:Tag)              # <int>
      define_type(:Number)           # 0
      define_type(:Ident_Colon)      # k_if:, k_if  : (spaces can be there)
      define_type(:Ident)            # api.pure, tNUMBER
      define_type(:Semicolon)        # ;
      define_type(:Bar)              # |
      define_type(:String)           # "str"
      define_type(:Char)             # '+'
    end

    # States
    #
    # See: https://www.gnu.org/software/bison/manual/html_node/Grammar-Outline.html
    Initial = 0
    Prologue = 1
    BisonDeclarations = 2
    GrammarRules = 3
    Epilogue = 4

    # Token types

    attr_reader :prologue, :bison_declarations, :grammar_rules, :epilogue,
                :bison_declarations_tokens, :grammar_rules_tokens

    def initialize(text)
      @text = text
      @state = Initial
      # Array of texts
      @prologue = []
      @bison_declarations = []
      @grammar_rules = []
      @epilogue = []

      #
      @bison_declarations_tokens = []
      @grammar_rules_tokens = []

      @debug = false

      report_duration(:lex) do
        lex_text
        lex_bison_declarations_tokens
        lex_grammar_rules_tokens
      end
    end

    private

    def create_token(type, s_value, line, column)
      t = Token.new(type: type, s_value: s_value)
      t.line = line
      t.column = column

      return t
    end

    # TODO: Remove this
    def lex_text
      @text.each_line.with_index(1) do |string, lineno|
        case @state
        when Initial
          # Skip until "%{"
          if string == "%{\n"
            @state = Prologue
            @prologue << ["", lineno]
            next
          end
        when Prologue
          # Between "%{" and "%}"
          if string == "%}\n"
            @state = BisonDeclarations
            @prologue << ["", lineno]
            next
          end

          @prologue << [string, lineno]
        when BisonDeclarations
          if string == "%%\n"
            @state = GrammarRules
            next
          end

          @bison_declarations << [string, lineno]
        when GrammarRules
          # Between "%%" and "%%"
          if string == "%%\n"
            @state = Epilogue
            next
          end

          @grammar_rules << [string, lineno]
        when Epilogue
          @epilogue << [string, lineno]
        else
          raise "Unknown state: #{@state}"
        end
      end
    end

    # See:
    #   * https://www.gnu.org/software/bison/manual/html_node/Decl-Summary.html
    #   * https://www.gnu.org/software/bison/manual/html_node/Symbol-Decls.html
    #   * https://www.gnu.org/software/bison/manual/html_node/Empty-Rules.html
    def lex_common(lines, tokens)
      line = lines.first[1]
      column = 0
      ss = StringScanner.new(lines.map(&:first).join)

      while !ss.eos? do
        case
        when ss.scan(/\n/)
          line += 1
          column = ss.pos
        when ss.scan(/\s+/)
          # skip
        when ss.scan(/;/)
          tokens << create_token(Token::Semicolon, ss[0], line, ss.pos - column)
        when ss.scan(/\|/)
          tokens << create_token(Token::Bar, ss[0], line, ss.pos - column)
        when ss.scan(/(\d+)/)
          tokens << create_token(Token::Number, Integer(ss[0]), line, ss.pos - column)
        when ss.scan(/(<[a-zA-Z0-9_]+>)/)
          tokens << create_token(Token::Tag, ss[0], line, ss.pos - column)
        when ss.scan(/([a-zA-Z_.][-a-zA-Z0-9_.]*)\s*:/)
          tokens << create_token(Token::Ident_Colon, ss[1], line, ss.pos - column)
        when ss.scan(/([a-zA-Z_.][-a-zA-Z0-9_.]*)/)
          tokens << create_token(Token::Ident, ss[0], line, ss.pos - column)
        when ss.scan(/%expect/)
          tokens << create_token(Token::P_expect, ss[0], line, ss.pos - column)
        when ss.scan(/%define/)
          tokens << create_token(Token::P_define, ss[0], line, ss.pos - column)
        when ss.scan(/%printer/)
          tokens << create_token(Token::P_printer, ss[0], line, ss.pos - column)
        when ss.scan(/%lex-param/)
          tokens << create_token(Token::P_lex_param, ss[0], line, ss.pos - column)
        when ss.scan(/%parse-param/)
          tokens << create_token(Token::P_parse_param, ss[0], line, ss.pos - column)
        when ss.scan(/%initial-action/)
          tokens << create_token(Token::P_initial_action, ss[0], line, ss.pos - column)
        when ss.scan(/%union/)
          tokens << create_token(Token::P_union, ss[0], line, ss.pos - column)
        when ss.scan(/%token/)
          tokens << create_token(Token::P_token, ss[0], line, ss.pos - column)
        when ss.scan(/%type/)
          tokens << create_token(Token::P_type, ss[0], line, ss.pos - column)
        when ss.scan(/%nonassoc/)
          tokens << create_token(Token::P_nonassoc, ss[0], line, ss.pos - column)
        when ss.scan(/%left/)
          tokens << create_token(Token::P_left, ss[0], line, ss.pos - column)
        when ss.scan(/%right/)
          tokens << create_token(Token::P_right, ss[0], line, ss.pos - column)
        when ss.scan(/%prec/)
          tokens << create_token(Token::P_prec, ss[0], line, ss.pos - column)
        when ss.scan(/{/)
          token, line = lex_user_code(ss, line, ss.pos - column, lines)
          tokens << token
        when ss.scan(/"/)
          string, line = lex_string(ss, "\"", line, lines)
          token = create_token(Token::String, string, line, ss.pos - column)
          tokens << token
        when ss.scan(/\/\*/)
          # TODO: Need to keep comment?
          line = lex_comment(ss, line, lines, "")
        when ss.scan(/'(.)'/)
          tokens << create_token(Token::Char, ss[0], line, ss.pos - column)
        when ss.scan(/'\\(.)'/) # '\\', '\t'
          tokens << create_token(Token::Char, ss[0], line, ss.pos - column)
        when ss.scan(/'\\(\d+)'/) # '\13'
          tokens << create_token(Token::Char, ss[0], line, ss.pos - column)
        when ss.scan(/%empty/)
          # skip
        else
          l = line - lines.first[1]
          split = ss.string.split("\n")
          col = ss.pos - split[0...l].join("\n").length
          raise "Parse error (unknown token): #{split[l]} \"#{ss.string[ss.pos]}\" (#{line}: #{col})"
        end
      end
    end

    def lex_bison_declarations_tokens
      lex_common(@bison_declarations, @bison_declarations_tokens)
    end

    def lex_user_code(ss, line, column, lines)
      first_line = line
      first_column = column
      debug("Enter lex_user_code: #{line}")
      brace_count = 1
      str = "{"
      # Array of [type, $n, tag, first column, last column]
      # TODO: Is it better to keep string, like "$$", and use gsub?
      references = []

      while !ss.eos? do
        case
        when ss.scan(/\n/)
          line += 1
        when ss.scan(/"/)
          string, line = lex_string(ss, "\"", line, lines)
          str << string
          next
        when ss.scan(/'/)
          string, line = lex_string(ss, "'", line, lines)
          str << string
          next
        when ss.scan(/\$(<[a-zA-Z0-9_]+>)?\$/) # $$, $<long>$
          tag = ss[1] ? create_token(Token::Tag, ss[1], line, str.length) : nil
          references << [:dollar, "$", tag, str.length, str.length + ss[0].length - 1]
        when ss.scan(/\$(<[a-zA-Z0-9_]+>)?(\d+)/) # $1, $2, $<long>1
          tag = ss[1] ? create_token(Token::Tag, ss[1], line, str.length) : nil
          references << [:dollar, Integer(ss[2]), tag, str.length, str.length + ss[0].length - 1]
        when ss.scan(/@\$/) # @$
          references << [:at, "$", nil, str.length, str.length + ss[0].length - 1]
        when ss.scan(/@(\d)+/) # @1
          references << [:at, Integer(ss[1]), nil, str.length, str.length + ss[0].length - 1]
        when ss.scan(/{/)
          brace_count += 1
        when ss.scan(/}/)
          brace_count -= 1

          debug("Return lex_user_code: #{line}")
          if brace_count == 0
            str << ss[0]
            user_code = Token.new(type: Token::User_code, s_value: str.freeze)
            user_code.line = first_line
            user_code.column = first_column
            user_code.references = references
            return [user_code, line]
          end
        when ss.scan(/\/\*/)
          str << ss[0]
          line = lex_comment(ss, line, lines, str)
        else
          # noop, just consume char
          str << ss.getch
          next
        end

        str << ss[0]
      end

      # Reach to end of input but brace does not match
      l = line - lines.first[1]
      raise "Parse error (brace mismatch): #{ss.string.split("\n")[l]} \"#{ss.string[ss.pos]}\" (#{line}: #{ss.pos})"
    end

    def lex_string(ss, terminator, line, lines)
      debug("Enter lex_string: #{line}")

      str = terminator.dup

      while (c = ss.getch) do
        str << c

        case c
        when "\n"
          line += 1
        when terminator
          debug("Return lex_string: #{line}")
          return [str, line]
        else
          # noop
        end
      end

      # Reach to end of input but quote does not match
      l = line - lines.first[1]
      raise "Parse error (quote mismatch): #{ss.string.split("\n")[l]} \"#{ss.string[ss.pos]}\" (#{line}: #{ss.pos})"
    end

    # TODO: Need to handle // style comment
    #
    # /*  */ style comment
    def lex_comment(ss, line, lines, str)
      while !ss.eos? do
        case
        when ss.scan(/\n/)
          line += 1
        when ss.scan(/\*\//)
          return line
        else
          str << ss.getch
          next
        end

        str << ss[0]
      end

      # Reach to end of input but quote does not match
      l = line - lines.first[1]
      raise "Parse error (comment mismatch): #{ss.string.split("\n")[l]} \"#{ss.string[ss.pos]}\" (#{line}: #{ss.pos})"
    end

    def lex_grammar_rules_tokens
      lex_common(@grammar_rules, @grammar_rules_tokens)
    end

    def debug(msg)
      return unless @debug
      puts "#{msg}\n"
    end
  end
end
