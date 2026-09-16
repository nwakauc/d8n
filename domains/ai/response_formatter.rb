module Ai
  # Consumer clients render assistant content as text, not guaranteed Markdown.
  # Keep provider replies legible without changing their meaning or inventing
  # structure: remove lightweight emphasis markers and place inline numbered
  # choices on their own lines.
  class ResponseFormatter
    def self.call(content)
      text = content.to_s.strip
      text = text.gsub(/\*\*([^*]+)\*\*/, "\\1").gsub(/__([^_]+)__/, "\\1")
      text = text.gsub(/(?<!\n)(?<!^)\s+(\d+\.\s+)/, "\n\\1")
      text.gsub(/\n{3,}/, "\n\n").strip
    end
  end
end
