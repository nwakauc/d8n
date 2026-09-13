module Ai
  # This is a deliberately narrow immediate-safety redirect, not automated
  # moderation or a claim that the platform has contacted a human responder.
  module SafetyTriage
    PATTERN = /(?:\b(?:threaten(?:ed|ing)?|abuse(?:d|s)?|violence|violent|danger|unsafe|coerc(?:e|ed|ion)|forced marriage|scam|blackmail|rape|kidnap|suicid|self[- ]?harm)\b|\b(?:send|sent|borrow|loan|investment)\b.{0,30}\bmoney\b|\bmoney\b.{0,30}\b(?:send|borrow|loan|investment|request)\b|\b(?:he|she|e)\s+(?:dey|is)\s+(?:beat|beating|threaten|threatening)\b|\b(?:no|not)\s+(?:dey|feel)\s+safe\b)/i
    RESPONSE = "This sounds serious. Please prioritize your immediate safety: contact local emergency services or someone you trust nearby if you are in danger. You can also use D8N's report and block tools for dating-platform concerns."

    def self.requires_immediate_response?(content)
      content.match?(PATTERN)
    end
  end
end
