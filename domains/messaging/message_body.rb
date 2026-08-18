module Messaging
  # Shared validation/normalization for any user-authored message body: the
  # match-gated chat message (Messaging::SendMessage) and the 🔥 Hook opener and
  # reply (Hooks::*). Body is untrusted input — NFC-normalized so equivalent
  # Unicode compares equal, whitespace-only rejected, length bounded — while emoji
  # and other codepoints are preserved verbatim. Raises Messaging::MessageError so
  # every surface maps a blank/oversized body to the same 422 code.
  module MessageBody
    def self.prepare(raw)
      content = raw.to_s.unicode_normalize(:nfc)
      raise MessageError, :message_blank if content.blank?
      raise MessageError, :message_too_long if content.length > Message::MAX_BODY_LENGTH

      content
    end
  end
end
