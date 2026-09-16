# frozen_string_literal: true

# Reads the REAL `scripts/date9ja/source_census.sql` and hands back its measures
# so a test can execute the committed SQL text rather than a copy of it. Written
# for the Pass-1 profile/preference value census (ord 200+), but deliberately
# generic: it parses the whole `census(ord, section, measure, source_count, note)`
# VALUES list, so later census extensions get the same coverage for free.
#
# This is a reader, not a second census framework: it never rewrites the SQL and
# never defines a measure of its own.
module Date9jaCensusSql
  SCRIPT_PATH = Rails.root.join("scripts/date9ja/source_census.sql")
  VALUES_MARKER = "WITH census(ord, section, measure, source_count, note) AS (\n  VALUES"

  Measure = Struct.new(:ord, :section, :name, :count_sql, :note_sql, keyword_init: true) do
    # One scalar SELECT that evaluates exactly what the census would emit for
    # this row. `NULL` is a valid expression on either side.
    def select_sql = "SELECT (#{count_sql}) AS source_count, (#{note_sql}) AS note"
  end

  module_function

  def source = @source ||= File.read(SCRIPT_PATH)

  def measures
    @measures ||= parse(source).freeze
  end

  def measure(ord) = measures.fetch(ord) { raise KeyError, "no census measure with ord #{ord}" }

  def measures_in(range) = measures.select { |ord, _| range.cover?(ord) }

  # ---------------------------------------------------------------------------

  def parse(sql)
    start = sql.index(VALUES_MARKER) or raise "census VALUES list not found in #{SCRIPT_PATH}"
    scanner = Scanner.new(sql, start + VALUES_MARKER.length)
    scanner.tuples.each_with_object({}) do |body, acc|
      fields = split_top_level(body)
      raise "census tuple has #{fields.length} fields, expected 5: #{body[0, 80]}" unless fields.length == 5

      ord = Integer(fields[0].strip)
      acc[ord] = Measure.new(
        ord:,
        section: unquote(fields[1]),
        name: unquote(fields[2]),
        count_sql: fields[3].strip,
        note_sql: fields[4].strip
      )
    end
  end

  def unquote(field)
    text = field.strip
    raise "expected a quoted literal, got #{text[0, 40]}" unless text.start_with?("'") && text.end_with?("'")

    text[1..-2].gsub("''", "'")
  end

  # Splits one tuple body on commas that are outside parens, string literals and
  # comments.
  def split_top_level(body)
    fields = []
    current = +""
    Scanner.new(body, 0).each_significant_char do |char, depth, literal|
      if char == "," && depth.zero? && !literal
        fields << current
        current = +""
      else
        current << char
      end
    end
    fields << current
    fields
  end

  # Minimal PostgreSQL-aware character walker: understands `--` line comments,
  # `'...'` literals (with `''` escapes) and `$tag$...$tag$` blocks, so a comma
  # or a parenthesis inside any of them is never mistaken for structure.
  class Scanner
    def initialize(sql, offset)
      @sql = sql
      @offset = offset
    end

    # Every depth-1 group of the VALUES list, returned as its inner text.
    def tuples
      found = []
      index = @offset
      while (index = next_tuple_start(index))
        finish = matching_close(index)
        found << @sql[(index + 1)...finish]
        index = finish + 1
      end
      found
    end

    def each_significant_char
      depth = 0
      walk(@offset, @sql.length) do |char, in_literal|
        depth += 1 if char == "(" && !in_literal
        depth -= 1 if char == ")" && !in_literal
        yield char, depth, in_literal
      end
    end

    private

    # The next `(` that opens a tuple, or nil once the VALUES list is closed by a
    # `)` at depth 0.
    def next_tuple_start(from)
      result = nil
      catch(:stop) do
        walk(from, @sql.length) do |char, in_literal, position|
          next if in_literal

          if char == "("
            result = position
            throw :stop
          elsif char == ")"
            throw :stop
          end
        end
      end
      result
    end

    def matching_close(open_index)
      depth = 0
      result = nil
      catch(:stop) do
        walk(open_index, @sql.length) do |char, in_literal, position|
          next if in_literal

          depth += 1 if char == "("
          if char == ")"
            depth -= 1
            if depth.zero?
              result = position
              throw :stop
            end
          end
        end
      end
      result or raise "unbalanced parentheses in #{SCRIPT_PATH} at offset #{open_index}"
    end

    # Yields (char, in_literal, position) for every character in [from, upto),
    # skipping comment bodies entirely.
    def walk(from, upto)
      index = from
      while index < upto
        char = @sql[index]

        if char == "-" && @sql[index + 1] == "-"
          index = (@sql.index("\n", index) || upto) + 1
          next
        end

        if char == "$" && (tag = dollar_tag(index))
          closing = @sql.index(tag, index + tag.length)
          stop = closing ? closing + tag.length : upto
          (index...stop).each { |position| yield @sql[position], true, position }
          index = stop
          next
        end

        if char == "'"
          stop = literal_end(index)
          (index...stop).each { |position| yield @sql[position], true, position }
          index = stop
          next
        end

        yield char, false, index
        index += 1
      end
    end

    def dollar_tag(index)
      match = @sql[index..].match(/\A\$[A-Za-z_][A-Za-z0-9_]*\$|\A\$\$/)
      match && match[0]
    end

    # Index just past the closing quote, honouring `''` escapes.
    def literal_end(open_index)
      index = open_index + 1
      while index < @sql.length
        if @sql[index] == "'"
          return index + 1 unless @sql[index + 1] == "'"

          index += 2
        else
          index += 1
        end
      end
      raise "unterminated string literal in #{SCRIPT_PATH} at offset #{open_index}"
    end
  end
end
