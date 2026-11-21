# frozen_string_literal: true

class ProcessingLimits
  DEFAULTS = {
    image_bytes: 32 * 1024 * 1024,
    request_bytes: 40 * 1024 * 1024,
    extraction_bytes: 40 * 1024 * 1024,
    image_count: 1024,
    archive_entries: 2048,
    image_pixels: 16_000_000,
    canvas_pixels: 16_000_000,
    dimension: 16_384,
    command_seconds: 30
  }.freeze

  attr_reader(*DEFAULTS.keys)

  def self.current
    @current ||= new
  end

  def initialize(**overrides)
    raise ArgumentError, 'Unknown processing limit' unless (overrides.keys - DEFAULTS.keys).empty?

    DEFAULTS.merge(overrides).each do |name, value|
      raise ArgumentError, 'Limits must be positive numbers' unless value.is_a?(Numeric) && value.positive?

      instance_variable_set("@#{name}", value)
    end

    freeze
  end
end
