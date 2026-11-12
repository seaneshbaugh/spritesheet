# frozen_string_literal: true

class ValidationError < StandardError
  def http_status
    422
  end
end
