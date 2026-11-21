# frozen_string_literal: true

require_relative '../config/processing_limits'

module ImageTools
  def self.run(name, directory:, limits: ProcessingLimits.current)
    tool = MiniMagick.public_send(name)

    tool.define "registry:temporary-path=#{directory}"

    yield tool

    tool.call(timeout: limits.command_seconds, warnings: false)
  end
end
